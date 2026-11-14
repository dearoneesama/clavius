-- The elaborate pass: lowers the code in regions to core units with their obligations. Each region
-- with statements becomes one unit.

local builder = require 'clavius.elaborate.builder'
local expr = require 'clavius.elaborate.expr'

local M = {}

local statement

--- Lowers an `if` from its arm `i` on.
--- @param b Builder
--- @param n SrcIf
--- @param i integer
--- @param out NodeId[]
--- @mut b
--- @mut out
local function lower_if(b, n, i, out)
    local arm_id = n.arms[i]
    local arm = b.src.nodes[arm_id] --[[@as SrcIfArm]]
    local cond = expr.lower(b, arm.cond, out)
    local then_body, else_body = {}, {}
    statement(b, arm.body, then_body)
    if i < #n.arms then
        lower_if(b, n, i + 1, else_body)
    elseif n.else_block ~= nil then
        statement(b, n.else_block, else_body)
    end
    builder.emit(b, out, { tag = 'Branch', cond = cond, then_body = then_body, else_body = else_body }, arm_id)
end

--- Lowers a statement and adds its core statements to `out`.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
function statement(b, id, out)
    local n = b.src.nodes[id]
    if n.tag == 'Local' then
        local terms = {}
        for i, v in ipairs(n.values) do
            terms[i] = expr.lower(b, v, out)
        end
        -- the names are fresh, so the values can't refer to them
        for i, name in ipairs(n.names) do
            builder.var(b, builder.name_of(b, name), builder.sort(b.info.types[name]), name)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, name), value = terms[i] }, id)
        end
    elseif n.tag == 'Set' then
        local terms = {}
        for i, v in ipairs(n.values) do
            terms[i] = expr.lower(b, v, out)
        end
        if #n.targets == 1 then
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, n.targets[1]), value = terms[1] }, id)
            return
        end
        -- every value is evaluated before the first assignment
        local temps = {}
        for i, v in ipairs(n.values) do
            temps[i] = builder.temp(b, builder.sort(b.info.types[v]), v)
            builder.emit(b, out, { tag = 'Assign', target = temps[i], value = terms[i] }, v)
        end
        for i, t in ipairs(n.targets) do
            local value = builder.add(b, { tag = 'Var', name = temps[i] }, t)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, t), value = value }, id)
        end
    elseif n.tag == 'Block' then
        for _, s in ipairs(n.statements) do
            statement(b, s, out)
        end
    elseif n.tag == 'If' then
        lower_if(b, n, 1, out)
    elseif n.tag == 'Call' then
        local callee = b.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            builder.check(b, out, 'assert', expr.lower(b, n.args[1], out), id)
        else
            -- `error` must be unreachable
            builder.check(b, out, 'unreachable', builder.add(b, { tag = 'Bool', value = false }, id), id)
        end
    else
        error(('elaborate: unhandled statement %s'):format(n.tag))
    end
end

--- Lowers the regions of a typed file. The units are named `main$1`, `main$2` and so on in order.
--- @param src SrcArena
--- @param root NodeId
--- @param res Resolution
--- @param info TypeInfo
--- @return CoreProgram
function M.run(src, root, res, info)
    local b = builder.new(src, res, info)
    local units = {}
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        if n.tag == 'ClvRegion' and #n.statements > 0 then
            b.vars, b.temps = {}, 0
            local body = {}
            for _, s in ipairs(n.statements) do
                statement(b, s, body)
            end
            local name = ('main$%d'):format(#units + 1)
            units[#units + 1] = builder.add(b, { tag = 'Unit', name = name, vars = b.vars, body = body }, id)
        end
    end
    return { core = b.core, units = units, obligations = b.obligations, assumptions = b.assumptions }
end

return M
