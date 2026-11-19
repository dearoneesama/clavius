local arena = require 'clavius.ir.arena'
local driver = require 'clavius.driver'

-- Clavius trusts the shipped specs without proof, so this test checks them against LuaJIT (design §10):
-- each function is called on every combination of edge values that meets its `---@pre`s. It must raise
-- no error, return a value of its declared type, and meet its `---@post`s.
--
-- The clauses are read from the spec files and run as Lua. Spec arithmetic is exact and LuaJIT's isn't,
-- but the edge values are within ±2^53, where doubles hold integers exactly, and the shipped clauses only
-- compare and negate them, so running a clause gives its exact value. A spec whose clauses compute more
-- than that needs this test to guard against rounding first.

local B = 2 ^ 53

--- The edge values of each type a spec's parameters may have.
--- @type table<string, any[]>
local EDGES = {
    int53 = { -B, -B + 1, -B / 2, -3, -2, -1, 0, 1, 2, 3, B / 2, B - 1, B },
    boolean = { false, true },
}

--- Returns whether `v` is a value of type `ty`.
--- @param ty string
--- @param v any
--- @return boolean
local function has_type(ty, v)
    if ty == 'int53' then
        return type(v) == 'number' and v == math.floor(v) and -B <= v and v <= B
    end
    return type(v) == 'boolean'
end

--- The spec of one shipped function, as this test runs it.
--- @class ShippedSpec
--- @field name string e.g. `math.min`
--- @field params string[]
--- @field types string[] the parameters' types
--- @field result string the value's name in `---@post`s
--- @field result_type string|nil
--- @field pres string[] the conditions, as written
--- @field posts string[]

--- Returns the shipped specs, read through the interfaces stage.
--- @return ShippedSpec[]
local function shipped()
    local c = driver.run_until('interfaces', '', 1)
    assert.are.same({}, c.diags)
    local iface = assert(c.iface)
    local out = {}
    for name, fn_id in pairs(iface.functions) do
        local fn = c.src.nodes[fn_id] --[[@as SrcFunction]]
        local text = c.files[c.src.spans[fn_id].file].text
        --- @param id NodeId
        --- @return string
        local function source(id)
            local s = c.src.spans[id]
            return text:sub(s.start, s.finish)
        end
        local spec = { name = name, params = {}, types = {}, result = 'result', result_type = nil, pres = {}, posts = {} }
        for i, p in ipairs(fn.params) do
            spec.params[i] = (c.src.nodes[p] --[[@as SrcBinder]]).name
            spec.types[i] = assert(iface.info.types[p])
        end
        local r = arena.directives(c.src, fn, 'ClvReturn')[1]
        if r ~= nil then
            spec.result = (c.src.nodes[r] --[[@as SrcClvReturn]]).name or 'result'
            spec.result_type = iface.info.types[r]
        end
        for _, d in ipairs(arena.directives(c.src, fn, 'ClvPre')) do
            spec.pres[#spec.pres + 1] = source((c.src.nodes[d] --[[@as SrcClvPre]]).cond)
        end
        for _, d in ipairs(arena.directives(c.src, fn, 'ClvPost')) do
            spec.posts[#spec.posts + 1] = source((c.src.nodes[d] --[[@as SrcClvPost]]).cond)
        end
        out[#out + 1] = spec
    end
    --- @param a ShippedSpec
    --- @param b ShippedSpec
    --- @return boolean
    local function by_name(a, b)
        return a.name < b.name
    end
    table.sort(out, by_name)
    return out
end

--- Compiles a clause over `names` into a function.
--- @param names string[]
--- @param cond string
--- @return fun(...): boolean
local function clause(names, cond)
    local f = assert(loadstring(('return function(%s) return %s end'):format(table.concat(names, ', '), cond)))
    return f()
end

--- Returns every combination of the edge values of `types`.
--- @param types string[]
--- @return any[][]
local function combinations(types)
    local out = { {} }
    for i, ty in ipairs(types) do
        local next_out = {}
        for _, prefix in ipairs(out) do
            for _, v in ipairs(assert(EDGES[ty], ty)) do
                local args = { unpack(prefix, 1, i - 1) }
                args[i] = v
                next_out[#next_out + 1] = args
            end
        end
        out = next_out
    end
    return out
end

--- Shows a value in a message, with integers in full.
--- @param v any
--- @return string
local function show(v)
    if type(v) == 'number' and v == math.floor(v) then
        return ('%.0f'):format(v)
    end
    return tostring(v)
end

--- Returns the library function a spec is for, such as the real `math.min`.
--- @param name string
--- @return function
local function real(name)
    local v = _G
    for part in name:gmatch '[^.]+' do
        v = v[part]
    end
    return v
end

describe('the shipped specs', function()
    it('run on LuaJIT', function()
        -- `jit` is LuaJIT's, so it isn't a Lua 5.1 global
        local jit = rawget(_G, 'jit')
        assert.is_not_nil(jit, 'these checks are about LuaJIT, so run them with --lua=luajit')
        assert.is_true(jit.version:match '^LuaJIT 2%.1' ~= nil, jit.version)
    end)

    it('cover the library functions that marked code may call', function()
        local names = {}
        for _, spec in ipairs(shipped()) do
            names[#names + 1] = spec.name
        end
        assert.are.same({ 'math.abs', 'math.max', 'math.min' }, names)
    end)

    for _, spec in ipairs(shipped()) do
        it(('%s raises no error and keeps its contract at the edges of its preconditions'):format(spec.name), function()
            local pres = {}
            for i, cond in ipairs(spec.pres) do
                pres[i] = clause(spec.params, cond)
            end
            local names = { unpack(spec.params) }
            names[#names + 1] = spec.result
            local posts = {}
            for i, cond in ipairs(spec.posts) do
                posts[i] = clause(names, cond)
            end
            local f = real(spec.name)
            local calls = 0
            for _, args in ipairs(combinations(spec.types)) do
                local n = #spec.params
                local meets = true
                for _, pre in ipairs(pres) do
                    meets = meets and pre(unpack(args, 1, n))
                end
                if meets then
                    calls = calls + 1
                    local shown_args = {}
                    for i = 1, n do
                        shown_args[i] = show(args[i])
                    end
                    local shown = ('%s(%s)'):format(spec.name, table.concat(shown_args, ', '))
                    local ok, value = pcall(f, unpack(args, 1, n))
                    assert(ok, ('%s raised: %s'):format(shown, tostring(value)))
                    if spec.result_type then
                        assert(has_type(spec.result_type, value), ('%s returned %s'):format(shown, show(value)))
                    end
                    local with_value = { unpack(args, 1, n) }
                    with_value[n + 1] = value
                    for i, post in ipairs(posts) do
                        assert(post(unpack(with_value, 1, n + 1)), ('%s = %s breaks `%s`'):format(shown, show(value), spec.posts[i]))
                    end
                end
            end
            assert.is_true(calls > 0, 'no edge value meets the preconditions')
        end)
    end
end)
