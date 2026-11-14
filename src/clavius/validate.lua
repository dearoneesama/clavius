-- Checks a core program before it is printed. Every node must be in a place its kind belongs:
-- e.g. units are at the top;
--   variable declarations are in a unit's `vars`;
--   statements are in statement lists;
--   terms, which are pure, are everywhere else;
--   every `Check` must refer to an obligation of a known kind;
--   every `Assume` must refer to an assumption with an allowed justification;
--   every `Exit` must be inside a `Block` with its label;
--   the `Block` labels in a unit must differ.
-- For a core program elaborated from Lua, it also checks coverage: every source node in a region that
-- can fail at runtime has a `Check` for each obligation it needs.
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

--- The source program that a core program was elaborated from.
--- @class ValidateSource
--- @field src SrcArena
--- @field index NodeIndex

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
    for _, id in ipairs(ids) do
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

--- Returns the obligation kind that the source node `id` in a region needs, or nil. This follows from
--- what `clavius.ir.support` lets regions use: every `+`, `-` and `*` is on `int53`, and every call is
--- a statement call to `assert` or `error`.
--- @param src SrcArena
--- @param id NodeId
--- @return ObligationKind|nil
local function needed_kind(src, id)
    local n = src.nodes[id]
    if n.tag == 'BinOp' and RANGE_CHECKED[n.op] then
        return 'range'
    elseif n.tag == 'Call' then
        local callee = src.nodes[n.func] --[[@as SrcId]]
        return callee.name == 'assert' and 'assert' or 'unreachable'
    end
    return nil
end

--- Reports each source node in a region that lacks a checked obligation it needs. No core node exists
--- for it, so the diagnostic's span is the source node's.
--- @param source ValidateSource
--- @param tables ValidateTables
--- @param checked table<integer, boolean> the obligations that a `Check` in a unit names
--- @param diags Diag[]
--- @mut diags
local function check_coverage(source, tables, checked, diags)
    --- @type table<NodeId, table<string, boolean>>
    local have = {}
    for id, o in ipairs(tables.obligations) do
        if checked[id] then
            have[o.node] = have[o.node] or {}
            have[o.node][o.kind] = true
        end
    end
    for _, tag in ipairs({ 'BinOp', 'Call' }) do
        local ids = source.index.by_tag[tag] or {}
        for _, id in ipairs(ids) do
            if source.index.region[id] ~= 0 then
                local kind = needed_kind(source.src, id)
                if kind ~= nil and not (have[id] and have[id][kind]) then
                    diags[#diags + 1] = diag.at_span('E-internal-coverage', source.src.spans[id], { tag, kind })
                end
            end
        end
    end
end

--- Returns a diagnostic for every misplaced node, unchecked `Check`, unjustified `Assume`, stray `Exit`
--- and reused `Block` label in the units in program order. With the source program, it then reports
--- the obligations missing from it. The result is empty when the program is valid.
--- @param core CoreArena
--- @param units NodeId[]
--- @param obligations Obligation[]
--- @param assumptions Assumption[]
--- @param source ValidateSource|nil
--- @return Diag[] diags
function M.run(core, units, obligations, assumptions, source)
    local diags = {}
    --- @type ValidateTables
    local tables = { obligations = obligations, assumptions = assumptions }
    --- @type table<integer, boolean>
    local checked = {}
    for _, unit in ipairs(units) do
        local n = core.nodes[unit]
        if n.tag == 'Unit' then
            for _, var in ipairs(n.vars) do
                local v = core.nodes[var]
                if v.tag ~= 'VarDecl' then
                    diags[#diags + 1] = diag.at_node('E-internal-node', var, { v.tag, 'variable declaration' })
                end
            end
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
