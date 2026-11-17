-- The elaborate pass: lowers marked code to core units with their obligations. Each verified function
-- becomes one unit, and so do the other top-level statements of each region.

local arena = require 'clavius.ir.arena'
local builder = require 'clavius.elaborate.builder'
local expr = require 'clavius.elaborate.expr'

local M = {}

local statement

--- Checks each `---@post` of the function being built, where it returns at `origin`. A parameter in a
--- `---@post` means its value on entry.
--- @param b Builder
--- @param out NodeId[]
--- @param origin NodeId a Return, or the Function when its body ends
--- @mut b
--- @mut out
local function check_posts(b, out, origin)
    local fn = assert(b.fn)
    for _, post in ipairs(fn.posts) do
        local cond = (b.src.nodes[post] --[[@as SrcClvPost]]).cond
        builder.check(b, out, 'post', expr.clause(b, cond, fn.entry), origin, post)
    end
end

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
    elseif n.tag == 'Call' and b.info.callees[id] ~= nil then
        expr.call(b, id, out)
    elseif n.tag == 'Call' then
        local callee = b.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            builder.check(b, out, 'assert', expr.lower(b, n.args[1], out), id)
        else
            -- `error` must be unreachable
            builder.check(b, out, 'unreachable', builder.add(b, { tag = 'Bool', value = false }, id), id)
        end
    elseif n.tag == 'Return' then
        local fn = assert(b.fn)
        if n.values[1] ~= nil then
            local value = expr.lower(b, n.values[1], out)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, assert(fn.result)), value = value }, id)
        end
        check_posts(b, out, id)
        builder.emit(b, out, { tag = 'Exit', label = 'body' }, id)
    elseif n.tag == 'LocalFunction' then -- luacheck: ignore 542
        -- a unit of its own
    else
        error(('elaborate: unhandled statement %s'):format(n.tag))
    end
end

--- Lowers a verified function to a unit named like its Binder. Its callers are trusted to pass well-typed
--- arguments that meet its `---@pre`s, since some may be outside verification; verified ones check the
--- `---@pre`s. Its body runs in a Block labeled `body`, which `return` exits.
--- @param b Builder
--- @param def SrcLocalFunction
--- @mut b
--- @return NodeId unit
local function function_unit(b, def)
    local fn_id = def.func
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    builder.start_unit(b)
    local body = {}
    for _, p in ipairs(fn.params) do
        local ty = b.info.types[p]
        builder.var(b, builder.name_of(b, p), builder.sort(ty), p)
        if ty == 'int53' then
            local value = builder.add(b, { tag = 'Var', name = builder.name_of(b, p) }, p)
            builder.assume(b, body, 'trusted', builder.is_int53(b, value, p), p, fn_id)
        end
    end
    local result = arena.directives(b.src, fn, 'ClvReturn')[1]
    if result ~= nil then
        builder.var(b, builder.name_of(b, result), builder.sort(b.info.types[result]), result)
    end
    --- @type table<NodeId, NodeId>
    local entry = {}
    for _, p in ipairs(fn.params) do
        if b.res.assigned[p] then
            local t = builder.temp(b, builder.sort(b.info.types[p]), p)
            local value = builder.add(b, { tag = 'Var', name = builder.name_of(b, p) }, p)
            builder.emit(b, body, { tag = 'Assign', target = t, value = value }, p)
            entry[p] = builder.add(b, { tag = 'Var', name = t }, p)
        end
    end
    for _, pre in ipairs(arena.directives(b.src, fn, 'ClvPre')) do
        local cond = (b.src.nodes[pre] --[[@as SrcClvPre]]).cond
        builder.assume(b, body, 'trusted', expr.clause(b, cond, {}), pre, fn_id)
    end
    b.fn = { id = fn_id, result = result, posts = arena.directives(b.src, fn, 'ClvPost'), entry = entry }
    local inner = {}
    statement(b, fn.body, inner)
    -- checks after control has reached end
    if result ~= nil then
        -- Lua would return nothing here. don't let it happen in verified code
        builder.check(b, inner, 'missing_return', builder.add(b, { tag = 'Bool', value = false }, fn_id), fn_id)
    else
        -- add post conds for the implicit return
        check_posts(b, inner, fn_id)
    end
    b.fn = nil
    builder.emit(b, body, { tag = 'Block', label = 'body', body = inner }, fn_id)
    return builder.add(b, { tag = 'Unit', name = builder.name_of(b, def.binder), vars = b.vars, body = body }, fn_id)
end

--- Returns whether a top-level `local function` is verified: marked `---@clavius`, or in a region and not
--- `---@unsafe`.
--- @param b Builder
--- @param def SrcLocalFunction
--- @param in_region boolean
--- @return boolean
local function is_verified(b, def, in_region)
    local fn = b.src.nodes[def.func] --[[@as SrcFunction]]
    if arena.has_directive(b.src, fn, 'ClvMarker') then
        return true
    end
    return in_region and not arena.has_directive(b.src, fn, 'ClvUnsafe')
end

--- Lowers the marked code of a typed file in source order. Each verified function's unit is named like
--- its Binder, and the units of the regions' other statements `main$1`, `main$2` and so on.
--- @param src SrcArena
--- @param root NodeId
--- @param res Resolution
--- @param info TypeInfo
--- @return CoreProgram
function M.run(src, root, res, info)
    local b = builder.new(src, res, info)
    local units = {}
    local regions = 0
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        if n.tag == 'LocalFunction' and is_verified(b, n, false) then
            units[#units + 1] = function_unit(b, n)
        elseif n.tag == 'ClvRegion' then
            local others = {}
            for _, s in ipairs(n.statements) do
                local sn = src.nodes[s]
                if sn.tag ~= 'LocalFunction' then
                    others[#others + 1] = s
                elseif is_verified(b, sn, true) then
                    units[#units + 1] = function_unit(b, sn)
                end
            end
            if #others > 0 then
                builder.start_unit(b)
                local body = {}
                for _, s in ipairs(others) do
                    statement(b, s, body)
                end
                regions = regions + 1
                units[#units + 1] = builder.add(b, { tag = 'Unit', name = ('main$%d'):format(regions), vars = b.vars, body = body }, id)
            end
        end
    end
    return { core = b.core, units = units, obligations = b.obligations, assumptions = b.assumptions }
end

return M
