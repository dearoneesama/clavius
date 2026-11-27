-- Builds a core program from the source arena. Every core node gets the span of the source node it
-- comes from, and every `Check` gets an obligation that points at that source node.

local arena = require 'clavius.ir.arena'

--- The function whose unit is being built.
--- @class BuilderFunction
--- @field id NodeId its Function node
--- @field kind 'exec' | 'spec' | 'lemma'
--- @field result NodeId|nil its ClvReturn
--- @field posts NodeId[] its ClvPost nodes
--- @field entry table<NodeId, NodeId> the snapshot taken on entry of each parameter the body assigns, as a Var term

--- A spec function's declarations: the FunDecl that stands for it, and the constant that guards its
--- axioms. Only a recursive one takes fuel, its FunDecl's first parameter.
--- @class BuilderSpec
--- @field id NodeId its Function node
--- @field name string
--- @field guard string
--- @field recursive boolean

--- The spec function whose definition is being lowered to an axiom: calls in its cycle take the fuel
--- that the axiom binds.
--- @class BuilderAxiom
--- @field fn NodeId the Function node
--- @field fuel string the bound fuel variable

--- @class Builder
--- @field src SrcArena
--- @field index NodeIndex
--- @field res Resolution
--- @field info TypeInfo
--- @field effects Effects
--- @field termination Termination
--- @field triggers Triggers
--- @field core CoreArena
--- @field decls NodeId[] the SortDecl, FunDecl and Axiom nodes
--- @field obligations Obligation[]
--- @field assumptions Assumption[]
--- @field specs BuilderSpec[] the spec functions in source order
--- @field spec_of table<NodeId, BuilderSpec> each spec function's by its Function node
--- @field fuel table<NodeId, integer> how often the unit being built may unfold each spec function, when not once
--- @field axiom BuilderAxiom|nil
--- @field vars NodeId[] the VarDecl nodes of the unit being built
--- @field declared table<string, boolean> the names of those variables
--- @field temps integer the temporaries of the unit being built
--- @field loops integer the loops of the unit being built
--- @field breaks string[] the Block labels of the loops around the statement being lowered, innermost last
--- @field fn BuilderFunction|nil
--- @field spec boolean whether a contract clause is being lowered: its arithmetic is exact and has no checks
--- @field ghost boolean whether spec or proof code is being lowered: its arithmetic is exact
--- @field subst table<NodeId, NodeId> the term that stands for each declaration in the clause being lowered
--- @field inline table<NodeId, NodeId>|nil while a trigger is being lowered, the value that stands for each `local` of a quantifier's body

local M = {}

-- int53 is ±2^53 with both bounds included
local INT53_MIN = '-9007199254740992'
local INT53_MAX = '9007199254740992'

--- @param src SrcArena
--- @param index NodeIndex
--- @param res Resolution
--- @param info TypeInfo
--- @param effects Effects
--- @param termination Termination
--- @param triggers Triggers
--- @return Builder
function M.new(src, index, res, info, effects, termination, triggers)
    return {
        src = src,
        index = index,
        res = res,
        info = info,
        effects = effects,
        termination = termination,
        triggers = triggers,
        core = arena.new_core(),
        decls = {},
        obligations = {},
        assumptions = {},
        specs = {},
        spec_of = {},
        fuel = {},
        axiom = nil,
        vars = {},
        declared = {},
        temps = 0,
        loops = 0,
        breaks = {},
        fn = nil,
        spec = false,
        ghost = false,
        subst = {},
        inline = nil,
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
    return ty == 'int53' or ty == 'Nat'
end

--- Returns the fact that a value of type `ty` satisfies, or nil when every value of its sort does: an
--- `int53` is within ±2^53 and a `Nat` is non-negative.
--- @param b Builder
--- @param ty Type|nil
--- @param t NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId|nil
function M.type_fact(b, ty, t, origin)
    if ty == 'int53' then
        return M.is_int53(b, t, origin)
    elseif ty == 'Nat' then
        return M.add(b, { tag = 'BinOp', op = '<=', lhs = M.add(b, { tag = 'Int', text = '0' }, origin), rhs = t }, origin)
    end
    return nil
end

--- Checks, in ghost code, that `t` fits where a value of the narrower type `to` is expected: a `Nat` is
--- non-negative, and an `int53` is within ±2^53. A value of type `from` already does when it is `to`.
--- @param b Builder
--- @param out NodeId[]
--- @param to Type|nil
--- @param from Type|nil
--- @param t NodeId
--- @param origin NodeId
--- @mut b
--- @mut out
function M.narrow(b, out, to, from, t, origin)
    if to == from or b.spec then
        return
    elseif to == 'Nat' then
        M.check(b, out, 'nat', assert(M.type_fact(b, to, t, origin)), origin)
    elseif to == 'int53' then
        M.check(b, out, 'range', M.is_int53(b, t, origin), origin)
    end
end

--- Returns the term for `fuel` unfoldings: `$succ` applied that often to `$zero`.
--- @param b Builder
--- @param fuel integer
--- @param origin NodeId
--- @mut b
--- @return NodeId
function M.fuel(b, fuel, origin)
    local t = M.add(b, { tag = 'App', fn = '$zero', args = {} }, origin)
    for _ = 1, fuel do
        t = M.add(b, { tag = 'App', fn = '$succ', args = { t } }, origin)
    end
    return t
end

--- Returns whether two functions are in one cycle of recursive calls.
--- @param b Builder
--- @param f NodeId
--- @param g NodeId
--- @return boolean
function M.same_cycle(b, f, g)
    local cycle = b.termination.cycle[f]
    return cycle ~= nil and cycle == b.termination.cycle[g]
end

--- Assumes the axioms of every spec function but those in the cycle of `except`, if any, which is the
--- spec function whose unit is being built. That unit checks that the definitions in its cycle are
--- well founded, so it may not rely on them.
--- @param b Builder
--- @param out NodeId[]
--- @param except NodeId|nil a spec function's Function node
--- @param origin NodeId
--- @mut b
--- @mut out
function M.definitions(b, out, except, origin)
    -- this spits out all assumptions although some may not needed.
    for _, spec in ipairs(b.specs) do
        if except == nil or not (spec.id == except or M.same_cycle(b, spec.id, except)) then
            M.assume(b, out, 'definition', M.add(b, { tag = 'App', fn = spec.guard, args = {} }, origin), origin)
        end
    end
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
