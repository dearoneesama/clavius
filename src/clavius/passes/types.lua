-- The types pass: the type of every expression and local in a region. A number literal's type comes
-- from its spelling, and a local's from its initializer.

local diag = require 'clavius.ir.diag'
local support = require 'clavius.ir.support'

--- @alias Type 'int53' | 'boolean'

--- @class TypeInfo
--- @field types table<NodeId, Type> the type of each expression and Binder in a region

--- @class TypesState
--- @field src SrcArena
--- @field res Resolution
--- @field out TypeInfo
--- @field diags Diag[]

local M = {}

-- the largest int53, in decimal and in hexadecimal digits
local INT53_MAX = '9007199254740992'
local INT53_MAX_HEX = '20000000000000'

local ARITH = { add = true, sub = true, mul = true }
local ORDER = { lt = true, le = true, gt = true, ge = true }

--- Returns the type that a number literal's spelling gives it: `int53` for a decimal or hexadecimal
--- integer within ±2^53 with no suffix, `i64` for `LL`, `u64` for `ULL`, `complex` for `i`, and `f64`
--- for everything else. That includes integers beyond ±2^53, since LuaJIT rounds them.
--- @param text string
--- @return string
function M.number_type(text)
    local t = text:lower()
    if t:sub(-1) == 'i' then
        return 'complex'
    elseif t:sub(-3) == 'ull' or t:sub(-3) == 'llu' then
        return 'u64'
    elseif t:sub(-2) == 'll' then
        return 'i64'
    end
    local digits, limit = t:match '^0x(%x+)$', INT53_MAX_HEX
    if digits == nil then
        digits, limit = t:match '^(%d+)$', INT53_MAX
    end
    if digits == nil then
        return 'f64'
    end
    digits = digits:gsub('^0+', '')
    -- digit strings of the same length compare like their values
    if #digits < #limit or (#digits == #limit and digits <= limit) then
        return 'int53'
    end
    return 'f64'
end

--- @param st TypesState
--- @param code DiagCode
--- @param id NodeId
--- @param args string[]
--- @mut st
local function report(st, code, id, args)
    st.diags[#st.diags + 1] = diag.at_node(code, id, args)
end

--- Requires `id`, whose type is `ty`, to be an `int53`.
--- @param st TypesState
--- @param id NodeId
--- @param ty Type|nil
--- @mut st
--- @return boolean
local function want_int(st, id, ty)
    if ty == 'boolean' then
        report(st, 'E-type-mismatch', id, { 'int53', ty })
    end
    return ty == 'int53'
end

--- Requires `id`, whose type is `ty`, to be a `boolean`. Conditions and the operands of `and`, `or` and
--- `not` must be booleans.
--- @param st TypesState
--- @param id NodeId
--- @param ty Type|nil
--- @mut st
--- @return boolean
local function want_bool(st, id, ty)
    if ty == 'int53' then
        report(st, 'E-unsupported-feature', id, { 'truthiness' })
    end
    return ty == 'boolean'
end

--- Returns the type of an expression. A type error is reported and gives nil.
--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
--- @return Type|nil
local function expression(st, id)
    local n = st.src.nodes[id]
    --- @type Type|nil
    local ty = nil
    if n.tag == 'Literal' then
        local lit = n.kind --- @type string
        if n.kind == 'number' then
            lit = M.number_type(n.text)
        elseif n.kind == 'true' or n.kind == 'false' then
            lit = 'boolean'
        end
        if support.TYPES[lit] then
            ty = lit --[[@as Type]]
        else
            report(st, 'E-unsupported-type', id, { lit })
        end
    elseif n.tag == 'Id' then
        ty = st.out.types[st.res.decl[id]]
    elseif n.tag == 'Paren' then
        ty = expression(st, n.expr)
    elseif n.tag == 'UnOp' then
        local a = expression(st, n.arg)
        if n.op == 'unm' and want_int(st, n.arg, a) then
            ty = 'int53'
        elseif n.op == 'not' and want_bool(st, n.arg, a) then
            ty = 'boolean'
        end
    elseif n.tag == 'BinOp' then
        local l = expression(st, n.lhs)
        local r = expression(st, n.rhs)
        if ARITH[n.op] or ORDER[n.op] then
            local ok_l = want_int(st, n.lhs, l)
            local ok_r = want_int(st, n.rhs, r)
            if ok_l and ok_r then
                ty = ARITH[n.op] and 'int53' or 'boolean'
            end
        elseif n.op == 'eq' or n.op == 'ne' then
            if l ~= nil and r ~= nil and l ~= r then
                report(st, 'E-type-mismatch', n.rhs, { l, r })
            elseif l ~= nil and r ~= nil then
                ty = 'boolean'
            end
        else
            local ok_l = want_bool(st, n.lhs, l)
            local ok_r = want_bool(st, n.rhs, r)
            if ok_l and ok_r then
                ty = 'boolean'
            end
        end
    else
        error(('types: unhandled expression %s'):format(n.tag))
    end
    if ty ~= nil then
        st.out.types[id] = ty
    end
    return ty
end

--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
local function statement(st, id)
    local n = st.src.nodes[id]
    if n.tag == 'Local' then
        for i, v in ipairs(n.values) do
            local ty = expression(st, v)
            if ty ~= nil then
                st.out.types[n.names[i]] = ty
            end
        end
    elseif n.tag == 'Set' then
        for i, v in ipairs(n.values) do
            local value = expression(st, v)
            local target = st.out.types[st.res.decl[n.targets[i]]]
            if target ~= nil then
                st.out.types[n.targets[i]] = target
            end
            if value ~= nil and target ~= nil and value ~= target then
                report(st, 'E-type-mismatch', v, { target, value })
            end
        end
    elseif n.tag == 'Block' then
        for _, s in ipairs(n.statements) do
            statement(st, s)
        end
    elseif n.tag == 'If' then
        for _, arm_id in ipairs(n.arms) do
            local arm = st.src.nodes[arm_id] --[[@as SrcIfArm]]
            want_bool(st, arm.cond, expression(st, arm.cond))
            statement(st, arm.body)
        end
        if n.else_block ~= nil then
            statement(st, n.else_block)
        end
    elseif n.tag == 'Call' then
        -- `assert` or `error`; a message is a literal that is never used as a value
        local callee = st.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            want_bool(st, n.args[1], expression(st, n.args[1]))
        end
    else
        error(('types: unhandled statement %s'):format(n.tag))
    end
end

--- Types the regions of a resolved file.
--- @param src SrcArena
--- @param root NodeId
--- @param res Resolution
--- @return TypeInfo info
--- @return Diag[] diags
function M.run(src, root, res)
    --- @type TypesState
    local st = { src = src, res = res, out = { types = {} }, diags = {} }
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        if n.tag == 'ClvRegion' then
            for _, s in ipairs(n.statements) do
                statement(st, s)
            end
        end
    end
    return st.out, st.diags
end

return M
