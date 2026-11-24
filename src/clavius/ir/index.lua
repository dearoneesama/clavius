-- The node index: lookups over a source arena that passes share. It is built once after parsing. The
-- arena never changes after that, so the index stays valid.

local arena = require 'clavius.ir.arena'
local source_nodes = require 'clavius.ir.source_nodes'

-- the nodes that hold ghost code
local GHOST = { ClvSpec = true, ClvLemma = true, ClvProof = true, ClvGhost = true, ClvAssert = true, ClvAssume = true }

--- @class NodeIndex
--- @field by_tag table<string, NodeId[]> the ids of each kind's nodes in ascending order
--- @field parent NodeId[] each node's parent, or 0 for the root
--- @field region NodeId[] the ClvRegion node that a node is in, or 0 outside every region
--- @field unit NodeId[] the root of the unit whose code a node is: its ClvRegion or verified Function. It is 0 for unmarked code, and for contracts and loop annotations, which are spec code.
--- @field ghost NodeId[] the innermost ClvSpec, ClvLemma, ClvProof, ClvGhost, ClvAssert or ClvAssume node around a node, or 0

local M = {}

--- Returns the unit root that the code of a child of `p` belongs to. `unit_of_p` is the one of `p`.
--- @param src SrcArena
--- @param p NodeId
--- @param unit_of_p NodeId
--- @param child NodeId
--- @return NodeId
local function child_unit(src, p, unit_of_p, child)
    local n = src.nodes[p]
    -- spec functions and lemmas are checked wherever they sit
    if n.tag == 'ClvRegion' or n.tag == 'ClvSpec' or n.tag == 'ClvLemma' then
        return p
    elseif n.tag == 'While' or n.tag == 'Repeat' or n.tag == 'Fornum' or n.tag == 'Forin' or n.tag == 'Function' then
        -- keeps a function's contract and a loop's annotations out of the unit
        for _, d in ipairs(n.directives) do
            if d == child then
                return 0
            end
        end
    end
    if n.tag ~= 'Function' then
        return unit_of_p
    end
    -- a function in marked code is verified unless it is `---@unsafe`
    if arena.has_directive(src, n, 'ClvMarker') or (unit_of_p ~= 0 and not arena.has_directive(src, n, 'ClvUnsafe')) then
        return p
    end
    return 0
end

--- Builds the index of a source arena.
--- @param src SrcArena
--- @return NodeIndex
function M.build(src)
    local by_tag = {}
    local parent = {}
    local region = {}
    local unit = {}
    local ghost = {}
    for id = 1, #src.nodes do
        parent[id] = 0
    end
    for id, n in ipairs(src.nodes) do
        local ids = by_tag[n.tag]
        if ids == nil then
            ids = {}
            by_tag[n.tag] = ids
        end
        ids[#ids + 1] = id
        for _, kid in ipairs(source_nodes.children(n)) do
            parent[kid] = id
        end
    end
    -- a parent has a larger id, so this loop reaches it before its children
    for id = #src.nodes, 1, -1 do
        local p = parent[id]
        if p == 0 then
            region[id], unit[id], ghost[id] = 0, 0, 0
        else
            region[id] = src.nodes[p].tag == 'ClvRegion' and p or region[p]
            unit[id] = child_unit(src, p, unit[p], id)
            ghost[id] = GHOST[src.nodes[p].tag] and p or ghost[p]
        end
    end
    return { by_tag = by_tag, parent = parent, region = region, unit = unit, ghost = ghost }
end

return M
