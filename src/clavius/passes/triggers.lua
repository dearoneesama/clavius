-- The triggers pass: picks the terms that tell the solver when to use each quantifier. The solver
-- uses a quantified fact only for the values in a term that matches its trigger, so every quantifier
-- needs one. Boogie also requires a trigger to mention every bound variable.
--
--   forall(function(i, j) return implies(i <= j, f(i) <= f(j)) end)   -- { f(i), f(j) }
--
-- A candidate is a spec function call that mentions a bound variable with no arithmetic over it,
-- since the solver matches `f(i + 1)` only against a term written `f(x + 1)`. The trigger is the
-- smallest candidate that mentions every bound variable. When none does, it is the smallest set of
-- candidates that together mention them all.

local diag = require 'clavius.ir.diag'
local source_nodes = require 'clavius.ir.source_nodes'
local support = require 'clavius.ir.support'

--- @class Triggers
--- @field groups table<NodeId, NodeId[]> the Call nodes of each `forall` and `exists` call's trigger
--- @field locals table<NodeId, NodeId> the value of each quantifier body's `local`, by its Binder

--- A term that a trigger may use, with the variables it mentions. Its key and size count each
--- `local` as its value, and the key tells equal terms apart.
--- @class TriggerTerm
--- @field ok boolean whether a trigger may use it at all
--- @field key string the term as text
--- @field size integer its number of nodes
--- @field mentions NodeId[] the bound variables it mentions
--- @field arith NodeId[] the bound variables it mentions under arithmetic

--- A candidate for the trigger of one quantifier.
--- @class TriggerCandidate
--- @field id NodeId the Call
--- @field size integer
--- @field covers NodeId[] the quantifier's bound variables that it mentions

--- @class TriggersState
--- @field src SrcArena
--- @field res Resolution
--- @field info TypeInfo
--- @field binder table<NodeId, boolean> the bound variables of every quantifier
--- @field locals table<NodeId, NodeId>

local M = {}

--- Adds each of `from` that `into` doesn't hold to it.
--- @param into NodeId[]
--- @param from NodeId[]
--- @mut into
local function union(into, from)
    for _, x in ipairs(from) do
        local found = false
        for _, y in ipairs(into) do
            found = found or x == y
        end
        if not found then
            into[#into + 1] = x
        end
    end
end

--- Returns what a trigger can make of the expression `id`. A `local` of a quantifier's body stands
--- for its value.
---
--- e.g. `f(i + 1)` => { ok = true, key = '(f$1 (add i$2 1))', size = 4, mentions = { i }, arith = { i } }
--- @param st TriggersState
--- @param id NodeId
--- @decrease id
--- @return TriggerTerm
local function term(st, id)
    local n = st.src.nodes[id]
    --- @type TriggerTerm
    local t = { ok = true, key = n.tag, size = 1, mentions = {}, arith = {} }
    if n.tag == 'Id' then
        local decl = st.res.decl[id]
        if decl ~= nil and st.locals[decl] ~= nil then
            return term(st, st.locals[decl])
        elseif decl ~= nil and st.binder[decl] then -- param
            t.mentions[1] = decl
        end
        t.key = decl and st.res.names[decl] or n.name
        return t
    elseif n.tag == 'Literal' then
        t.key = n.text or n.kind
        return t
    elseif n.tag == 'Paren' then
        return term(st, n.expr)
    end
    local spec_call = n.tag == 'Call' and st.res.kinds[st.info.callees[id]] == 'spec'
    local arith = (n.tag == 'BinOp' and support.ARITH[n.op]) or (n.tag == 'UnOp' and n.op == 'unm')
    if not (spec_call or arith) then
        t.ok = false
        return t
    end
    local keys = { spec_call and st.res.names[st.res.decl[n.func]] or n.op }
    for _, kid in ipairs(source_nodes.children(n)) do
        if kid ~= n.func then
            local k = term(st, kid)
            keys[#keys + 1] = k.key
            t.ok = t.ok and k.ok
            t.size = t.size + k.size
            union(t.mentions, k.mentions)
            -- not just `k.arith`, which holds only what is under arithmetic below the child: in
            -- `x + 1`, the leaf `x` has nothing there, and it is this `+` that puts `x` under it
            union(t.arith, arith and k.mentions or k.arith)
        end
    end
    t.key = ('(%s)'):format(table.concat(keys, ' '))
    return t
end

--- Adds the spec function calls under `id` to `out` in source order.
--- @param src SrcArena
--- @param res Resolution
--- @param info TypeInfo
--- @param id NodeId
--- @param out NodeId[]
--- @mut out
--- @decrease id
local function calls(src, res, info, id, out)
    local n = src.nodes[id]
    if n.tag == 'Call' and res.kinds[info.callees[id]] == 'spec' then
        out[#out + 1] = id
    end
    for _, kid in ipairs(source_nodes.children(n)) do
        calls(src, res, info, kid, out)
    end
end

--- Adds the bound variables of the quantifiers under `id` to `out`.
--- @param st TriggersState
--- @param id NodeId
--- @param out table<NodeId, boolean>
--- @mut out
--- @decrease id
local function inner_binders(st, id, out)
    local n = st.src.nodes[id]
    if n.tag == 'Call' and (st.res.prelude[id] == 'forall' or st.res.prelude[id] == 'exists') then
        for _, p in
            ipairs((st.src.nodes[n.args[1]] --[[@as SrcFunction]]).params)
        do
            out[p] = true
        end
    end
    for _, kid in ipairs(source_nodes.children(n)) do
        inner_binders(st, kid, out)
    end
end

--- Returns whether `list` holds every one of `keys`.
--- @param list NodeId[]
--- @param keys NodeId[]
--- @return boolean
local function covers_all(list, keys)
    local all = {}
    union(all, list)
    union(all, keys)
    return #all == #list
end

--- Returns the candidates for the trigger of the quantifier whose function is `fn`, in source order
--- and each term once. A call that mentions a bound variable of a quantifier inside the body is
--- left to that one.
--- @param st TriggersState
--- @param fn SrcFunction
--- @return TriggerCandidate[]
local function candidates(st, fn)
    -- e.g. forall(fn = function(i) return forall(function(j) return f(i) <= g(i+1, j) end) end)
    -- own = { i = true }
    -- inner = { j = true }
    -- found = { f(i), g(i+1, j) }
    -- out = { { id = f(i), size = 2, covers = { i } } }, since g(i, j) mentions j
    -- out for inner = { { id = g(i+1, j), size = 4, covers = { j } } }
    local own = {}
    for _, p in ipairs(fn.params) do
        own[p] = true
    end
    local inner = {}
    inner_binders(st, fn.body, inner)
    local found = {}
    calls(st.src, st.res, st.info, fn.body, found)
    local out = {}

    local seen = {}
    for _, c in ipairs(found) do
        local t = term(st, c)
        local under_arith = {}
        for _, b in ipairs(t.arith) do
            under_arith[b] = true
        end
        local covers = {}
        local usable = t.ok
        for _, b in ipairs(t.mentions) do
            -- a call over an inner quantifier's variable is that one's to use. arithmetic over an
            -- own variable makes the term fire only where the solver already has that arithmetic,
            -- so Verus and Dafny's automatic choice skip such terms too. an outer variable is fixed
            -- here, so arithmetic over it is fine
            usable = usable and not inner[b] and not (own[b] and under_arith[b])
            if own[b] then
                covers[#covers + 1] = b
            end
        end
        -- the same term written twice is one candidate
        if usable and #covers > 0 and not seen[t.key] then
            seen[t.key] = true
            out[#out + 1] = { id = c, size = t.size, covers = covers }
        end
    end
    return out
end

--- Adds to `out` every set of `k` indices from `from` to `n`, each in increasing order, after the ones
--- in `chosen`. The sets come in lexicographic order.
--- @param n integer
--- @param k integer
--- @param from integer
--- @param chosen integer[]
--- @param out integer[][]
--- @mut chosen
--- @mut out
--- @decrease k
local function subsets(n, k, from, chosen, out)
    if k == 0 then
        out[#out + 1] = { unpack(chosen) }
        return
    end
    for i = from, n do
        chosen[#chosen + 1] = i
        subsets(n, k - 1, i + 1, chosen, out)
        chosen[#chosen] = nil
    end
end

--- Returns the smallest set of `k` candidates of `cans` that mention every one of `binders`. The
--- smallest has the fewest nodes in total, and of equal sets the first in source order wins. Returns
--- nil when there is none.
--- @param cans TriggerCandidate[]
--- @param binders NodeId[]
--- @param k integer
--- @return TriggerCandidate[]|nil
local function best_set(cans, binders, k)
    --- @type integer[][]
    local all = {}
    subsets(#cans, k, 1, {}, all)
    local best, best_size = nil, 0
    for _, indices in ipairs(all) do
        local set, covered, size = {}, {}, 0
        for j, i in ipairs(indices) do
            set[j] = cans[i]
            union(covered, cans[i].covers)
            size = size + cans[i].size
        end
        if covers_all(covered, binders) and (best == nil or size < best_size) then
            best, best_size = set, size
        end
    end
    return best
end

--- Returns the trigger of the quantifier whose function is `fn`, or nil when it has none.
--- @param st TriggersState
--- @param fn SrcFunction
--- @return NodeId[]|nil
local function choose(st, fn)
    local cans = candidates(st, fn)
    -- every can covers at least one of var. in a smallest cover, each term must add a var no other
    -- term covers, or it could be dropped. so with n bound variables, we never need more than n terms.
    for k = 1, #fn.params do
        local set = best_set(cans, fn.params, k)
        if set ~= nil then
            local ids = {}
            for i, c in ipairs(set) do
                ids[i] = c.id
            end
            return ids
        end
    end
    return nil
end

--- Chooses the trigger of every `forall` and `exists` call that `resolve` found.
--- @param src SrcArena
--- @param idx NodeIndex
--- @param res Resolution
--- @param info TypeInfo
--- @return Triggers result
--- @return Diag[] diags
function M.run(src, idx, res, info)
    --- @type TriggersState
    local st = { src = src, res = res, info = info, binder = {}, locals = {} }
    local quantifiers = {}
    for _, id in ipairs(idx.by_tag.Call or {}) do
        if res.prelude[id] == 'forall' or res.prelude[id] == 'exists' then
            quantifiers[#quantifiers + 1] = id
            local call = src.nodes[id] --[[@as SrcCall]]
            local fn = src.nodes[call.args[1]] --[[@as SrcFunction]]
            for _, p in ipairs(fn.params) do
                st.binder[p] = true
            end
        end
    end

    -- the locals of quantifiers' bodies, which a trigger can only name by their values
    for _, id in ipairs(idx.by_tag.Local or {}) do
        local p = idx.parent[id]
        while p ~= 0 and src.nodes[p].tag ~= 'Function' do
            p = idx.parent[p]
        end
        if p ~= 0 and res.prelude[idx.parent[p]] ~= nil then
            local n = src.nodes[id] --[[@as SrcLocal]]
            for i, name in ipairs(n.names) do
                st.locals[name] = n.values[i]
            end
        end
    end

    --- @type Triggers
    local out = { groups = {}, locals = st.locals }
    local diags = {}
    for _, id in ipairs(quantifiers) do
        local call = src.nodes[id] --[[@as SrcCall]]
        local fn = src.nodes[call.args[1]] --[[@as SrcFunction]]
        local group = choose(st, fn)
        if group == nil then
            diags[#diags + 1] = diag.at_node('E-trigger', id, { 'no-trigger' })
        else
            out.groups[id] = group
        end
    end
    return out, diags
end

return M
