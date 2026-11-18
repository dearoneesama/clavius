-- The effects pass: what each loop in marked code writes. A loop's encoding havocs exactly these places
-- at its head, and keeps every fact about the others.
--
--   local x, z = 0, 0
--   while a do          -- writes x
--       local y = 0
--       while b do      -- writes x and y
--           if c then
--               x = 1
--           end
--           y = 2
--       end
--   end
--
-- Neither loop writes z. The outer loop doesn't write y either, since each of its iterations declares
-- a fresh one.

--- A place that code writes: a local.
--- @class Write
--- @field root NodeId the Binder of the local

--- @class Effects
--- @field writes table<NodeId, Write[]> what each loop in marked code writes of the locals declared outside it, by first write

local M = {}

-- the loops that marked code may have
local LOOPS = { While = true, Repeat = true, Fornum = true }

--- Returns the nodes from `id` up to the root, as a set.
--- @param idx NodeIndex
--- @param id NodeId
--- @return table<NodeId, boolean>
local function ancestors(idx, id)
    local out = {}
    local p = id
    while p ~= 0 do
        out[p] = true
        p = idx.parent[p]
    end
    return out
end

--- Records `root` as a write of each loop around the assignment `id` that `root` is declared outside of.
--- One declared inside a loop starts afresh in each iteration.
--- @param src SrcArena
--- @param idx NodeIndex
--- @param id NodeId the assignment
--- @param root NodeId the Binder of the local it assigns
--- @param out Effects
--- @param seen table<NodeId, table<NodeId, boolean>> loop -> root -> already recorded
--- @mut out
--- @mut seen
local function record(src, idx, id, root, out, seen)
    local around = ancestors(idx, root)
    -- p: start from the assignment's parent and walk outwards
    local p = idx.parent[id]
    while p ~= 0 and not around[p] do
        -- not around[p] = loop p is not around the local's original declaration => loop writes to it
        if LOOPS[src.nodes[p].tag] then
            seen[p] = seen[p] or {}
            out.writes[p] = out.writes[p] or {}
            if not seen[p][root] then
                seen[p][root] = true
                out.writes[p][#out.writes[p] + 1] = { root = root }
            end
        end
        p = idx.parent[p]
    end
end

--- Finds the places that the loops in marked code write.
--- @param src SrcArena
--- @param res Resolution
--- @param idx NodeIndex
--- @return Effects
function M.run(src, res, idx)
    --- @type Effects
    local out = { writes = {} }
    --- @type table<NodeId, table<NodeId, boolean>>
    local seen = {}
    for _, id in ipairs(idx.by_tag.Set or {}) do
        local n = src.nodes[id] --[[@as SrcSet]]
        for _, t in ipairs(n.targets) do
            -- the Binder that local was declared by; nil for a global
            local root = res.decl[t]
            if idx.unit[id] ~= 0 and root ~= nil then
                record(src, idx, id, root, out, seen)
            end
        end
    end
    return out
end

return M
