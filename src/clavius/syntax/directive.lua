-- The grammar of each directive tag: a `---@tag args` comment becomes source nodes. For example
-- `---@param n int53 the count` becomes `(ClvParam n false (ClvTypeName int53))`, and `---@pre n > 0`
-- a ClvPre node over the Lua expression `n > 0`.
--
-- source for the LuaLS tags: LuaLS 3.19.2's script/parser/luadoc.lua (https://github.com/LuaLS/lua-language-server)

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local typeexpr = require 'clavius.syntax.typeexpr'

--- Parses Lua code that sits at offset `start` of the file, such as the `n > 0` of `---@pre n > 0`, as
--- the values of `return code`. Returns their nodes and the syntax errors.
--- Used to avoid require cycle.
--- @alias CodeParser fun(code: string, start: integer): NodeId[], Diag[]

--- What a tag's grammar reads and where it puts what it makes.
--- @class GrammarState
--- @field src SrcArena
--- @field lx DocLexer
--- @field d Directive
--- @field code_parser CodeParser
--- @field diags Diag[]

--- Reads one tag's arguments and returns the nodes it makes.
--- @alias Grammar fun(g: GrammarState): NodeId[]

local M = {}

local THEORIES = { nonlinear_arith = true, bit_vector = true }

local VISIBILITY = { public = true, protected = true, private = true, package = true }

--- The node kind of each tag that takes no arguments.
--- @type table<string, SrcTag>
local FLAGS = { unsafe = 'ClvUnsafe', entry = 'ClvEntry', extern = 'ClvExtern', no_callback = 'ClvNoCallback', may_raise = 'ClvMayRaise' }

--- The node kind of each tag whose argument is one Lua expression.
--- @type table<string, SrcTag>
local CLAUSES = {
    pre = 'ClvPre',
    post = 'ClvPost',
    invariant = 'ClvInvariant',
    module_invariant = 'ClvModuleInvariant',
    closure_invariant = 'ClvClosureInvariant',
}

--- Raises a grammar error at `s`.
--- @param s Span
--- @param key string
local function fail_at(s, key)
    --- @type DocError
    local e = { diag = diag.at_span('E-syntax', s, { key }) }
    error(e, 0)
end

--- Adds a directive node. It spans the whole directive.
--- @param g GrammarState
--- @param node SrcNode
--- @mut g
--- @return NodeId
local function add(g, node)
    return arena.add_src(g.src, node, g.d.span)
end

--- Raises an error unless the directive ends after the last token taken. Clavius tags take no
--- description.
--- @param lx DocLexer
local function finish(lx)
    if not typeexpr.at_end(lx) then
        typeexpr.fail(lx, 'unexpected-text')
    end
end

--- Takes a name token.
--- @param lx DocLexer
--- @param lua boolean whether it must be a Lua identifier rather than any LuaLS name such as `a.b`
--- @mut lx
--- @return string
local function name(lx, lua)
    local t = typeexpr.peek(lx)
    if not t or t.kind ~= 'name' or (lua and not t.text:match '^[%a_][%w_]*$') then
        typeexpr.fail(lx, 'expected-name')
    end
    --- @cast t DocToken
    typeexpr.next(lx)
    return t.text
end

--- Takes a positive integer token.
--- @param lx DocLexer
--- @mut lx
--- @return integer
local function count(lx)
    local t = typeexpr.peek(lx)
    local n = t and t.kind == 'integer' and tonumber(t.text) --[[@as integer|nil]]
    if not n or n < 1 then
        typeexpr.fail(lx, 'expected-positive-integer')
    end
    typeexpr.next(lx)
    return n --[[@as integer]]
end

--- Takes LuaLS attributes such as `(exact)`, which must be among `allowed`.
--- @param lx DocLexer
--- @param allowed table<string, boolean>
--- @mut lx
--- @return table<string, boolean>
local function attrs(lx, allowed)
    local out = {}
    if typeexpr.symbol(lx, '(') then
        repeat
            local t = typeexpr.peek(lx)
            local a = name(lx, false)
            if not allowed[a] then
                typeexpr.fail(lx, 'unknown-attribute', t)
            end
            out[a] = true
        until not typeexpr.symbol(lx, ',')
        typeexpr.expect(lx, ')')
    end
    return out
end

--- Takes the `<T, U>` after a class or alias name, or nothing.
--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function generics(g)
    local t = typeexpr.peek(g.lx)
    if t and t.kind == 'symbol' and t.text == '<' then
        return typeexpr.generics(g.src, g.lx)
    end
    return {}
end

--- Parses the directive's argument as Lua expressions. Returns nil when the code has errors, which go
--- to `g.diags`.
--- @param g GrammarState
--- @mut g
--- @return NodeId[]|nil
local function expressions(g)
    if g.d.args == '' then
        typeexpr.fail(g.lx, 'expected-code')
    end
    local values, diags = g.code_parser(g.d.args, g.d.args_span.start)
    for _, e in ipairs(diags) do
        g.diags[#g.diags + 1] = e
    end
    if #diags > 0 then
        return nil
    end
    return values
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function marker(g)
    local t = typeexpr.peek(g.lx)
    if t and t.kind == 'name' and (t.text == 'begin' or t.text == 'end') then
        typeexpr.next(g.lx)
    elseif typeexpr.at_end(g.lx) then
        return { add(g, { tag = 'ClvMarker' }) }
    end
    if not typeexpr.at_end(g.lx) then
        typeexpr.fail(g.lx, 'clavius-args')
    end
    -- a region marker makes no node
    return {}
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function flag(g)
    finish(g.lx)
    return {
        add(g, { tag = FLAGS[g.d.tag] } --[[@as SrcNode]]),
    }
end

--- @param _g GrammarState
--- @return NodeId[]
local function none(_g)
    return {}
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function clause(g)
    local values = expressions(g)
    if not values then
        return {}
    end
    if #values ~= 1 then
        fail_at(g.d.args_span, 'one-expression')
    end
    return {
        add(g, { tag = CLAUSES[g.d.tag], cond = values[1] } --[[@as SrcNode]]),
    }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function decrease(g)
    local values = expressions(g)
    if not values then
        return {}
    end
    return { add(g, { tag = 'ClvDecrease', measures = values }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function mode(g)
    local tag = g.d.tag
    if tag == 'frozen' then
        local n = typeexpr.peek(g.lx) and name(g.lx, true) or nil
        finish(g.lx)
        return { add(g, { tag = 'ClvFrozen', name = n }) }
    end
    local n = name(g.lx, true)
    finish(g.lx)
    if tag == 'mut' then
        return { add(g, { tag = 'ClvMut', name = n }) }
    end
    return { add(g, { tag = 'ClvMove', name = n }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function len(g)
    local param = name(g.lx, true)
    local length = name(g.lx, true)
    finish(g.lx)
    return { add(g, { tag = 'ClvLen', param = param, length = length }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function disjoint(g)
    local first = name(g.lx, true)
    typeexpr.expect(g.lx, ',')
    local second = name(g.lx, true)
    finish(g.lx)
    return { add(g, { tag = 'ClvDisjoint', first = first, second = second }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function rlimit(g)
    local limit = count(g.lx)
    finish(g.lx)
    return { add(g, { tag = 'ClvRlimit', limit = limit }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function proof_by(g)
    typeexpr.expect(g.lx, '(')
    local t = typeexpr.peek(g.lx)
    if not t or not THEORIES[t.text] then
        typeexpr.fail(g.lx, 'unknown-theory')
    end
    --- @cast t DocToken
    typeexpr.next(g.lx)
    typeexpr.expect(g.lx, ')')
    finish(g.lx)
    return {
        add(g, {
            tag = 'ClvProofBy',
            theory = t.text --[[@as 'nonlinear_arith' | 'bit_vector']],
        }),
    }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function fuel(g)
    typeexpr.expect(g.lx, '(')
    local f = name(g.lx, true)
    typeexpr.expect(g.lx, ',')
    local n = count(g.lx)
    typeexpr.expect(g.lx, ')')
    finish(g.lx)
    return { add(g, { tag = 'ClvRevealWithFuel', name = f, fuel = n }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function param(g)
    local n
    if typeexpr.symbol(g.lx, '...') then
        n = '...'
    else
        n = name(g.lx, false)
    end
    local optional = typeexpr.symbol(g.lx, '?') ~= nil
    local ty = typeexpr.parse(g.src, g.lx)
    return { add(g, { tag = 'ClvParam', name = n, optional = optional, type = ty }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function returns(g)
    local out = {}
    repeat
        local ty = typeexpr.parse(g.src, g.lx)
        local n = nil
        local t = typeexpr.peek(g.lx)
        if t and (t.kind == 'name' or t.text == '...') then
            typeexpr.next(g.lx)
            n = t.text
        end
        out[#out + 1] = add(g, { tag = 'ClvReturn', name = n, type = ty })
    until not typeexpr.symbol(g.lx, ',')
    return out
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function type_list(g)
    local types = {}
    repeat
        types[#types + 1] = typeexpr.parse(g.src, g.lx)
    until not typeexpr.symbol(g.lx, ',')
    return { add(g, { tag = 'ClvType', types = types }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function typed(g)
    local tag = g.d.tag
    local t = typeexpr.peek(g.lx)
    if tag == 'overload' and not (t and t.kind == 'name' and (t.text == 'fun' or t.text == 'async')) then
        typeexpr.fail(g.lx, 'expected-fun')
    end
    local ty = typeexpr.parse(g.src, g.lx)
    if tag == 'vararg' then
        return { add(g, { tag = 'ClvVararg', type = ty }) }
    elseif tag == 'overload' then
        return { add(g, { tag = 'ClvOverload', type = ty }) }
    end
    return { add(g, { tag = 'ClvAs', type = ty }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function class(g)
    local a = attrs(g.lx, { exact = true, partial = true })
    local n = name(g.lx, false)
    local gs = generics(g)
    local parents = {}
    if typeexpr.symbol(g.lx, ':') then
        repeat
            parents[#parents + 1] = typeexpr.unit(g.src, g.lx)
        until not typeexpr.symbol(g.lx, ',')
    end
    local node = { tag = 'ClvClass', exact = a.exact == true, partial = a.partial == true, name = n, generics = gs, parents = parents }
    return { add(g, node) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function field(g)
    local lx = g.lx
    local t = typeexpr.peek(lx)
    local after = typeexpr.peek(lx, 2)
    local last = typeexpr.peek(lx, 3)
    -- a visibility changes only what an editor shows; `---@field private integer` is a field named `private`
    if t and t.kind == 'name' and VISIBILITY[t.text] and after and not (after.kind == 'name' and not last) then
        typeexpr.next(lx)
    end
    local n, key = nil, nil
    if typeexpr.symbol(lx, '[') then
        key = typeexpr.parse_inner(g.src, lx)
        typeexpr.expect(lx, ']')
    else
        n = name(lx, false)
    end
    local optional = typeexpr.symbol(lx, '?') ~= nil
    local ty = typeexpr.parse(g.src, lx)
    return { add(g, { tag = 'ClvField', key = key, name = n, optional = optional, type = ty }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function alias(g)
    attrs(g.lx, {})
    local n = name(g.lx, false)
    local gs = generics(g)
    return { add(g, { tag = 'ClvAlias', name = n, generics = gs, type = typeexpr.parse(g.src, g.lx) }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function enum(g)
    local a = attrs(g.lx, { key = true, partial = true })
    return { add(g, { tag = 'ClvEnum', key = a.key == true, partial = a.partial == true, name = name(g.lx, false) }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function generic(g)
    local out = {}
    repeat
        local n = name(g.lx, false)
        local bound = nil
        if typeexpr.symbol(g.lx, ':') then
            bound = typeexpr.parse_inner(g.src, g.lx)
        end
        out[#out + 1] = add(g, { tag = 'ClvGeneric', name = n, bound = bound })
    until not typeexpr.symbol(g.lx, ',')
    return out
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function cast(g)
    local n = name(g.lx, false)
    local out = {}
    repeat
        --- @type 'set' | 'add' | 'remove'
        local m = 'set'
        if typeexpr.symbol(g.lx, '+') then
            m = 'add'
        elseif typeexpr.symbol(g.lx, '-') then
            m = 'remove'
        end
        local ty = nil
        if not typeexpr.symbol(g.lx, '?') then
            ty = typeexpr.parse(g.src, g.lx)
        end
        out[#out + 1] = add(g, { tag = 'ClvCast', name = n, mode = m, type = ty })
    until not typeexpr.symbol(g.lx, ',')
    return out
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function operator(g)
    local op = name(g.lx, false)
    local operand = nil
    if typeexpr.symbol(g.lx, '(') and not typeexpr.symbol(g.lx, ')') then
        operand = typeexpr.parse_inner(g.src, g.lx)
        typeexpr.expect(g.lx, ')')
    end
    typeexpr.expect(g.lx, ':')
    local result = typeexpr.parse(g.src, g.lx)
    return { add(g, { tag = 'ClvOperator', op = op, operand = operand, result = result }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function meta(g)
    local t = typeexpr.peek(g.lx)
    local n = nil
    if t and t.kind == 'name' then
        typeexpr.next(g.lx)
        n = t.text
    end
    return { add(g, { tag = 'ClvMeta', name = n }) }
end

--- @param g GrammarState
--- @mut g
--- @return NodeId[]
local function module(g)
    local t = typeexpr.peek(g.lx)
    if not t or t.kind ~= 'string' then
        typeexpr.fail(g.lx, 'expected-string')
    end
    --- @cast t DocToken
    typeexpr.next(g.lx)
    return { add(g, { tag = 'ClvModule', name = t.text }) }
end

--- @type table<string, Grammar>
local GRAMMARS = {
    clavius = marker,
    unsafe = flag,
    entry = flag,
    extern = flag,
    no_callback = flag,
    may_raise = flag,
    pre = clause,
    post = clause,
    invariant = clause,
    module_invariant = clause,
    closure_invariant = clause,
    decrease = decrease,
    -- their code is read with the file's
    ghost = none,
    proof = none,
    assert = none,
    mut = mode,
    move = mode,
    frozen = mode,
    len = len,
    disjoint = disjoint,
    rlimit = rlimit,
    proof_by = proof_by,
    reveal_with_fuel = fuel,
    param = param,
    ['return'] = returns,
    type = type_list,
    vararg = typed,
    overload = typed,
    as = typed,
    class = class,
    field = field,
    alias = alias,
    enum = enum,
    generic = generic,
    cast = cast,
    operator = operator,
    meta = meta,
    module = module,
}

--- Returns whether `tag` is a directive tag that Clavius reads. Any other tag, such as LuaLS's
--- `---@deprecated` or another tool's, changes nothing that Clavius verifies, so it is ignored.
--- @param tag string
--- @return boolean
function M.is_tag(tag)
    return GRAMMARS[tag] ~= nil
end

--- Parses a directive into source nodes and returns them. `---@return T1, T2`, `---@generic` and
--- `---@cast` make one node per item, and region markers, ghost code and the tags Clavius ignores make
--- none. With errors, the nodes are incomplete.
--- @param src SrcArena
--- @param d Directive
--- @param code_parser CodeParser parses the Lua code in `---@pre` and the like
--- @mut src
--- @return NodeId[] nodes
--- @return Diag[] diags
function M.parse(src, d, code_parser)
    local grammar = GRAMMARS[d.tag]
    if not grammar then
        return {}, {}
    end
    local lines = { { text = d.args, start = d.args_span.start } }
    for _, c in ipairs(d.next_lines) do
        -- the text after `---`
        lines[#lines + 1] = { text = c.text:sub(2), start = c.span.start + 3 }
    end
    --- @type GrammarState
    local g = { src = src, lx = typeexpr.lexer(d.span.file, lines), d = d, code_parser = code_parser, diags = {} }
    local ok, result = pcall(grammar, g)
    if ok then
        return result, --[[@as NodeId[] ]]
            g.diags
    end
    local e = result --[[@as DocError]]
    if type(e) == 'table' and e.diag then
        g.diags[#g.diags + 1] = e.diag
        return {}, g.diags
    end
    error(result, 0)
end

return M
