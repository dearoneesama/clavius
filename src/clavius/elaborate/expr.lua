-- Lowers source expressions to pure core terms. The checks and calls an expression needs are hoisted in
-- evaluation order into the statement list before it. A contract clause is spec code: its arithmetic
-- is exact, so it has no checks.

local arena = require 'clavius.ir.arena'
local builder = require 'clavius.elaborate.builder'

local M = {}

-- the core operator of each source operator other than `and` and `or`
--- @type table<string, '+' | '-' | '*' | '<' | '<=' | '>' | '>=' | '==' | '!='>
local OPS = { add = '+', sub = '-', mul = '*', lt = '<', le = '<=', gt = '>', ge = '>=', eq = '==', ne = '!=' }
local RANGE_CHECKED = { add = true, sub = true, mul = true }

--- Returns the decimal digits of an int53 literal.
--- @param text string a decimal or hexadecimal integer
--- @return string
local function int_text(text)
    return ('%.0f'):format(assert(tonumber(text)))
end

--- Lowers `lhs and rhs` or `lhs or rhs`. The right operand's checks run only when it is evaluated, so
--- when it has any, the result goes through a temporary set in a Branch.
--- @param b Builder
--- @param id NodeId
--- @param n SrcBinOp
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
--- @return NodeId term
local function short_circuit(b, id, n, out)
    local op = n.op == 'and' and 'and' or 'or'
    -- lhs always runs so it is lowered into current statement list
    local l = M.lower(b, n.lhs, out)
    local rhs_statements = {}
    local r = M.lower(b, n.rhs, rhs_statements)
    -- if rhs produced no checks, then core term is pure, evaluating it in every case is harmless
    if #rhs_statements == 0 then
        return builder.add(b, { tag = 'BinOp', op = op, lhs = l, rhs = r }, id)
    end

    -- in the case where rhs runs, rhs has checks, and t = rhs
    -- else, lhs = false, t = true iff operator is `or`
    local t = builder.temp(b, 'bool', id)
    builder.emit(b, rhs_statements, { tag = 'Assign', target = t, value = r }, id)
    local short = {}
    builder.emit(b, short, { tag = 'Assign', target = t, value = builder.add(b, { tag = 'Bool', value = op == 'or' }, id) }, id)
    if op == 'and' then
        builder.emit(b, out, { tag = 'Branch', cond = l, then_body = rhs_statements, else_body = short }, id)
    else
        -- short = true
        builder.emit(b, out, { tag = 'Branch', cond = l, then_body = short, else_body = rhs_statements }, id)
    end
    return builder.add(b, { tag = 'Var', name = t }, id)
end

--- Lowers a contract clause of a function to a term, with `subst` giving the term for each of its
--- parameters and its value that doesn't stand for itself.
--- @param b Builder
--- @param cond NodeId
--- @param subst table<NodeId, NodeId>
--- @mut b
--- @return NodeId term
function M.clause(b, cond, subst)
    local spec, outer = b.spec, b.subst
    b.spec, b.subst = true, subst
    -- spec code has no checks and no calls, so nothing is hoisted
    local hoisted = {}
    local t = M.lower(b, cond, hoisted)
    assert(#hoisted == 0, 'elaborate: a contract clause needs statements')
    b.spec, b.subst = spec, outer
    return t
end

--- Lowers a call of a local function. The arguments are evaluated and each `---@pre` checked on them.
--- A call that stays in its caller's cycle of recursive calls also checks that the callee's measure at
--- the arguments is below the caller's on entry. The value, if any, is then arbitrary but for its type
--- and the callee's `---@post`s, which are assumed: proved in a verified callee, and trusted in an
--- `---@unsafe` one. Returns the value's term, or nil when the callee has no `---@return`.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
--- @return NodeId|nil term
function M.call(b, id, out)
    local n = b.src.nodes[id] --[[@as SrcCall]]
    local fn_id = b.info.callees[id]
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    --- @type table<NodeId, NodeId>
    local subst = {}
    for i, a in ipairs(n.args) do
        subst[fn.params[i]] = M.lower(b, a, out)
    end
    for _, pre in ipairs(arena.directives(b.src, fn, 'ClvPre')) do
        local cond = (b.src.nodes[pre] --[[@as SrcClvPre]]).cond
        builder.check(b, out, 'pre', M.clause(b, cond, subst), id, pre)
    end
    local caller = b.fn and b.fn.id
    local cycle = caller and b.termination.cycle[caller]
    if cycle ~= nil and cycle == b.termination.cycle[fn_id] then
        local mine = arena.directives(b.src, b.src.nodes[caller] --[[@as SrcFunction]], 'ClvDecrease')[1]
        local theirs = arena.directives(b.src, fn, 'ClvDecrease')[1]
        local entry_measure = b.src.nodes[mine] --[[@as SrcClvDecrease]]
        local call_measure = b.src.nodes[theirs] --[[@as SrcClvDecrease]]
        -- the caller's measure on entry, and the callee's at the arguments
        local before, after = {}, {}
        for i, m in ipairs(entry_measure.measures) do
            before[i] = M.clause(b, m, assert(b.fn).entry)
        end
        for i, m in ipairs(call_measure.measures) do
            after[i] = M.clause(b, m, subst)
        end
        -- this check makes it sound to assume the callee's `---@post`s below, by induction on the measure
        builder.check(b, out, 'decrease', builder.decreases(b, before, after, id), id, theirs)
    end
    local trusted = arena.has_directive(b.src, fn, 'ClvUnsafe')
    local decl = trusted and fn_id or nil
    local value = nil
    local r = arena.directives(b.src, fn, 'ClvReturn')[1]
    if r ~= nil then
        local ty = b.info.types[r]
        local t = builder.temp(b, builder.sort(ty), id)
        builder.emit(b, out, { tag = 'Havoc', target = t }, id)
        value = builder.add(b, { tag = 'Var', name = t }, id)
        if ty == 'int53' then
            builder.assume(b, out, trusted and 'trusted' or 'type_fact', builder.is_int53(b, value, id), id, decl)
        end
        subst[r] = value
    end
    for _, post in ipairs(arena.directives(b.src, fn, 'ClvPost')) do
        local cond = (b.src.nodes[post] --[[@as SrcClvPost]]).cond
        builder.assume(b, out, trusted and 'trusted' or 'callee_post', M.clause(b, cond, subst), id, decl)
    end
    return value
end

--- Lowers an expression to a term and adds the statements it needs to `out`.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
--- @return NodeId term
function M.lower(b, id, out)
    local n = b.src.nodes[id]
    if n.tag == 'Literal' and n.kind == 'number' then
        return builder.add(b, { tag = 'Int', text = int_text(n.text) }, id)
    elseif n.tag == 'Literal' then
        return builder.add(b, { tag = 'Bool', value = n.kind == 'true' }, id)
    elseif n.tag == 'Id' then
        local decl = b.res.decl[id]
        if b.subst[decl] ~= nil then
            return b.subst[decl]
        elseif b.res.constants[decl] ~= nil and not b.declared[builder.name_of(b, id)] then
            -- a constant declared outside this unit
            return M.lower(b, b.res.constants[decl], out)
        end
        return builder.add(b, { tag = 'Var', name = builder.name_of(b, id) }, id)
    elseif n.tag == 'Call' then
        -- `types` has made sure the callee has a value
        return assert(M.call(b, id, out))
    elseif n.tag == 'Paren' then
        return M.lower(b, n.expr, out)
    elseif n.tag == 'UnOp' and n.op == 'not' then
        return builder.add(b, { tag = 'Not', arg = M.lower(b, n.arg, out) }, id)
    elseif n.tag == 'UnOp' then
        -- -x stays within ±2^53 when x does, so it needs no check
        local arg = b.src.nodes[n.arg]
        if arg.tag == 'Literal' then
            local text = int_text(arg.text)
            return builder.add(b, { tag = 'Int', text = text == '0' and text or '-' .. text }, id)
        end
        local zero = builder.add(b, { tag = 'Int', text = '0' }, id)
        return builder.add(b, { tag = 'BinOp', op = '-', lhs = zero, rhs = M.lower(b, n.arg, out) }, id)
    elseif n.tag == 'BinOp' and (n.op == 'and' or n.op == 'or') then
        return short_circuit(b, id, n, out)
    elseif n.tag == 'BinOp' then
        local l = M.lower(b, n.lhs, out)
        local r = M.lower(b, n.rhs, out)
        local t = builder.add(b, { tag = 'BinOp', op = OPS[n.op], lhs = l, rhs = r }, id)
        if RANGE_CHECKED[n.op] and not b.spec then
            builder.check(b, out, 'range', builder.is_int53(b, t, id), id)
        end
        return t
    end
    error(('elaborate: unhandled expression %s'):format(n.tag))
end

return M
