local driver = require 'clavius.driver'
local markers = require 'support.markers'
local types = require 'clavius.passes.types'

describe('types', function()
    it('types number literals by their spelling', function()
        local cases = {
            { '0', 'int53' },
            { '007', 'int53' },
            { '0xff', 'int53' },
            { '0X1F', 'int53' },
            { '9007199254740992', 'int53' },
            { '0x20000000000000', 'int53' },
            { '0x0020000000000000', 'int53' },
            { '9007199254740993', 'f64' },
            { '0x20000000000001', 'f64' },
            { '1.0', 'f64' },
            { '1e3', 'f64' },
            { '.5', 'f64' },
            { '0x1p4', 'f64' },
            { '1LL', 'i64' },
            { '1ULL', 'u64' },
            { '1llu', 'u64' },
            { '1i', 'complex' },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], types.number_type(c[1]), c[1])
        end
    end)

    it('gives each local the type of its initializer', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, 1 < 2
            local y = x
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            -- the shipped specs follow the file in the run's arena
            if n.tag == 'Binder' and c.src.spans[id].file == c.file then
                found[#found + 1] = ('%s %s'):format(res.names[id], info.types[id])
            end
        end
        assert.are.same({ 'x$1 int53', 'p$2 boolean', 'y$3 int53' }, found)
    end)

    it('rejects unsupported types', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local a = 1.5 --! E-unsupported-type
            local b = 1LL --! E-unsupported-type
            local c = 1ULL --! E-unsupported-type
            local d = 1i --! E-unsupported-type
            local e = 9007199254740993 --! E-unsupported-type
            local f = 'text' --! E-unsupported-type
            local g = nil --! E-unsupported-type
            local h = -0x20000000000001 --! E-unsupported-type
            ---@clavius end
            ]=]
        )
    end)

    it('checks operands and values against their types', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, true
            local a = x + p --! E-type-mismatch
            local b = p < x --! E-type-mismatch
            local c = -p --! E-type-mismatch
            local d = x == p --! E-type-mismatch
            x = p --! E-type-mismatch
            p = 1 --! E-type-mismatch
            local e = x * 2 - -x
            local f = x <= 3 and not p or x ~= 0
            local g = p == (x > 1)
            x = e
            p = f
            ---@clavius end
            ]=]
        )
    end)

    it('accepts only booleans as conditions', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, true
            if x then end --! E-unsupported-feature
            assert(x) --! E-unsupported-feature
            local a = p and x --! E-unsupported-feature
            local b = x or p --! E-unsupported-feature
            local c = not x --! E-unsupported-feature
            if p then elseif x < 2 then end
            assert(p)
            local d = p and x < 2
            local e = x == 1 or not p
            local f = not (p and d)
            ---@clavius end
            ]=]
        )
    end)

    it('does not type the messages of assert and error', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            assert(true, 'message')
            error('message', 1.5)
            ---@clavius end
            ]=]
        )
    end)

    it('reports an error once, not again in what uses it', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local a = 1.5 --! E-unsupported-type
            local b = a + 1
            local c = b < 2 and true
            ---@clavius end
            ]=]
        )
    end)
    it('types parameters and values from `---@param` and `---@return`', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius
            ---@param n integer
            ---@param on boolean
            ---@return int53 sum
            local function f(n, on)
                return n
            end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local found = {}
        for id, ty in pairs(assert(c.info).types) do
            local n = c.src.nodes[id]
            if (n.tag == 'Binder' or n.tag == 'ClvReturn') and c.src.spans[id].file == c.file then
                found[#found + 1] = ('%s %s'):format(n.name, ty)
            end
        end
        table.sort(found)
        assert.are.same({ 'n int53', 'on boolean', 'sum int53' }, found)
    end)

    it('rejects types in signatures that this version does not support', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius
            ---@param s string
            --! E-unsupported-type
            ---@return Seq<int53>
            --! E-unsupported-type
            local function f(s, untyped) --! E-unsupported-type
                return 1
            end
            ]=]
        )
    end)

    it('checks returns, clauses and calls against the contracts', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius
            ---@param n integer
            ---@pre n
            --! E-unsupported-feature
            local function none(n)
                return n --! E-type-mismatch
            end
            ---@clavius
            ---@return boolean
            local function flag()
                if true then
                    return --! E-type-mismatch
                end
                return 1 --! E-type-mismatch
            end
            ---@clavius begin
            none(true) --! E-type-mismatch
            local x = none(1) --! E-type-mismatch
            local y = flag()
            ---@clavius end
            ]=]
        )
    end)

    it('checks measures, and calls to functions defined below against their signatures', function()
        markers.expect_diags(
            'types',
            [=[
            local g
            ---@clavius begin
            ---@param n integer
            ---@param on boolean
            ---@decrease n, on
            --! E-type-mismatch
            ---@return integer
            local function f(n, on)
                return g(on) --! E-type-mismatch E-type-mismatch
            end
            ---@param n integer
            ---@return boolean
            function g(n)
                return n > 0
            end
            local x = g(1)
            ---@clavius end
            ]=]
        )
    end)

    it('checks loop conditions, bounds, invariants and measures', function()
        local c = markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local n = 1
            local on = true
            ---@invariant n
            --! E-unsupported-feature
            ---@decrease on
            --! E-type-mismatch
            while n do end --! E-unsupported-feature
            ---@invariant on
            ---@decrease n, on
            --! E-type-mismatch
            repeat local m = n until m --! E-unsupported-feature
            for i = on, 2, 1.5 do end --! E-type-mismatch E-unsupported-type
            ---@invariant i
            --! E-unsupported-feature
            for i = 1, n do
                local k = i
            end
            ---@clavius end
            ]=]
        )
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' and (n.name == 'i' or n.name == 'k') then
                found[#found + 1] = ('%s %s'):format(res.names[id], info.types[id])
            end
        end
        assert.are.same({ 'i$4 int53', 'i$5 int53', 'k$6 int53' }, found)
    end)
end)
