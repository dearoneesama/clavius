-- The node index: lookups over a source arena that passes share. It is built once after parsing. The
-- arena never changes after that, so the index stays valid.

local source_nodes = require 'clavius.ir.source_nodes'

--- @class NodeIndex
--- @field by_tag table<string, NodeId[]> the ids of each kind's nodes in ascending order
--- @field parent NodeId[] each node's parent, or 0 for the root
--- @field region NodeId[] the ClvRegion node that a node is in, or 0 outside every region

local M = {}

--- Builds the index of a source arena.
--- @param src SrcArena
--- @return NodeIndex
function M.build(src)
    local by_tag, parent, region = {}, {}, {}
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
            region[id] = 0
        elseif src.nodes[p].tag == 'ClvRegion' then
            region[id] = p
        else
            region[id] = region[p]
        end
    end
    return { by_tag = by_tag, parent = parent, region = region }
end

return M
