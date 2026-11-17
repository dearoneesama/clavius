-- Runs the verified functions of a program that verifies on LuaJIT, and checks their contracts on what
-- they do. The inputs are the edges of the parameters' types and the numbers around those in the
-- contracts. A raise or a broken `---@post` is a bug in Clavius.

local arena = require 'clavius.ir.arena'
local luassert = require 'luassert'
local source_nodes = require 'clavius.ir.source_nodes'

local M = {}

local INT53 = 2 ^ 53

-- runs per function at most
local MAX_INPUTS = 256

-- the value of a clause that can't be evaluated exactly
local UNKNOWN = setmetatable({}, {
    __tostring = function()
        return 'unknown'
    end,
})

--- A value in a clause: a number, a boolean, or `UNKNOWN`.
--- @alias RunValue number|boolean|table

--- A verified function to run.
--- @class RunFunction
--- @field name string
--- @field fn SrcFunction
--- @field result NodeId|nil its ClvReturn

--- Evaluates a contract clause with exact integers. An arithmetic result beyond ±2^53 may have been
--- rounded, so it is `UNKNOWN`, and so is anything computed from one.
--- @param c CompilerContext
--- @param env table<NodeId, RunValue> the value of each parameter and of the function's value
--- @param id NodeId
--- @return RunValue
local function eval(c, env, id)
    local n = c.src.nodes[id]
    local res = assert(c.res)
    if n.tag == 'Literal' then
        if n.kind == 'number' then
            return assert(tonumber(n.text))
        end
        return n.kind == 'true'
    elseif n.tag == 'Id' then
        local decl = res.decl[id]
        if env[decl] ~= nil then
            return env[decl]
        end
        return eval(c, env, assert(res.constants[decl]))
    elseif n.tag == 'Paren' then
        return eval(c, env, n.expr)
    elseif n.tag == 'UnOp' then
        local a = eval(c, env, n.arg)
        if a == UNKNOWN then
            return UNKNOWN
        end
        return n.op == 'unm' and -a or not a
    end
    assert(n.tag == 'BinOp', n.tag)
    local l = eval(c, env, n.lhs)
    if n.op == 'and' or n.op == 'or' then
        -- `false and x` and `true or x` are known whatever x is
        local decides = n.op == 'or'
        if l == decides then
            return l
        end
        local r = eval(c, env, n.rhs)
        if r == decides then
            return r
        elseif l == UNKNOWN or r == UNKNOWN then
            return UNKNOWN
        end
        return not decides
    end
    local r = eval(c, env, n.rhs)
    if l == UNKNOWN or r == UNKNOWN then
        return UNKNOWN
    end
    local v
    if n.op == 'add' then
        v = l + r
    elseif n.op == 'sub' then
        v = l - r
    elseif n.op == 'mul' then
        v = l * r
    elseif n.op == 'eq' then
        return l == r
    elseif n.op == 'ne' then
        return l ~= r
    elseif n.op == 'lt' then
        return l < r
    elseif n.op == 'le' then
        return l <= r
    elseif n.op == 'gt' then
        return l > r
    else
        return l >= r
    end
    -- operands within ±2^53 give an exact result whenever it is below 2^53 in size
    if math.abs(v) >= INT53 then
        return UNKNOWN
    end
    return v
end

--- Adds the number literals under `id` to `out`, including the values of the constants it reads.
--- @param c CompilerContext
--- @param id NodeId
--- @param out number[]
local function literals(c, id, out)
    local n = c.src.nodes[id]
    local res = assert(c.res)
    if n.tag == 'Literal' and n.kind == 'number' then
        out[#out + 1] = assert(tonumber(n.text))
    elseif n.tag == 'Id' and res.constants[res.decl[id]] then
        literals(c, res.constants[res.decl[id]], out)
    end
    for _, kid in ipairs(source_nodes.children(n)) do
        literals(c, kid, out)
    end
end

--- Returns the candidate values of each parameter of `f`: the edges of `int53`, or both booleans, and
--- for an integer also each number in the contract, one less and one more.
--- @param c CompilerContext
--- @param f RunFunction
--- @return RunValue[][]
local function candidates(c, f)
    local numbers = {}
    for _, d in ipairs(f.fn.directives) do
        literals(c, d, numbers)
    end
    local out = {}
    for i, p in ipairs(f.fn.params) do
        if assert(c.info).types[p] == 'boolean' then
            out[i] = { false, true }
        else
            local seen, list = {}, {}
            local base = { -INT53, -(INT53 - 1), -1, 0, 1, INT53 - 1, INT53 }
            for _, v in ipairs(numbers) do
                base[#base + 1], base[#base + 2], base[#base + 3] = v - 1, v, v + 1
            end
            for _, v in ipairs(base) do
                if not seen[v] and math.abs(v) <= INT53 then
                    seen[v] = true
                    list[#list + 1] = v
                end
            end
            table.sort(list)
            out[i] = list
        end
    end
    return out
end

--- Returns the verified top-level functions of a program, in source order.
--- @param c CompilerContext
--- @return RunFunction[]
local function verified(c)
    local index = assert(c.index)
    local out = {}
    for _, id in ipairs(index.by_tag.LocalFunction or {}) do
        local def = c.src.nodes[id] --[[@as SrcLocalFunction]]
        local fn = c.src.nodes[def.func] --[[@as SrcFunction]]
        if index.unit[fn.body] == def.func then
            local name = (c.src.nodes[def.binder] --[[@as SrcBinder]]).name
            out[#out + 1] = { name = name, fn = fn, result = arena.directives(c.src, fn, 'ClvReturn')[1] }
        end
    end
    return out
end

--- Returns whether a value has a type.
--- @param value any
--- @param ty Type
--- @return boolean
local function has_type(value, ty)
    if ty == 'boolean' then
        return type(value) == 'boolean'
    end
    return type(value) == 'number' and value == math.floor(value) and math.abs(value) <= INT53
end

--- Runs `f`, exported as `run`, on every input that meets its `---@pre`s, up to `MAX_INPUTS` spread over
--- all of them, and fails when it raises, returns a value of the wrong type, or breaks a `---@post`.
--- @param c CompilerContext
--- @param f RunFunction
--- @param run function
local function check_function(c, f, run)
    local lists = candidates(c, f)
    local total = 1
    for _, list in ipairs(lists) do
        total = total * #list
    end
    local step = math.max(1, math.floor(total / MAX_INPUTS))
    for k = 0, total - 1, step do
        -- the k-th combination, with the first parameter varying fastest
        local args, env = {}, {}
        local rest = k
        for i, list in ipairs(lists) do
            args[i] = list[rest % #list + 1]
            rest = math.floor(rest / #list)
            env[f.fn.params[i]] = args[i]
        end
        local meets = true
        for _, pre in ipairs(arena.directives(c.src, f.fn, 'ClvPre')) do
            meets = meets and eval(c, env, (c.src.nodes[pre] --[[@as SrcClvPre]]).cond) == true
        end
        if meets then
            local shown = {}
            for i, a in ipairs(args) do
                shown[i] = type(a) == 'number' and ('%.17g'):format(a) or tostring(a)
            end
            local call = ('%s(%s)'):format(f.name, table.concat(shown, ', '))
            local ok, value = pcall(run, unpack(args))
            luassert(ok, ('%s raised: %s'):format(call, tostring(value)))
            if f.result ~= nil then
                local ty = assert(c.info).types[f.result]
                luassert(has_type(value, ty), ('%s returned %s, which is not %s'):format(call, tostring(value), ty))
                env[f.result] = value
            end
            for _, post in ipairs(arena.directives(c.src, f.fn, 'ClvPost')) do
                local holds = eval(c, env, (c.src.nodes[post] --[[@as SrcClvPost]]).cond)
                local clause = c.text:sub(c.src.spans[post].start, c.src.spans[post].finish)
                luassert(holds ~= false, ('%s returned %s, which breaks `%s`'):format(call, tostring(value), clause))
            end
        end
    end
end

--- Runs the verified functions of the program in `c`, which has verified, and checks their contracts.
--- The program is loaded again with a `return` of its functions appended.
--- @param c CompilerContext a context after `validate`
--- @param path string the program's file, for messages
function M.check(c, path)
    local fns = verified(c)
    if #fns == 0 then
        return
    end
    local names = {}
    for i, f in ipairs(fns) do
        names[i] = f.name
    end
    local chunk = assert(loadstring(('%s\nreturn { %s }\n'):format(c.text, table.concat(names, ', ')), '=' .. path))
    local exported = chunk()
    for i, f in ipairs(fns) do
        check_function(c, f, exported[i])
    end
end

return M
