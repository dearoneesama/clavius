-- Checks a core program before it is printed. Every node must be in a place its kind belongs:
-- e.g. units are at the top;
--   variable declarations are in a unit's `vars`;
--   statements are in statement lists;
--   terms, which are pure, are everywhere else;
--   every `Check` must refer to an obligation of a known kind;
--   every `Assume` must refer to an assumption with an allowed justification.
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

--- @param core CoreArena
--- @param ids NodeId[]
--- @param tables ValidateTables
--- @param diags Diag[]
--- @mut diags
local function check_statements(core, ids, tables, diags)
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
            check_statements(core, n.then_body, tables, diags)
            check_statements(core, n.else_body, tables, diags)
        elseif n.tag == 'Choice' then
            check_statements(core, n.first, tables, diags)
            check_statements(core, n.second, tables, diags)
        elseif n.tag == 'Block' then
            check_statements(core, n.body, tables, diags)
        elseif n.tag == 'Havoc' or n.tag == 'Exit' then -- luacheck: ignore 542
            -- nothing
        else
            diags[#diags + 1] = diag.at_node('E-internal-node', id, { n.tag, 'statement' })
        end
    end
end

--- Returns a diagnostic for every misplaced node, unchecked `Check` and unjustified `Assume` in the
--- units in program order. The result is empty when the program is valid.
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
            check_statements(core, n.body, tables, diags)
        else
            diags[#diags + 1] = diag.at_node('E-internal-node', units[i], { n.tag, 'unit' })
        end
    end
    return diags
end

return M
