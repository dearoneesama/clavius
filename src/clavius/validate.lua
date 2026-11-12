-- Checks a core program before it is printed. Every node must be in a place its kind belongs:
-- e.g. units are at the top;
--   variable declarations are in a unit's `vars`;
--   statements are in statement lists;
--   terms, which are pure, are everywhere else;
--   every `Check` must refer to an obligation of a known kind;
--   every `Assume` must refer to an assumption with an allowed justification;
--   every `Exit` must be inside a `Block` with its label;
--   the `Block` labels in a unit must differ.
-- A failure is a bug in Clavius, not in the program being verified.

local diag = require 'clavius.ir.diag'
local obligation = require 'clavius.ir.obligation'

local M = {}

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
    else
        diags[#diags + 1] = diag.at_node('E-internal-node', id, { n.tag, 'term' })
    end
end

--- The tables that `Check` and `Assume` nodes refer to.
--- @class ValidateTables
--- @field obligations Obligation[]
--- @field assumptions Assumption[]

--- The `Block` labels of one unit.
--- @class ValidateLabels
--- @field open table<string, boolean> labels of the Blocks around the current statement
--- @field used table<string, boolean> labels of the unit's Blocks so far

--- @param core CoreArena
--- @param ids NodeId[]
--- @param tables ValidateTables
--- @param labels ValidateLabels
--- @param diags Diag[]
--- @mut labels
--- @mut diags
local function check_statements(core, ids, tables, labels, diags)
    for i = 1, #ids do
        local id = ids[i]
        local n = core.nodes[id]
        if n.tag == 'Assign' then
            check_term(core, n.value, diags)
        elseif n.tag == 'Assume' then
            local a = tables.assumptions[n.assumption]
            if a == nil or not obligation.JUSTIFICATIONS[a.kind] then
                diags[#diags + 1] = diag.at_node('E-internal-assume', id, { tostring(n.assumption) })
            end
            check_term(core, n.cond, diags)
        elseif n.tag == 'Check' then
            local o = tables.obligations[n.obligation]
            if o == nil or not obligation.OBLIGATION_KINDS[o.kind] then
                diags[#diags + 1] = diag.at_node('E-internal-check', id, { tostring(n.obligation) })
            end
            check_term(core, n.cond, diags)
        elseif n.tag == 'Branch' then
            check_term(core, n.cond, diags)
            check_statements(core, n.then_body, tables, labels, diags)
            check_statements(core, n.else_body, tables, labels, diags)
        elseif n.tag == 'Choice' then
            check_statements(core, n.first, tables, labels, diags)
            check_statements(core, n.second, tables, labels, diags)
        elseif n.tag == 'Block' then
            -- Boogie labels are per procedure, so a reused label would make an Exit ambiguous
            if labels.used[n.label] then
                diags[#diags + 1] = diag.at_node('E-internal-label', id, { n.label })
            end
            labels.used[n.label] = true
            labels.open[n.label] = true
            check_statements(core, n.body, tables, labels, diags)
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

--- Returns a diagnostic for every misplaced node, unchecked `Check`, unjustified `Assume`, stray
--- `Exit` and reused `Block` label in the units in program order. The result is empty when the program is valid.
--- @param core CoreArena
--- @param units NodeId[]
--- @param obligations Obligation[]
--- @param assumptions Assumption[]
--- @return Diag[] diags
function M.run(core, units, obligations, assumptions)
    local diags = {}
    local tables = { obligations = obligations, assumptions = assumptions }
    for i = 1, #units do
        local n = core.nodes[units[i]]
        if n.tag == 'Unit' then
            for j = 1, #n.vars do
                local v = core.nodes[n.vars[j]]
                if v.tag ~= 'VarDecl' then
                    diags[#diags + 1] = diag.at_node('E-internal-node', n.vars[j], { v.tag, 'variable declaration' })
                end
            end
            check_statements(core, n.body, tables, { open = {}, used = {} }, diags)
        else
            diags[#diags + 1] = diag.at_node('E-internal-node', units[i], { n.tag, 'unit' })
        end
    end
    return diags
end

return M
