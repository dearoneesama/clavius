-- Builds a core program from the source arena. Every core node gets the span of the source node it
-- comes from, and every `Check` gets an obligation that points at that source node.

local arena = require 'clavius.ir.arena'

--- @class Builder
--- @field src SrcArena
--- @field res Resolution
--- @field info TypeInfo
--- @field core CoreArena
--- @field obligations Obligation[]
--- @field assumptions Assumption[]
--- @field vars NodeId[] the VarDecl nodes of the unit being built
--- @field temps integer the temporaries of the unit being built

local M = {}

-- int53 is ±2^53 with both bounds included
local INT53_MIN = '-9007199254740992'
local INT53_MAX = '9007199254740992'

--- @param src SrcArena
--- @param res Resolution
--- @param info TypeInfo
--- @return Builder
function M.new(src, res, info)
    return { src = src, res = res, info = info, core = arena.new_core(), obligations = {}, assumptions = {}, vars = {}, temps = 0 }
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

--- Adds a check of `cond` to `out`, with an obligation of `kind` on the source node `origin`.
--- @param b Builder
--- @param out NodeId[]
--- @param kind ObligationKind
--- @param cond NodeId
--- @param origin NodeId
--- @mut b
--- @mut out
function M.check(b, out, kind, cond, origin)
    b.obligations[#b.obligations + 1] = { kind = kind, node = origin }
    M.emit(b, out, { tag = 'Check', obligation = #b.obligations, cond = cond }, origin)
end

--- Declares a variable of the unit being built.
--- @param b Builder
--- @param name string
--- @param sort 'int' | 'bool'
--- @param origin NodeId
--- @mut b
function M.var(b, name, sort, origin)
    b.vars[#b.vars + 1] = M.add(b, { tag = 'VarDecl', name = name, sort = sort }, origin)
end

--- Declares a fresh variable. Its name starts with `$`, so it can't clash with a Lua name.
--- @param b Builder
--- @param sort 'int' | 'bool'
--- @param origin NodeId
--- @mut b
--- @return string name
function M.temp(b, sort, origin)
    b.temps = b.temps + 1
    local name = ('$t%d'):format(b.temps)
    M.var(b, name, sort, origin)
    return name
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

--- Returns the core sort of a type.
--- @param ty Type
--- @return 'int' | 'bool'
function M.sort(ty)
    if ty == 'int53' then
        return 'int'
    end
    return 'bool'
end

--- Returns the variable that holds a local: the unique name of the Binder that `id` (a Binder or an Id)
--- refers to.
--- @param b Builder
--- @param id NodeId
--- @return string
function M.name_of(b, id)
    local binder = b.res.decl[id] or id
    return b.res.names[binder]
end

return M
