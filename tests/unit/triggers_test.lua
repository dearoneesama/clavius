local driver = require 'clavius.driver'
local markers = require 'support.markers'
local stringx = require 'pl.stringx'

-- the spec functions that the programs below call
local SPECS = [=[
--[[@spec
---@param i Int
---@return Int
local function f(i) return i end

---@param i Int
---@param j Int
---@return Int
local function g(i, j) return i + j end

---@param i Int
---@return Int
local function enc(i) return i end

---@param i Int
---@return Int
local function inv(i) return i end

---@param i Int
---@return boolean
local function p(i) return i > 0 end

---@param i Int
---@return boolean
local function q(i) return i > 1 end

---@param x boolean
---@return boolean
local function b(x) return x end

---@param i Int
---@param x boolean
---@return Int
local function h(i, x) return i end
]]
]=]

--- Runs the stages up to `triggers` on a region that holds `body` after the spec functions above, and
--- returns the trigger of each quantifier as the source text of its terms. An inner quantifier comes
--- before the one around it, as in the node arena.
--- @param body string
--- @return string[]
local function chosen(body)
    local text = ('%s---@clavius begin\n%s\n---@clavius end\n'):format(SPECS, body)
    local c = driver.run_until('triggers', text, 1)
    assert.are.same({}, c.diags)
    local res = assert(c.res)
    local groups = assert(c.triggers).groups
    local quantifiers = {}
    for id in ipairs(c.src.nodes) do
        if res.prelude[id] == 'forall' or res.prelude[id] == 'exists' then
            quantifiers[#quantifiers + 1] = id
        end
    end
    local out = {}
    for i, id in ipairs(quantifiers) do
        local terms = {}
        for j, t in ipairs(groups[id]) do
            local span = c.src.spans[t]
            terms[j] = text:sub(span.start, span.finish)
        end
        out[i] = table.concat(terms, ' ')
    end
    return out
end

describe('triggers', function()
    it('picks the smallest call that mentions every bound variable, the first of equal ones', function()
        local found = chosen [[
            ---@assert forall(function(x) return inv(enc(x)) == x end)
            ---@assert forall(function(i) return implies(p(i), q(i)) end)
            ---@assert forall(function(i, j) return implies(f(i) < f(j), g(i, j) > 0) end)
        ]]
        assert.are.same({ 'enc(x)', 'p(i)', 'g(i, j)' }, found)
    end)

    it('joins calls when no one call mentions every bound variable', function()
        local found = chosen [[
            ---@assert forall(function(i, j) return implies(i <= j, f(i) <= f(j)) end)
            ---@assert exists(function(i, j) return f(i) + f(i) == f(j) end)
            ---@assert forall(function(i, j, k) return implies(f(i) < f(j), f(j) < f(k)) end)
        ]]
        assert.are.same({ 'f(i) f(j)', 'f(i) f(j)', 'f(i) f(j) f(k)' }, found)
    end)

    it('joins the smallest set of calls, the first of equal ones', function()
        local found = chosen [[
            ---@assert forall(function(i, j) return enc(f(i)) == f(j) and f(i) > 0 end)
            ---@assert forall(function(i, j) return implies(p(i) and q(j), p(j)) end)
        ]]
        assert.are.same({ 'f(i) f(j)', 'p(i) q(j)' }, found)
    end)

    it('skips calls with arithmetic over a bound variable, but not over other values', function()
        local found = chosen [[
            local n = 3
            ---@assert forall(function(i) return f(i + 1) > f(i) end)
            ---@assert forall(function(i) return g(i, n + 1) > g(-i, n) end)
        ]]
        assert.are.same({ 'f(i)', 'g(i, n + 1)' }, found)
    end)

    it('triggers on a boolean bound variable', function()
        local found = chosen [[
            ---@assert forall(function(x) return b(x) or not b(x) end)
        ]]
        assert.are.same({ 'b(x)' }, found)
    end)

    it('sees through parentheses', function()
        local found = chosen [[
            ---@assert forall(function(i) return f((i)) > 0 end)
        ]]
        assert.are.same({ 'f((i))' }, found)
    end)

    it("reads a body's local as its value", function()
        local found = chosen [[
            ---@assert forall(function(i, j) local d = f(i) return g(d, j) > 0 end)
        ]]
        assert.are.same({ 'g(d, j)' }, found)
    end)

    it('leaves a call that mentions an inner bound variable to the inner quantifier', function()
        local found = chosen [[
            ---@assert forall(function(i) return forall(function(j) return implies(i <= j, f(i) <= f(j)) end) end)
            ---@assert forall(function(i) return implies(p(i), forall(function(j) return g(i, j) >= 0 end)) end)
        ]]
        -- id order (child first)
        assert.are.same({ 'f(j)', 'f(i)', 'g(i, j)', 'p(i)' }, found)
    end)

    it('reports a quantifier that no call can trigger', function()
        markers.expect_diags('triggers', SPECS .. stringx.dedent [=[
            ---@clavius begin
            ---@assert forall(function(i) return implies(i > 0, i + i > i) end) --! E-trigger
            ---@assert forall(function(i) return f(i + 1) > 0 end) --! E-trigger
            ---@assert forall(function(i) return f((i + 1)) > 0 end) --! E-trigger
            ---@assert forall(function(i) local d = i + 1 return f(d) > 0 end) --! E-trigger
            -- arithmetic over i in one argument rules out the whole call
            ---@assert forall(function(i) return g(i, i + 1) > 0 end) --! E-trigger
            -- a comparison can't sit in a trigger
            ---@assert forall(function(i) return h(i, i > 0) > 0 end) --! E-trigger
            -- every call over i mentions j too, so only one quantifier over both can use it
            ---@assert forall(function(i) return forall(function(j) return g(i, j) >= 0 end) end) --! E-trigger
            ---@clavius end
            ]=])
    end)

    it('takes the terms that `trigger(e)` marks, together, in place of its own choice', function()
        local found = chosen [[
            ---@assert forall(function(i) return implies(p(i), trigger(q(i))) end)
            -- without the marks, g(i, j) alone would be the trigger
            ---@assert forall(function(i, j) return implies(i <= j, trigger(f(i)) <= trigger(f(j)) + g(i, j)) end)
            ---@assert forall(function(i) return trigger(f(i + 1)) > f(i) end)
            -- a mark sees through a body's locals and parentheses
            ---@assert forall(function(i) local d = f(i) return trigger(d) > 0 or trigger((p(i))) end)
        ]]
        assert.are.same({ 'q(i)', 'f(i) f(j)', 'f(i + 1)', 'd (p(i))' }, found)
    end)

    it('gives a mark to the innermost quantifier around it whose bound variables it mentions', function()
        local found = chosen [[
            ---@assert forall(function(i) return forall(function(j) return implies(trigger(p(i)), g(i, j) >= 0) end) end)
            ---@assert exists(function(i) return implies(p(i), forall(function(j) return trigger(g(i, j)) >= f(j) end)) end)
        ]]
        assert.are.same({ 'g(i, j)', 'p(i)', 'g(i, j)', 'p(i)' }, found)
    end)

    it("reports a mark outside a quantifier's body, one no trigger can use, and marks that miss a variable", function()
        markers.expect_diags('triggers', SPECS .. stringx.dedent [=[
            ---@clavius begin
            ---@assert trigger(p(1)) --! E-trigger
            ---@assert forall(function(i) return trigger(f(0)) <= f(i) end) --! E-trigger
            ---@assert forall(function(i) return trigger(i) <= f(i) end) --! E-trigger
            ---@assert forall(function(i, j) return trigger(f(i)) <= f(j) end) --! E-trigger
            -- a bad mark is the one error, though the other mark misses i
            ---@assert forall(function(i, j) return trigger(i) <= trigger(f(j)) end) --! E-trigger
            ---@clavius end
            ]=])
    end)
end)
