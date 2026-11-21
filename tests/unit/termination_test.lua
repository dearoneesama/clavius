local markers = require 'support.markers'

--- Returns the name that the definition of the Function `id` gives it.
--- @param c CompilerContext
--- @param id NodeId
--- @return string
local function name_of(c, id)
    local def = c.src.nodes[assert(c.index).parent[id]]
    local named = def.tag == 'Set' and def.targets[1] or def.binder
    return c.src.nodes[named].name
end

--- Returns each recursive function of the context's cycle table with the function its cycle is named
--- by, as sorted `f first` lines.
--- @param c CompilerContext
--- @return string[]
local function cycles(c)
    local found = {}
    for f, first in pairs(assert(c.termination).cycle) do
        found[#found + 1] = ('%s %s'):format(name_of(c, f), name_of(c, first))
    end
    table.sort(found)
    return found
end

describe('termination', function()
    it('needs a measure on every `while` and `repeat` loop in marked code', function()
        markers.expect_diags(
            'termination',
            [=[
            local n = 1
            while n > 0 do n = n - 1 end
            ---@unsafe
            local function g()
                while true do end
            end
            ---@clavius begin
            local m = 3
            while m > 0 do m = m - 1 end --! E-misplaced-directive
            repeat m = m + 1 until m > 5 --! E-misplaced-directive
            ---@decrease m
            while m > 0 do m = m - 1 end
            for i = 1, 3 do end
            ---@clavius end
            ---@clavius
            local function f()
                local k = 0
                while k < 3 do k = k + 1 end --! E-misplaced-directive
            end
            ]=]
        )
    end)

    it('needs a measure on every recursive function, with as many expressions in each cycle', function()
        -- two cycles, even with odd and spin alone; once only calls into one
        --
        --   once ─▶ even ─▶ odd ─▶ spin ─┐
        --           ▲       │       ▲    │
        --           └───────┘       └────┘
        --
        -- unmarked and trusted aren't verified, so they aren't in the graph
        local c = markers.expect_diags(
            'termination',
            [=[
            local function unmarked(n) return unmarked(n) end
            ---@unsafe
            ---@param n integer
            local function trusted(n) return trusted(n) end
            local odd
            ---@clavius begin
            ---@param n integer
            local function spin(n) --! E-misplaced-directive
                spin(n)
            end
            ---@param n integer
            ---@decrease n
            local function even(n)
                odd(n)
            end
            ---@param n integer
            ---@decrease n, 0
            --! E-misplaced-directive
            function odd(n)
                even(n)
                spin(n)
                trusted(n)
            end
            ---@param n integer
            local function once(n)
                even(n)
            end
            once(1)
            ---@clavius end
            ]=]
        )
        assert.are.same({ 'even even', 'odd even', 'spin spin' }, cycles(c))
    end)

    it('follows a cycle through three functions, and names cycles apart from what they call and their callers', function()
        -- two cycles, first to third and spin alone; helper and caller have smaller ids but are in neither
        --
        --             ┌────────────────────┐
        --             ▼                    │
        --   caller ─▶ first ─▶ second ─▶ third
        --    │        │
        --    │        └─▶ helper
        --    │
        --    └─▶ spin ─┐
        --         ▲    │
        --         └────┘
        local c = markers.expect_diags(
            'termination',
            [=[
            local first, second, third, spin
            ---@clavius begin
            ---@param n integer
            local function helper(n) end
            -- defined before both cycles and calls into each, so it names neither
            ---@param n integer
            local function caller(n)
                first(n)
                spin(n)
            end
            ---@param n integer
            ---@decrease n
            function first(n)
                helper(n)
                second(n)
            end
            ---@param n integer
            ---@decrease n
            function second(n)
                third(n)
            end
            ---@param n integer
            ---@decrease n
            function third(n)
                first(n)
            end
            ---@param n integer
            ---@decrease n
            function spin(n)
                spin(n)
            end
            ---@clavius end
            ]=]
        )
        assert.are.same({ 'first first', 'second first', 'spin spin', 'third first' }, cycles(c))
    end)

    it('puts two loops through one function into one cycle, whose measures all have one length', function()
        -- two loops through f make one cycle
        --
        --   ┌──▶ g ──┐
        --   │        │
        --   f ◀──────┤
        --   │        │
        --   └──▶ h ──┘
        local c = markers.expect_diags(
            'termination',
            [=[
            local g, h
            ---@clavius begin
            ---@param n integer
            ---@decrease n, 1
            local function f(n)
                g(n)
                h(n)
            end
            ---@param n integer
            ---@decrease n, 0
            function g(n)
                f(n)
            end
            -- h never calls g, but shares a cycle with it through f
            ---@param n integer
            ---@decrease n
            --! E-misplaced-directive
            function h(n)
                f(n)
            end
            ---@clavius end
            ]=]
        )
        assert.are.same({ 'f f', 'g f', 'h f' }, cycles(c))
    end)
end)
