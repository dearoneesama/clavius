-- Lowers source expressions to pure core terms. The checks and calls an expression needs are hoisted,
-- in evaluation order, into the statement list before it. Contract clauses and ghost code never run,
-- so their arithmetic is exact and gets no range checks. A ghost value passed to a parameter is still
-- checked against the parameter's type. A call of a spec function lowers to its FunDecl applied to the
-- fuel and the arguments.

local arena = require 'clavius.ir.arena'
local builder = require 'clavius.elaborate.builder'
local support = require 'clavius.ir.support'

local M = {}

-- the core operator of each source operator other than `and` and `or`
--- @type table<string, '+' | '-' | '*' | '<' | '<=' | '>' | '>=' | '==' | '!='>
local OPS = { add = '+', sub = '-', mul = '*', lt = '<', le = '<=', gt = '>', ge = '>=', eq = '==', ne = '!=' }

--- Returns the decimal digits of an int53 literal.
--- @param text string a decimal or hexadecimal integer
--- @return string
function M.int_text(text)
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

--- Lowers the arguments of a call to `fn`, and in ghost code checks that each fits its parameter's type.
--- Returns the term for each parameter.
--- @param b Builder
--- @param n SrcCall
--- @param fn SrcFunction
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @return table<NodeId, NodeId> subst
local function arguments(b, n, fn, out)
    --- @type table<NodeId, NodeId>
    local subst = {}
    for i, a in ipairs(n.args) do
        local t = M.lower(b, a, out)
        if b.ghost then
            builder.narrow(b, out, b.info.types[fn.params[i]], b.info.types[a], t, a)
        end
        subst[fn.params[i]] = t
    end
    return subst
end

--- Checks, at a call `id` of `fn_id` that stays in its caller's cycle of recursive calls, that the
--- callee's measure at the arguments is below the caller's on entry. This makes it sound to assume what
--- the callee promises, by induction on the measure.
--- @param b Builder
--- @param id NodeId
--- @param fn_id NodeId
--- @param subst table<NodeId, NodeId>
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @return boolean recursive whether the call stays in the cycle
local function check_decrease(b, id, fn_id, subst, out)
    local caller = b.fn and b.fn.id
    if caller == nil or not builder.same_cycle(b, caller, fn_id) then
        return false
    end
    local mine = arena.directives(b.src, b.src.nodes[caller] --[[@as SrcFunction]], 'ClvDecrease')[1]
    local theirs = arena.directives(b.src, b.src.nodes[fn_id] --[[@as SrcFunction]], 'ClvDecrease')[1]
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
    builder.check(b, out, 'decrease', builder.decreases(b, before, after, id), id, theirs)
    return true
end

--- Lowers a call of a local function. The arguments are evaluated and each `---@pre` checked on them.
--- A call that stays in its caller's cycle of recursive calls also checks that the callee's measure at
--- the arguments is below the caller's on entry. The value, if any, is then arbitrary but for its type
--- and the callee's `---@post`s, which are assumed: proved in a verified callee or lemma, and trusted in
--- an `---@unsafe` one. Returns the value's term, or nil when the callee has no `---@return`.
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
    local subst = arguments(b, n, fn, out)
    for _, pre in ipairs(arena.directives(b.src, fn, 'ClvPre')) do
        local cond = (b.src.nodes[pre] --[[@as SrcClvPre]]).cond
        builder.check(b, out, 'pre', M.clause(b, cond, subst), id, pre)
    end
    check_decrease(b, id, fn_id, subst, out)
    local trusted = arena.has_directive(b.src, fn, 'ClvUnsafe')
    local decl = trusted and fn_id or nil
    local value = nil
    local r = arena.directives(b.src, fn, 'ClvReturn')[1]
    if r ~= nil then
        local ty = b.info.types[r]
        local t = builder.temp(b, builder.sort(ty), id)
        builder.emit(b, out, { tag = 'Havoc', target = t }, id)
        value = builder.add(b, { tag = 'Var', name = t }, id)
        local fact = builder.type_fact(b, ty, value, id)
        if fact ~= nil then
            builder.assume(b, out, trusted and 'trusted' or 'type_fact', fact, id, decl)
        end
        subst[r] = value
    end
    for _, post in ipairs(arena.directives(b.src, fn, 'ClvPost')) do
        local cond = (b.src.nodes[post] --[[@as SrcClvPost]]).cond
        builder.assume(b, out, trusted and 'trusted' or 'callee_post', M.clause(b, cond, subst), id, decl)
    end
    return value
end

--- Lowers a call of a spec function to the term that applies its FunDecl to the arguments, after the
--- fuel when the callee is recursive. In the axiom that defines a function of the callee's cycle, the
--- fuel is one less than the axiom's. A call that stays in the cycle of the spec function whose unit is
--- being built checks the measure, and then assumes the value's type, which that unit proves.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
--- @return NodeId term
function M.spec_call(b, id, out)
    local n = b.src.nodes[id] --[[@as SrcCall]]
    local fn_id = b.info.callees[id]
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    local subst = arguments(b, n, fn, out)
    local recursive = not b.spec and check_decrease(b, id, fn_id, subst, out)
    local spec = b.spec_of[fn_id]
    local args = {}
    if spec.recursive and b.axiom ~= nil and builder.same_cycle(b, b.axiom.fn, fn_id) then
        args[1] = builder.add(b, { tag = 'Var', name = b.axiom.fuel }, id)
    elseif spec.recursive then
        args[1] = builder.fuel(b, b.fuel[fn_id] or 1, id)
    end
    for _, p in ipairs(fn.params) do
        args[#args + 1] = subst[p]
    end
    local app = builder.add(b, { tag = 'App', fn = spec.name, args = args }, id)
    local r = arena.directives(b.src, fn, 'ClvReturn')[1]
    local fact = recursive and builder.type_fact(b, b.info.types[r], app, id)
    if fact then
        builder.assume(b, out, 'callee_post', fact, id)
    end
    return app
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
        return builder.add(b, { tag = 'Int', text = M.int_text(n.text) }, id)
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
    elseif n.tag == 'Call' and b.spec_of[b.info.callees[id]] ~= nil then
        return M.spec_call(b, id, out)
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
            local text = M.int_text(arg.text)
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
        if support.ARITH[n.op] and not b.spec and not b.ghost then
            builder.check(b, out, 'range', builder.is_int53(b, t, id), id)
        end
        return t
    end
    error(('elaborate: unhandled expression %s'):format(n.tag))
end

return M
