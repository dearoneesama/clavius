-- Builds a core program from the source arena. Every core node gets the span of the source node it
-- comes from, and every `Check` gets an obligation that points at that source node.

local arena = require 'clavius.ir.arena'

--- The function whose unit is being built.
--- @class BuilderFunction
--- @field id NodeId its Function node
--- @field result NodeId|nil its ClvReturn
--- @field posts NodeId[] its ClvPost nodes
--- @field entry table<NodeId, NodeId> the snapshot taken on entry of each parameter the body assigns, as a Var term

--- @class Builder
--- @field src SrcArena
--- @field res Resolution
--- @field info TypeInfo
--- @field effects Effects
--- @field termination Termination
--- @field core CoreArena
--- @field decls NodeId[] the SortDecl, FunDecl and Axiom nodes
--- @field obligations Obligation[]
--- @field assumptions Assumption[]
--- @field vars NodeId[] the VarDecl nodes of the unit being built
--- @field declared table<string, boolean> the names of those variables
--- @field temps integer the temporaries of the unit being built
--- @field loops integer the loops of the unit being built
--- @field breaks string[] the Block labels of the loops around the statement being lowered, innermost last
--- @field fn BuilderFunction|nil
--- @field spec boolean whether a contract clause is being lowered: its arithmetic is exact and has no checks
--- @field ghost boolean whether spec or proof code is being lowered: its arithmetic is exact
--- @field subst table<NodeId, NodeId> the term that stands for each declaration in the clause being lowered

local M = {}

-- int53 is ±2^53 with both bounds included
local INT53_MIN = '-9007199254740992'
local INT53_MAX = '9007199254740992'

--- @param src SrcArena
--- @param res Resolution
--- @param info TypeInfo
--- @param effects Effects
--- @param termination Termination
--- @return Builder
function M.new(src, res, info, effects, termination)
    return {
        src = src,
        res = res,
        info = info,
        effects = effects,
        termination = termination,
        core = arena.new_core(),
        decls = {},
        obligations = {},
        assumptions = {},
        vars = {},
        declared = {},
        temps = 0,
        loops = 0,
        breaks = {},
        fn = nil,
        spec = false,
        ghost = false,
        subst = {},
    }
end

--- Adds a core node that comes from the source node `origin`.
--- @param b Builder
--- @param node CoreNode
--- @param origin NodeId
--- @mut b
--- @return NodeId
function M.add(b, node, origin)
    return arena.add_core(b.core, node, b.src.spans[origin])
end

--- Adds a statement to `out`.
--- @param b Builder
--- @param out NodeId[]
--- @param node CoreNode
--- @param origin NodeId
--- @mut b
--- @mut out
function M.emit(b, out, node, origin)
    out[#out + 1] = M.add(b, node, origin)
end

--- Adds a check of `cond` to `out`, with an obligation of `kind` on the source node `origin`. A contract
--- obligation names its clause.
--- @param b Builder
--- @param out NodeId[]
--- @param kind ObligationKind
--- @param cond NodeId
--- @param origin NodeId
--- @param clause NodeId|nil
--- @mut b
--- @mut out
function M.check(b, out, kind, cond, origin, clause)
    b.obligations[#b.obligations + 1] = { kind = kind, node = origin, clause = clause }
    M.emit(b, out, { tag = 'Check', obligation = #b.obligations, cond = cond }, origin)
end

--- Adds an assumption of `cond` to `out`, justified by `kind`, from the source node `origin`. A trusted
--- one names the Function it trusts.
--- @param b Builder
--- @param out NodeId[]
--- @param kind Justification
--- @param cond NodeId
--- @param origin NodeId
--- @param decl NodeId|nil
--- @mut b
--- @mut out
function M.assume(b, out, kind, cond, origin, decl)
    b.assumptions[#b.assumptions + 1] = { kind = kind, node = origin, decl = decl }
    M.emit(b, out, { tag = 'Assume', assumption = #b.assumptions, cond = cond }, origin)
end

--- Starts a new unit with no variables.
--- @param b Builder
--- @mut b
function M.start_unit(b)
    b.vars, b.declared = {}, {}
    b.temps, b.loops = 0, 0
end

--- Declares a variable of the unit being built.
--- @param b Builder
--- @param name string
--- @param sort string
--- @param origin NodeId
--- @mut b
function M.var(b, name, sort, origin)
    b.vars[#b.vars + 1] = M.add(b, { tag = 'VarDecl', name = name, sort = sort }, origin)
    b.declared[name] = true
end

--- Declares a fresh variable. Its name starts with `$`, so it can't clash with a Lua name.
--- @param b Builder
--- @param sort string
--- @param origin NodeId
--- @mut b
--- @return string name
function M.temp(b, sort, origin)
    b.temps = b.temps + 1
    local name = ('$t%d'):format(b.temps)
    M.var(b, name, sort, origin)
    return name
end

--- Returns a fresh label for a loop's Block: `loop$1`, `loop$2` and so on in each unit.
--- @param b Builder
--- @mut b
--- @return string
function M.loop_label(b)
    b.loops = b.loops + 1
    return ('loop$%d'):format(b.loops)
end

--- Returns the term `-2^53 <= t and t <= 2^53`.
--- @param b Builder
--- @param t NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId
function M.is_int53(b, t, origin)
    local lo = M.add(b, { tag = 'BinOp', op = '<=', lhs = M.add(b, { tag = 'Int', text = INT53_MIN }, origin), rhs = t }, origin)
    local hi = M.add(b, { tag = 'BinOp', op = '<=', lhs = t, rhs = M.add(b, { tag = 'Int', text = INT53_MAX }, origin) }, origin)
    return M.add(b, { tag = 'BinOp', op = 'and', lhs = lo, rhs = hi }, origin)
end

--- Returns the term that says the measure `after` is below `before` in the lexicographic order: at
--- some position the expression was non-negative and is now smaller, and every expression before that
--- position is unchanged. Both lists have the same length. Only `before` is bounded below, so the
--- step to `after` may overshoot below zero.
--- e.g. for `(a1, b1)` below `(a0, b0)`:
---
---     (BinOp or
---       (BinOp and (BinOp <= (Int 0) a0) (BinOp < a1 a0))
---       (BinOp and (BinOp == a1 a0) (BinOp and (BinOp <= (Int 0) b0) (BinOp < b1 b0))))
--- @param b Builder
--- @param before NodeId[]
--- @param after NodeId[]
--- @param origin NodeId
--- @mut b
--- @return NodeId
function M.decreases(b, before, after, origin)
    assert(#before == #after, 'builder: measures of different lengths')
    -- built from the last position, where only a decrease will do
    local cond = nil
    for i = #before, 1, -1 do
        local zero = M.add(b, { tag = 'Int', text = '0' }, origin)
        local bounded = M.add(b, { tag = 'BinOp', op = '<=', lhs = zero, rhs = before[i] }, origin)
        local smaller = M.add(b, { tag = 'BinOp', op = '<', lhs = after[i], rhs = before[i] }, origin)
        local here = M.add(b, { tag = 'BinOp', op = 'and', lhs = bounded, rhs = smaller }, origin) -- decreases at i
        if cond ~= nil then
            local same = M.add(b, { tag = 'BinOp', op = '==', lhs = after[i], rhs = before[i] }, origin)
            local later = M.add(b, { tag = 'BinOp', op = 'and', lhs = same, rhs = cond }, origin) -- decreases after i
            here = M.add(b, { tag = 'BinOp', op = 'or', lhs = here, rhs = later }, origin)
        end
        cond = here
    end
    return assert(cond, 'builder: a measure with no expression')
end

--- Returns the core sort of a type.
--- @param ty Type
--- @return string
function M.sort(ty)
    if ty == 'boolean' then
        return 'bool'
    end
    return 'int'
end

--- Returns whether a value of type `ty` satisfies a fact that not every value of its sort does, which
--- `type_fact` gives.
--- @param ty Type|nil
--- @return boolean
function M.has_type_fact(ty)
    return ty == 'int53'
end

--- Returns the fact that a value of type `ty` satisfies, or nil when every value of its sort does: an
--- `int53` is within ±2^53.
--- @param b Builder
--- @param ty Type|nil
--- @param t NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId|nil
function M.type_fact(b, ty, t, origin)
    if ty == 'int53' then
        return M.is_int53(b, t, origin)
    end
    return nil
end

--- Returns the variable that holds a local or a function's value: the unique name of the Binder or
--- ClvReturn that `id` is or refers to.
--- @param b Builder
--- @param id NodeId
--- @return string
function M.name_of(b, id)
    local binder = b.res.decl[id] or id
    return b.res.names[binder]
end

return M
