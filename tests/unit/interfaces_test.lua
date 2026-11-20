local arena = require 'clavius.ir.arena'
local driver = require 'clavius.driver'
local markers = require 'support.markers'
local stringx = require 'pl.stringx'

--- Runs the stages up to `stage` on a Lua file and one project `---@meta` file, and returns the
--- diagnostics as `file line code`.
--- @param stage string
--- @param text string
--- @param meta string
--- @return string[]
local function diags(stage, text, meta)
    text = stringx.dedent(text)
    meta = stringx.dedent(meta)
    local c = driver.run_until(stage, text, 1, { { name = 'host.lua', text = meta } })
    local out = {}
    for i, d in ipairs(c.diags) do
        local span = d.span or c.spans[d.node]
        local f = c.files[span.file]
        local line = arena.line_col(f.text, arena.line_starts(f.text), span.start)
        out[i] = ('%s %d %s'):format(span.file == c.file and 'main' or f.name, line, d.code)
    end
    table.sort(out)
    return out
end

describe('interfaces', function()
    it('reads the contracts of the functions in a `---@meta` file, and nothing else in it', function()
        local meta = [=[
            ---@meta host

            ---@extern
            ---@param n integer
            ---@pre n > 0
            ---@post result < n
            ---@return integer
            function host.f(n) end

            -- not a function: ignored, so verified code can't use it
            ---@extern
            host.limit = 10
        ]=]
        local c = driver.run_until('interfaces', 'local x = 1', 1, { { name = 'host.lua', text = stringx.dedent(meta) } })
        assert.are.same({}, c.diags)
        local iface = assert(c.iface)
        local fn = assert(iface.functions['host.f'])
        assert.are.equal('extern', iface.kinds[fn])
        assert.are.equal('stdlib', iface.kinds[iface.functions['math.min']])
        assert.is_nil(iface.functions['host.limit'])
        -- the parameter and the value are typed, so a call can lower the contract
        local n = c.src.nodes[fn] --[[@as SrcFunction]]
        assert.are.equal('int53', iface.info.types[n.params[1]])
    end)

    it("needs `---@extern` on the project's functions, and only a spec's directives", function()
        assert.are.same(
            { 'host.lua 2 E-misplaced-directive', 'host.lua 4 E-unsupported-directive' },
            diags(
                'interfaces',
                'local x = 1',
                [=[
                ---@meta
                function host.f() end
                ---@extern
                ---@unsafe
                function host.g() end
                ]=]
            )
        )
    end)

    it('rejects marked code in a `---@meta` file, and a name declared twice', function()
        assert.are.same(
            { 'host.lua 10 E-misplaced-directive', 'host.lua 2 E-misplaced-directive', 'host.lua 8 E-misplaced-directive' },
            diags(
                'interfaces',
                'local x = 1',
                [=[
                ---@meta
                ---@clavius begin
                local y = 1
                ---@clavius end
                ---@extern
                function host.f() end
                ---@extern
                function math.min(a, b) end
                ---@extern
                function host.f() end
                ]=]
            )
        )
    end)

    it("types a spec's signature and contract", function()
        assert.are.same(
            { 'host.lua 4 E-type-mismatch', 'host.lua 5 E-unsupported-type' },
            diags(
                'interfaces',
                'local x = 1',
                [=[
                ---@meta
                ---@extern
                ---@param n integer
                ---@pre n + true
                ---@param s string
                function host.f(n, s) end
                ]=]
            )
        )
    end)

    it('lowers a spec whose contract divides', function()
        local meta = stringx.dedent [=[
            ---@meta
            ---@extern
            ---@param n integer
            ---@pre n % 2 == 0
            ---@post result == math.floor(n / 2)
            ---@return integer
            function host.half(n) end
        ]=]
        local text = stringx.dedent [=[
            ---@clavius begin
            local h = host.half(6)
            assert(h == 3)
            ---@clavius end
        ]=]
        -- tests/e2e/verify/extern.lua verifies such a call
        local c = driver.run_until('validate', text, 1, { { name = 'host.lua', text = meta } })
        assert.are.same({}, c.diags)
    end)

    it('lets marked code call what the run declares, with as many arguments as parameters', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local a = math.min(1, 2)
            local b = math.min(1) --! E-unsupported-feature
            local c = math.floor(a) --! E-unsupported-call
            local d = math.sqrt(4) --! E-unsupported-call
            local f = math.max --! E-unsupported-call
            local e = host.f(1) --! E-banned-global
            ---@clavius end
            ]=]
        )
    end)

    it('sees through a library alias, but not a host function alias', function()
        local text = stringx.dedent [=[
            local floor = math.floor
            local m = math.min
            local h = host.f
            ---@clavius begin
            local a = floor(7 / 2)
            local b = m(a, 1)
            ---@clavius end
        ]=]
        local meta = '---@meta\n---@extern\n---@param n integer\nfunction host.f(n) end\n'
        local c = driver.run_until('types', text, 1, { { name = 'host.lua', text = meta } })
        assert.are.same({}, c.diags)
        local ops = {}
        for id, op in pairs(assert(c.info).ops) do
            local s = c.src.spans[id]
            ops[#ops + 1] = ('%s %s'):format(text:sub(s.start, s.finish), op.op)
        end
        table.sort(ops)
        assert.are.same({ 'floor(7 / 2) int.floordiv', 'm(a, 1) call' }, ops)
        assert.are.same({ 'main 6 E-unsupported-feature' }, diags('resolve', text:gsub('m%(a, 1%)', 'h(a)'), meta))
    end)

    it('records the resolved operation of each call and idiom', function()
        local text = stringx.dedent [=[
            ---@clavius
            ---@param a integer
            ---@param b integer
            ---@pre b ~= 0
            ---@post result == math.floor(a / b)
            ---@return integer
            local function q(a, b)
                return math.floor((a) / b) + a % b + math.abs(a) * 0
            end
            ---@clavius begin
            local x = q(1, 2)
            ---@clavius end
        ]=]
        local c = driver.run_until('types', text, 1)
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local found = {}
        for id, op in pairs(info.ops) do
            local s = c.src.spans[id]
            local callee = op.callee and c.src.spans[op.callee].file or 0
            found[#found + 1] = ('%s %s %s %s'):format(text:sub(s.start, s.finish), op.op, callee, tostring(op.trusted))
        end
        table.sort(found)
        assert.are.same({
            'a % b int.mod 0 false',
            'math.abs(a) call 2 true',
            'math.floor((a) / b) int.floordiv 0 false',
            'math.floor(a / b) int.floordiv 0 false',
            'q(1, 2) call 1 false',
        }, found)
    end)
end)
