-- The termination pass: every `while` and `repeat` loop in marked code needs a `---@decrease`, and so
-- does every verified function that calls itself, directly or through other verified functions. The
-- loop's encoding checks its measure on each iteration, and a call that stays in its caller's cycle
-- checks the callee's measure against the caller's.
--
--   local g
--   local function f(n) … g(n - 1) … end   -- f and g form one cycle
--   function g(n) … f(n) … h(n) … end      -- h is outside it, unless it calls f or g
--
-- An `---@unsafe` function's body is unmarked code, so it adds no calls to the graph. Its promise to
-- terminate covers any call back into verified code.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'

--- The cycles of the call graph of verified functions. Functions in one cycle map to the same id, and
--- a function in no cycle has no entry.
--- @class Termination
--- @field cycle table<NodeId, NodeId> the smallest Function id in each recursive Function's cycle

local M = {}

--- Returns the verified functions by id, and the verified functions that each one calls, from the
--- callee table of `types`.
--- @param src SrcArena
--- @param idx NodeIndex
--- @param info TypeInfo
--- @return NodeId[] fns
--- @return table<NodeId, NodeId[]> calls
local function call_graph(src, idx, info)
    local fns = {}
    local calls = {}
    for _, id in ipairs(idx.by_tag.Function or {}) do
        local fn = src.nodes[id] --[[@as SrcFunction]]
        if idx.unit[fn.body] == id then
            fns[#fns + 1] = id
            calls[id] = {}
        end
    end
    for _, id in ipairs(idx.by_tag.Call or {}) do
        local caller = idx.unit[id]
        local callee = info.callees[id]
        if calls[caller] ~= nil and callee ~= nil and calls[callee] ~= nil then
            calls[caller][#calls[caller] + 1] = callee
        end
    end
    return fns, calls
end

--- Returns the functions that `from` reaches through one call or more.
--- @param calls table<NodeId, NodeId[]>
--- @param from NodeId
--- @return table<NodeId, boolean>
local function reached(calls, from)
    local seen = {}
    local todo = { from }
    while #todo > 0 do
        local f = todo[#todo]
        todo[#todo] = nil
        for _, g in ipairs(calls[f]) do
            if not seen[g] then
                seen[g] = true
                todo[#todo + 1] = g
            end
        end
    end
    return seen
end

--- Returns whether the call `id` is in the body of a quantifier: a Function inside its unit's.
--- @param src SrcArena
--- @param idx NodeIndex
--- @param id NodeId
--- @return boolean
local function in_quantifier(src, idx, id)
    local p = idx.parent[id]
    while p ~= 0 and p ~= idx.unit[id] do
        if src.nodes[p].tag == 'Function' then
            return true
        end
        p = idx.parent[p]
    end
    return false
end

--- Reports the loops in marked code that have no measure, and the recursive functions whose measure is
--- missing or has another number of expressions than the first one in its cycle. A call in a
--- quantifier's body that stays in its caller's cycle is reported too: its measure would have to be
--- checked under the bound variables, where no check can go.
--- @param src SrcArena
--- @param idx NodeIndex
--- @param info TypeInfo
--- @return Termination result
--- @return Diag[] diags
function M.run(src, idx, info)
    local diags = {}
    for _, tag in ipairs { 'While', 'Repeat' } do
        for _, id in ipairs(idx.by_tag[tag] or {}) do
            local loop = src.nodes[id] --[[@as SrcWhile|SrcRepeat]]
            if idx.unit[id] ~= 0 and not arena.has_directive(src, loop, 'ClvDecrease') then
                diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'missing-decrease' })
            end
        end
    end

    local fns, calls = call_graph(src, idx, info)
    --- @type table<NodeId, table<NodeId, boolean>>
    local reach = {}
    for _, f in ipairs(fns) do
        reach[f] = reached(calls, f)
    end
    --- @type Termination
    local out = { cycle = {} }
    -- the number of expressions in the first measure of each cycle, by the cycle's name
    --- @type table<NodeId, integer>
    local length = {}
    for _, f in ipairs(fns) do
        if reach[f][f] then
            -- f's cycle is every g with reach[f][g] and reach[g][f]. reach is transitive, so on
            -- recursive functions this is an equivalence and the cycles are its classes. all members of
            -- one get the same name: the class's first function by id, which may be f itself.
            -- fns is in id order, so the first g that passes is the class's smallest id, and every member
            -- stops at the same one.
            -- that means for f->g->h->f, g compares length of measure list with f's. if f's is unset, then
            -- h will compare with g's.
            --
            -- loops that share a function, as in f -> g -> f and f -> h -> f, make one class. a check
            -- at each call in it is enough: a run that never ends is an endless chain of calls in one
            -- class, and each call decreases the measure in one well-founded order, so no chain is
            -- endless
            local name = f
            for _, g in ipairs(fns) do
                if reach[f][g] and reach[g][f] then
                    name = g
                    break
                end
            end
            out.cycle[f] = name
            local d = arena.directives(src, src.nodes[f] --[[@as SrcFunction]], 'ClvDecrease')[1]
            if d == nil then
                diags[#diags + 1] = diag.at_node('E-misplaced-directive', f, { 'missing-function-decrease' })
            else
                local n = #(src.nodes[d] --[[@as SrcClvDecrease]]).measures
                length[name] = length[name] or n
                if n ~= length[name] then
                    diags[#diags + 1] = diag.at_node('E-misplaced-directive', d, { 'decrease-length' })
                end
            end
        end
    end
    for _, id in ipairs(idx.by_tag.Call or {}) do
        local cycle = out.cycle[idx.unit[id]]
        if cycle ~= nil and cycle == out.cycle[info.callees[id]] and in_quantifier(src, idx, id) then
            diags[#diags + 1] = diag.at_node('E-unsupported-feature', id, { 'quantifier-recursion' })
        end
    end
    return out, diags
end

return M
