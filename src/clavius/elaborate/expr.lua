-- Lowers source expressions to pure core terms. The checks an expression needs are hoisted in
-- evaluation order into the statement list before it.

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

--- Forward declaration.
local lower

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
    local l = lower(b, n.lhs, out)
    local rhs_statements = {}
    local r = lower(b, n.rhs, rhs_statements)
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

--- Lowers an expression to a term and adds the statements it needs to `out`.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
--- @return NodeId term
function lower(b, id, out)
    local n = b.src.nodes[id]
    if n.tag == 'Literal' and n.kind == 'number' then
        return builder.add(b, { tag = 'Int', text = int_text(n.text) }, id)
    elseif n.tag == 'Literal' then
        return builder.add(b, { tag = 'Bool', value = n.kind == 'true' }, id)
    elseif n.tag == 'Id' then
        return builder.add(b, { tag = 'Var', name = builder.name_of(b, id) }, id)
    elseif n.tag == 'Paren' then
        return lower(b, n.expr, out)
    elseif n.tag == 'UnOp' and n.op == 'not' then
        return builder.add(b, { tag = 'Not', arg = lower(b, n.arg, out) }, id)
    elseif n.tag == 'UnOp' then
        -- -x stays within ±2^53 when x does, so it needs no check
        local arg = b.src.nodes[n.arg]
        if arg.tag == 'Literal' then
            local text = int_text(arg.text)
            return builder.add(b, { tag = 'Int', text = text == '0' and text or '-' .. text }, id)
        end
        local zero = builder.add(b, { tag = 'Int', text = '0' }, id)
        return builder.add(b, { tag = 'BinOp', op = '-', lhs = zero, rhs = lower(b, n.arg, out) }, id)
    elseif n.tag == 'BinOp' and (n.op == 'and' or n.op == 'or') then
        return short_circuit(b, id, n, out)
    elseif n.tag == 'BinOp' then
        local l = lower(b, n.lhs, out)
        local r = lower(b, n.rhs, out)
        local t = builder.add(b, { tag = 'BinOp', op = OPS[n.op], lhs = l, rhs = r }, id)
        if RANGE_CHECKED[n.op] then
            builder.check(b, out, 'range', builder.is_int53(b, t, id), id)
        end
        return t
    end
    error(('elaborate: unhandled expression %s'):format(n.tag))
end

M.lower = lower

return M
