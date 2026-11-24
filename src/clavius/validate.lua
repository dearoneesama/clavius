-- Checks a core program before it is printed. Every node must be in a place its kind belongs:
-- e.g. units are at the top;
--   variable declarations are in a unit's `vars`;
--   statements are in statement lists;
--   terms, which are pure, are everywhere else;
--   every `Check` must refer to an obligation of a known kind;
--   every `Assume` must refer to an assumption with an allowed justification;
--   a `back_edge` `Assume`, which assumes `false`, must end its statement list;
--   every `Exit` must be inside a `Block` with its label;
--   the `Block` labels in a unit must differ.
-- For a core program elaborated from Lua, it also checks coverage: every source node in marked code that
-- can fail at runtime, or that a contract applies to, has a `Check` for each obligation it needs.
-- A failure is a bug in Clavius, not in the program being verified.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local obligation = require 'clavius.ir.obligation'

local M = {}

--- @param core CoreArena
--- @param vars NodeId[]
--- @param diags Diag[]
--- @mut diags
local function check_vars(core, vars, diags)
    for _, var in ipairs(vars) do
        local v = core.nodes[var]
        if v.tag ~= 'VarDecl' then
            diags[#diags + 1] = diag.at_node('E-internal-node', var, { v.tag, 'variable declaration' })
        end
    end
end

--- @param core CoreArena
--- @param id NodeId
--- @param diags Diag[]
--- @mut diags
--- @decrease id
local function check_term(core, id, diags)
    local n = core.nodes[id]
    if n.tag == 'Var' or n.tag == 'Int' or n.tag == 'Bool' then
        return
    elseif n.tag == 'BinOp' then
        check_term(core, n.lhs, diags)
        check_term(core, n.rhs, diags)
    elseif n.tag == 'Not' then
        check_term(core, n.arg, diags)
    elseif n.tag == 'Ite' then
        check_term(core, n.cond, diags)
        check_term(core, n.if_true, diags)
        check_term(core, n.if_false, diags)
    elseif n.tag == 'Let' then
        check_term(core, n.value, diags)
        check_term(core, n.body, diags)
    elseif n.tag == 'App' then
        for _, a in ipairs(n.args) do
            check_term(core, a, diags)
        end
    elseif n.tag == 'Forall' then
        check_vars(core, n.vars, diags)
        for _, t in ipairs(n.triggers) do
            local trigger = core.nodes[t]
            if trigger.tag == 'Trigger' then
                for _, term in ipairs(trigger.terms) do
                    check_term(core, term, diags)
                end
            else
                diags[#diags + 1] = diag.at_node('E-internal-node', t, { trigger.tag, 'trigger' })
            end
        end
        check_term(core, n.body, diags)
    else
        diags[#diags + 1] = diag.at_node('E-internal-node', id, { n.tag, 'term' })
    end
end

--- The tables that `Check` and `Assume` nodes refer to.
--- @class ValidateTables
--- @field obligations Obligation[]
--- @field assumptions Assumption[]

--- The source program that a core program was elaborated from.
--- @class ValidateSource
--- @field src SrcArena
--- @field index NodeIndex
--- @field callees table<NodeId, NodeId> the Function node that each call of a local function calls
--- @field cycle table<NodeId, NodeId> the smallest Function id in each recursive Function's cycle

--- One obligation that a source node needs: its kind, and the clause for a contract kind or 0.
--- @class NeededKey
--- @field kind ObligationKind
--- @field clause NodeId

--- The `Block` labels of one unit.
--- @class ValidateLabels
--- @field open table<string, boolean> labels of the Blocks around the current statement
--- @field used table<string, boolean> labels of the unit's Blocks so far

--- @param core CoreArena
--- @param ids NodeId[]
--- @param tables ValidateTables
--- @param checked table<integer, boolean> the obligations that a `Check` in a unit names
--- @param labels ValidateLabels
--- @param diags Diag[]
--- @mut checked
--- @mut labels
--- @mut diags
local function check_statements(core, ids, tables, checked, labels, diags)
    for i, id in ipairs(ids) do
        local n = core.nodes[id]
        if n.tag == 'Assign' then
            check_term(core, n.value, diags)
        elseif n.tag == 'Assume' then
            local a = tables.assumptions[n.assumption]
            if a == nil or not obligation.JUSTIFICATIONS[a.kind] then
                diags[#diags + 1] = diag.at_node('E-internal-assume', id, { tostring(n.assumption) })
            elseif a.kind == 'back_edge' and i < #ids then
                -- the path ends here, so a Check after it would hold vacuously
                diags[#diags + 1] = diag.at_node('E-internal-back-edge', id, { tostring(n.assumption) })
            end
            check_term(core, n.cond, diags)
        elseif n.tag == 'Check' then
            local o = tables.obligations[n.obligation]
            if o == nil or not obligation.OBLIGATION_KINDS[o.kind] then
                diags[#diags + 1] = diag.at_node('E-internal-check', id, { tostring(n.obligation) })
            end
            checked[n.obligation] = true
            check_term(core, n.cond, diags)
        elseif n.tag == 'Branch' then
            check_term(core, n.cond, diags)
            check_statements(core, n.then_body, tables, checked, labels, diags)
            check_statements(core, n.else_body, tables, checked, labels, diags)
        elseif n.tag == 'Choice' then
            check_statements(core, n.first, tables, checked, labels, diags)
            check_statements(core, n.second, tables, checked, labels, diags)
        elseif n.tag == 'Block' then
            -- Boogie labels are per procedure, so a reused label would make an Exit ambiguous
            if labels.used[n.label] then
                diags[#diags + 1] = diag.at_node('E-internal-label', id, { n.label })
            end
            labels.used[n.label] = true
            labels.open[n.label] = true
            check_statements(core, n.body, tables, checked, labels, diags)
            labels.open[n.label] = nil
        elseif n.tag == 'Exit' then
            -- a goto to any other label could jump backwards or into a block
            if not labels.open[n.label] then
                diags[#diags + 1] = diag.at_node('E-internal-exit', id, { n.label })
            end
        elseif n.tag == 'Havoc' then -- luacheck: ignore 542
            -- nothing
        else
            diags[#diags + 1] = diag.at_node('E-internal-node', id, { n.tag, 'statement' })
        end
    end
end

local RANGE_CHECKED = { add = true, sub = true, mul = true }

--- Adds a key for each contract clause in `clauses`.
--- @param keys NeededKey[]
--- @param kind ObligationKind
--- @param clauses NodeId[]
--- @mut keys
local function add_clauses(keys, kind, clauses)
    for _, c in ipairs(clauses) do
        keys[#keys + 1] = { kind = kind, clause = c }
    end
end

--- Returns the obligations that the source node `id` in marked code needs. This follows from what
--- `clavius.ir.support` lets marked code use: every `+`, `-` and `*` is on `int53`, every call is to
--- `assert`, `error`, a local function or, in proof code, `assume`, and every `return` is in a verified
--- function.
--- @param source ValidateSource
--- @param id NodeId
--- @return NeededKey[]
local function needed(source, id)
    local src = source.src
    local n = src.nodes[id]
    -- ghost code never runs, so its arithmetic is exact
    local ghost = source.index.ghost[id] ~= 0
    local keys = {}
    if n.tag == 'BinOp' and RANGE_CHECKED[n.op] and not ghost then
        keys[1] = { kind = 'range', clause = 0 }
    elseif n.tag == 'Call' and source.callees[id] ~= nil then
        local callee = src.nodes[source.callees[id]] --[[@as SrcFunction]]
        add_clauses(keys, 'pre', arena.directives(src, callee, 'ClvPre'))
        -- a call that stays in its caller's cycle checks the callee's measure
        local cycle = source.cycle[source.index.unit[id]]
        if cycle ~= nil and cycle == source.cycle[source.callees[id]] then
            add_clauses(keys, 'decrease', arena.directives(src, callee, 'ClvDecrease'))
        end
    elseif n.tag == 'Call' then
        local callee = src.nodes[n.func]
        local name = callee.tag == 'Id' and callee.name
        -- an `assume` proves nothing
        if name ~= 'assume' then
            keys[1] = { kind = name == 'assert' and 'assert' or 'unreachable', clause = 0 }
        end
    elseif n.tag == 'Return' then
        local fn = src.nodes[source.index.unit[id]] --[[@as SrcFunction]]
        add_clauses(keys, 'post', arena.directives(src, fn, 'ClvPost'))
    elseif n.tag == 'ClvAssert' then
        keys[1] = { kind = 'assert', clause = 0 }
    elseif n.tag == 'Function' and ghost and src.nodes[source.index.ghost[id]].tag == 'ClvSpec' then -- luacheck: ignore 542
        -- every path through a spec function returns
    elseif n.tag == 'Function' and arena.has_directive(src, n, 'ClvReturn') then
        keys[1] = { kind = 'missing_return', clause = 0 }
    elseif n.tag == 'Function' then
        add_clauses(keys, 'post', arena.directives(src, n, 'ClvPost'))
    elseif n.tag == 'While' or n.tag == 'Repeat' or n.tag == 'Fornum' then
        if n.tag == 'Fornum' then
            if n.step ~= nil and arena.nonzero_literal(src, n.step) == nil then
                keys[#keys + 1] = { kind = 'for_step', clause = 0 }
            end
            -- the counter's range is an invariant too, with no clause
            if not ghost then
                keys[#keys + 1] = { kind = 'for_bound', clause = 0 }
            end
            keys[#keys + 1] = { kind = 'invariant_entry', clause = 0 }
            keys[#keys + 1] = { kind = 'invariant_preserved', clause = 0 }
        end
        local invariants = arena.directives(src, n, 'ClvInvariant')
        add_clauses(keys, 'invariant_entry', invariants)
        add_clauses(keys, 'invariant_preserved', invariants)
        add_clauses(keys, 'decrease', arena.directives(src, n, 'ClvDecrease'))
    end
    return keys
end

--- Reports each source node in marked code that lacks a checked obligation it needs. No core node exists
--- for it, so the diagnostic's span is the source node's.
--- @param source ValidateSource
--- @param tables ValidateTables
--- @param checked table<integer, boolean> the obligations that a `Check` in a unit names
--- @param diags Diag[]
--- @mut diags
local function check_coverage(source, tables, checked, diags)
    -- node -> kind -> clause, or 0 -> present
    --- @type table<NodeId, table<string, table<NodeId, boolean>>>
    local have = {}
    for id, o in ipairs(tables.obligations) do
        if checked[id] then
            have[o.node] = have[o.node] or {}
            have[o.node][o.kind] = have[o.node][o.kind] or {}
            have[o.node][o.kind][o.clause or 0] = true
        end
    end
    for _, tag in ipairs { 'BinOp', 'Call', 'Return', 'While', 'Repeat', 'Fornum', 'ClvAssert' } do
        for _, id in ipairs(source.index.by_tag[tag] or {}) do
            if source.index.unit[id] ~= 0 then
                for _, key in ipairs(needed(source, id)) do
                    local kinds = have[id] and have[id][key.kind]
                    if not (kinds and kinds[key.clause]) then
                        diags[#diags + 1] = diag.at_span('E-internal-coverage', source.src.spans[id], { tag, key.kind })
                    end
                end
            end
        end
    end
    -- a verified function's end
    for _, id in ipairs(source.index.by_tag.Function or {}) do
        if source.index.unit[source.src.nodes[id].body] == id then
            for _, key in ipairs(needed(source, id)) do
                local kinds = have[id] and have[id][key.kind]
                if not (kinds and kinds[key.clause]) then
                    diags[#diags + 1] = diag.at_span('E-internal-coverage', source.src.spans[id], { 'Function', key.kind })
                end
            end
        end
    end
end

--- Returns a diagnostic for every misplaced node, unchecked `Check`, unjustified `Assume`, stray `Exit`
--- and reused `Block` label in the declarations and units in program order. With the source program, it
--- then reports the obligations missing from it. The result is empty when the program is valid.
--- @param core CoreArena
--- @param decls NodeId[]
--- @param units NodeId[]
--- @param obligations Obligation[]
--- @param assumptions Assumption[]
--- @param source ValidateSource|nil
--- @return Diag[] diags
function M.run(core, decls, units, obligations, assumptions, source)
    local diags = {}
    for _, id in ipairs(decls) do
        local n = core.nodes[id]
        if n.tag == 'FunDecl' then
            check_vars(core, n.params, diags)
        elseif n.tag == 'Axiom' then
            check_term(core, n.cond, diags)
        elseif n.tag ~= 'SortDecl' then
            diags[#diags + 1] = diag.at_node('E-internal-node', id, { n.tag, 'declaration' })
        end
    end
    --- @type ValidateTables
    local tables = { obligations = obligations, assumptions = assumptions }
    --- @type table<integer, boolean>
    local checked = {}
    for _, unit in ipairs(units) do
        local n = core.nodes[unit]
        if n.tag == 'Unit' then
            check_vars(core, n.vars, diags)
            check_statements(core, n.body, tables, checked, { open = {}, used = {} }, diags)
        else
            diags[#diags + 1] = diag.at_node('E-internal-node', unit, { n.tag, 'unit' })
        end
    end
    if source ~= nil then
        check_coverage(source, tables, checked, diags)
    end
    return diags
end

return M
