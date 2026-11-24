-- The types pass: the type of every expression and local in marked code and in contracts. A number
-- literal's type comes from its spelling, a local's from its initializer, and a parameter's and a
-- function's value from its `---@param` and `---@return`. In spec and proof code, which never runs,
-- arithmetic is exact and gives an `Int`, and so does a ghost local with an integer initializer. Integer
-- types convert into each other, and `elaborate` checks where a value narrows.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local support = require 'clavius.ir.support'

--- @alias Type 'int53' | 'Int' | 'Nat' | 'boolean'

--- @class TypeInfo
--- @field types table<NodeId, Type> the type of each expression and Binder in marked code and contracts, and of each function's ClvReturn
--- @field callees table<NodeId, NodeId> the Function node that each call of a local function calls

--- @class TypesState
--- @field src SrcArena
--- @field res Resolution
--- @field out TypeInfo
--- @field diags Diag[]
--- @field result NodeId|nil the ClvReturn of the function whose body is being typed
--- @field typed table<NodeId, boolean> the expressions typed so far
--- @field ghost boolean whether spec or proof code is being typed

local M = {}

-- the largest int53, in decimal and in hexadecimal digits
local INT53_MAX = '9007199254740992'
local INT53_MAX_HEX = '20000000000000'

local ARITH = { add = true, sub = true, mul = true }
local ORDER = { lt = true, le = true, gt = true, ge = true }

local INTEGERS = { int53 = true, Int = true, Nat = true }

-- the integer types that only spec and proof code may hold
local GHOST_TYPES = { Int = true, Nat = true }

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
    local digits = t:match '^0x(%x+)$'
    local limit = INT53_MAX_HEX
    if digits == nil then
        digits = t:match '^(%d+)$'
        limit = INT53_MAX
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

--- Requires `id`, whose type is `ty`, to be an integer.
--- @param st TypesState
--- @param id NodeId
--- @param ty Type|nil
--- @mut st
--- @return boolean
local function want_int(st, id, ty)
    if ty == 'boolean' then
        report(st, 'E-type-mismatch', id, { 'int53', ty })
    end
    return ty ~= nil and INTEGERS[ty] == true
end

--- Returns whether a value of type `value` may go where one of type `want` is expected: one of the same
--- type, or any integer where an integer is expected.
--- @param want Type
--- @param value Type
--- @return boolean
local function fits(want, value)
    return want == value or (INTEGERS[want] == true and INTEGERS[value] == true)
end

--- Requires `id`, whose type is `ty`, to be a `boolean`. Conditions and the operands of `and`, `or` and
--- `not` must be booleans.
--- @param st TypesState
--- @param id NodeId
--- @param ty Type|nil
--- @mut st
--- @return boolean
local function want_bool(st, id, ty)
    if ty ~= nil and INTEGERS[ty] then
        report(st, 'E-unsupported-feature', id, { 'truthiness' })
    end
    return ty == 'boolean'
end

--- Returns a type expression as it would be written, for messages.
--- @param st TypesState
--- @param id NodeId
--- @decrease id
--- @return string
local function type_text(st, id)
    local n = st.src.nodes[id]
    if n.tag == 'ClvTypeName' then
        return n.name
    elseif n.tag == 'ClvTypeLiteral' then
        return n.kind == 'string' and ('%q'):format(n.text) or n.text
    elseif n.tag == 'ClvTypeApply' then
        local args = {}
        for i, a in ipairs(n.args) do
            args[i] = type_text(st, a)
        end
        return ('%s<%s>'):format(type_text(st, n.base), table.concat(args, ', '))
    elseif n.tag == 'ClvTypeArray' then
        return type_text(st, n.elem) .. '[]'
    elseif n.tag == 'ClvTypeUnion' then
        local members = {}
        for i, m in ipairs(n.members) do
            members[i] = type_text(st, m)
        end
        return table.concat(members, ' | ')
    elseif n.tag == 'ClvTypeOptional' then
        return type_text(st, n.inner) .. '?'
    elseif n.tag == 'ClvTypeFun' then
        return 'fun(…)'
    elseif n.tag == 'ClvTypeTable' then
        return '{…}'
    elseif n.tag == 'ClvTypeTuple' then
        return '[…]'
    end
    return '`…`'
end

--- Returns the type that a type expression stands for. One that marked code can't use yet is reported
--- and gives nil, and so do `Int` and `Nat` in an exec function's signature.
--- @param st TypesState
--- @param id NodeId
--- @param kind FunctionKind the kind of the function whose signature it is in
--- @mut st
--- @return Type|nil
local function declared(st, id, kind)
    local n = st.src.nodes[id]
    -- `integer` is LuaLS's spelling of `int53`
    if n.tag == 'ClvTypeName' and (n.name == 'int53' or n.name == 'integer') then
        return 'int53'
    elseif n.tag == 'ClvTypeName' and n.name == 'boolean' then
        return 'boolean'
    elseif n.tag == 'ClvTypeName' and GHOST_TYPES[n.name] and kind ~= 'exec' then
        return n.name --[[@as Type]]
    elseif n.tag == 'ClvTypeName' and GHOST_TYPES[n.name] then
        report(st, 'E-type-mismatch', id, { 'int53', n.name })
        return nil
    end
    report(st, 'E-unsupported-type', id, { type_text(st, id) })
    return nil
end

--- Gives a function's parameters and value their declared types. A parameter with no `---@param` has
--- LuaLS's type `any`, which isn't supported.
--- @param st TypesState
--- @param fn SrcFunction
--- @param kind FunctionKind
--- @mut st
local function signature(st, fn, kind)
    --- @type table<string, NodeId>
    local params = {}
    for _, d in ipairs(fn.directives) do
        local dn = st.src.nodes[d]
        if dn.tag == 'ClvParam' then
            params[dn.name] = dn.type
        end
    end
    for _, p in ipairs(fn.params) do
        local ty_node = params[
            (st.src.nodes[p] --[[@as SrcBinder]]).name
        ]
        if ty_node == nil then
            report(st, 'E-unsupported-type', p, { 'any' })
        else
            st.out.types[p] = declared(st, ty_node, kind)
        end
    end
    local r = arena.directives(st.src, fn, 'ClvReturn')[1]
    if r ~= nil then
        st.out.types[r] = declared(st, (st.src.nodes[r] --[[@as SrcClvReturn]]).type, kind)
    end
end

--- Forward declaration.
local expression

--- Types a call of a local function against the callee's parameters, records the callee, and returns
--- the type of its value: nil when the callee has no `---@return`.
--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
--- @return Type|nil
local function call(st, id)
    local n = st.src.nodes[id] --[[@as SrcCall]]
    local fn_id = st.res.functions[st.res.decl[n.func]]
    st.out.callees[id] = fn_id
    local fn = st.src.nodes[fn_id] --[[@as SrcFunction]]
    for i, a in ipairs(n.args) do
        local ty = expression(st, a)
        local want = st.out.types[fn.params[i]]
        if ty ~= nil and want ~= nil and not fits(want, ty) then
            report(st, 'E-type-mismatch', a, { want, ty })
        end
    end
    local r = arena.directives(st.src, fn, 'ClvReturn')[1]
    return r and st.out.types[r]
end

--- Returns the type of an expression. A type error is reported and gives nil.
--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
--- @return Type|nil
function expression(st, id)
    local n = st.src.nodes[id]
    st.typed[id] = true
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
        local decl = st.res.decl[id]
        local constant = st.res.constants[decl]
        -- a constant's initializer is typed once, so its error is reported once, and as exec code
        if constant ~= nil and not st.typed[constant] then
            local ghost = st.ghost
            st.ghost = false
            ty = expression(st, constant)
            st.ghost = ghost
        else
            ty = st.out.types[constant or decl]
        end
    elseif n.tag == 'Call' then
        local fn = st.src.nodes[st.res.functions[st.res.decl[n.func]]] --[[@as SrcFunction]]
        ty = call(st, id)
        if not arena.has_directive(st.src, fn, 'ClvReturn') then
            report(st, 'E-type-mismatch', id, { 'a value', 'no value' })
        end
    elseif n.tag == 'Paren' then
        ty = expression(st, n.expr)
    elseif n.tag == 'UnOp' then
        local a = expression(st, n.arg)
        if n.op == 'unm' and want_int(st, n.arg, a) then
            ty = st.ghost and 'Int' or 'int53'
        elseif n.op == 'not' and want_bool(st, n.arg, a) then
            ty = 'boolean'
        end
    elseif n.tag == 'BinOp' then
        local l = expression(st, n.lhs)
        local r = expression(st, n.rhs)
        if ARITH[n.op] or ORDER[n.op] then
            local ok_l = want_int(st, n.lhs, l)
            local ok_r = want_int(st, n.rhs, r)
            if ok_l and ok_r and ORDER[n.op] then
                ty = 'boolean'
            elseif ok_l and ok_r then
                ty = st.ghost and 'Int' or 'int53'
            end
        elseif n.op == 'eq' or n.op == 'ne' then
            if l ~= nil and r ~= nil and not fits(l, r) then
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

--- Types a contract clause, an invariant or a measure. It is spec code, so its arithmetic is exact.
--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @return Type|nil
local function clause(st, id)
    local ghost = st.ghost
    st.ghost = true
    local ty = expression(st, id)
    st.ghost = ghost
    return ty
end

--- Types a loop's directives: an invariant is a boolean and each expression of a measure an integer.
--- @param st TypesState
--- @param loop SrcWhile|SrcRepeat|SrcFornum
--- @mut st
local function loop_directives(st, loop)
    for _, d in ipairs(loop.directives) do
        local dn = st.src.nodes[d]
        if dn.tag == 'ClvInvariant' then
            want_bool(st, dn.cond, clause(st, dn.cond))
        elseif dn.tag == 'ClvDecrease' then
            for _, m in ipairs(dn.measures) do
                want_int(st, m, clause(st, m))
            end
        end
    end
end

--- Forward declaration.
local statement

--- Types a statement of ghost code.
--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
local function ghost_statement(st, id)
    local ghost = st.ghost
    st.ghost = true
    statement(st, id)
    st.ghost = ghost
end

--- @param st TypesState
--- @param id NodeId
--- @mut st
--- @decrease id
function statement(st, id)
    local n = st.src.nodes[id]
    if st.res.defined[id] ~= nil or n.tag == 'ClvSpec' or n.tag == 'ClvLemma' then -- luacheck: ignore 542
        -- a function definition, typed as a unit of its own
    elseif n.tag == 'Local' then
        for i, v in ipairs(n.values) do
            local ty = expression(st, v)
            if ty ~= nil then
                -- a ghost local never exists at runtime, so a range would buy nothing
                st.out.types[n.names[i]] = (st.ghost and INTEGERS[ty]) and 'Int' or ty
            end
        end
    elseif n.tag == 'Set' then
        for i, v in ipairs(n.values) do
            local value = expression(st, v)
            local target = st.out.types[st.res.decl[n.targets[i]]]
            if target ~= nil then
                st.out.types[n.targets[i]] = target
            end
            if value ~= nil and target ~= nil and not fits(target, value) then
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
    elseif n.tag == 'While' then
        loop_directives(st, n)
        want_bool(st, n.cond, expression(st, n.cond))
        statement(st, n.body)
    elseif n.tag == 'Repeat' then
        loop_directives(st, n)
        statement(st, n.body)
        want_bool(st, n.cond, expression(st, n.cond))
    elseif n.tag == 'Fornum' then
        want_int(st, n.start, expression(st, n.start))
        want_int(st, n.limit, expression(st, n.limit))
        if n.step ~= nil then
            want_int(st, n.step, expression(st, n.step))
        end
        st.out.types[n.var] = st.ghost and 'Int' or 'int53'
        loop_directives(st, n)
        statement(st, n.body)
    elseif n.tag == 'Break' then -- luacheck: ignore 542
        -- nothing to type
    elseif n.tag == 'Call' and st.res.decl[n.func] ~= nil then
        call(st, id)
    elseif n.tag == 'Call' then
        -- `assert` or `error`; a message is a literal that is never used as a value
        local callee = st.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            want_bool(st, n.args[1], expression(st, n.args[1]))
        end
    elseif n.tag == 'Return' then
        local want = st.result and st.out.types[st.result]
        local value = n.values[1]
        if value == nil and st.result ~= nil then
            report(st, 'E-type-mismatch', id, { want or 'a value', 'no value' })
        elseif value ~= nil then
            local ty = expression(st, value)
            if st.result == nil and ty ~= nil then
                report(st, 'E-type-mismatch', value, { 'no value', ty })
            elseif ty ~= nil and want ~= nil and not fits(want, ty) then
                report(st, 'E-type-mismatch', value, { want, ty })
            end
        end
    elseif n.tag == 'ClvProof' then
        for _, s in ipairs(n.statements) do
            ghost_statement(st, s)
        end
    elseif n.tag == 'ClvGhost' then
        ghost_statement(st, n.statement)
    elseif n.tag == 'ClvAssert' then
        want_bool(st, n.cond, clause(st, n.cond))
    else
        error(('types: unhandled statement %s'):format(n.tag))
    end
end

--- A function to type, and how.
--- @class TypesFunction
--- @field fn SrcFunction
--- @field verified boolean whether its body is typed: it isn't `---@unsafe`
--- @field kind FunctionKind

--- Types a function's contract and measure, and its body unless it is `---@unsafe`. Its signature is
--- already typed.
--- @param st TypesState
--- @param f TypesFunction
--- @mut st
local function func(st, f)
    for _, d in ipairs(f.fn.directives) do
        local dn = st.src.nodes[d]
        if dn.tag == 'ClvPre' or dn.tag == 'ClvPost' then
            want_bool(st, dn.cond, clause(st, dn.cond))
        elseif dn.tag == 'ClvDecrease' then
            for _, m in ipairs(dn.measures) do
                want_int(st, m, clause(st, m))
            end
        end
    end
    if f.verified then
        st.result = arena.directives(st.src, f.fn, 'ClvReturn')[1]
        st.ghost = f.kind ~= 'exec'
        statement(st, f.fn.body)
        st.result, st.ghost = nil, false
    end
end

--- Adds the functions that the statements of a list define to `out`: in a region, marked `---@clavius`
--- or `---@unsafe`, or in a spec or lemma block.
--- @param st TypesState
--- @param statements NodeId[]
--- @param in_region boolean
--- @param out TypesFunction[]
--- @mut out
local function defined(st, statements, in_region, out)
    for _, id in ipairs(statements) do
        local binder = st.res.defined[id]
        local n = st.src.nodes[id]
        if binder ~= nil then
            local fn_id = st.res.functions[binder]
            local fn = st.src.nodes[fn_id] --[[@as SrcFunction]]
            local kind = st.res.kinds[fn_id]
            local unsafe = arena.has_directive(st.src, fn, 'ClvUnsafe')
            if kind ~= 'exec' or unsafe or in_region or arena.has_directive(st.src, fn, 'ClvMarker') then
                out[#out + 1] = { fn = fn, verified = not unsafe, kind = kind }
            end
        elseif n.tag == 'ClvSpec' or n.tag == 'ClvLemma' then
            defined(st, n.statements, in_region, out)
        end
    end
end

--- Types the marked code of a resolved file: its regions, the functions in them and those marked
--- `---@clavius`, spec functions and lemmas, and the contracts of `---@unsafe` functions.
--- @param src SrcArena
--- @param root NodeId
--- @param res Resolution
--- @return TypeInfo info
--- @return Diag[] diags
function M.run(src, root, res)
    --- @type TypesState
    local st = { src = src, res = res, out = { types = {}, callees = {} }, diags = {}, result = nil, typed = {}, ghost = false }
    local top = src.nodes[root] --[[@as SrcBlock]]
    --- @type TypesFunction[]
    local fns = {}
    defined(st, top.statements, false, fns)
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        if n.tag == 'ClvRegion' then
            defined(st, n.statements, true, fns)
        end
    end
    -- every signature first, since a function may call one defined below it
    for _, f in ipairs(fns) do
        signature(st, f.fn, f.kind)
    end
    for _, f in ipairs(fns) do
        func(st, f)
    end
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
