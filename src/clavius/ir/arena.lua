-- Node storage. An arena is a Seq of nodes plus a parallel Seq of spans. Node ids are indices
-- into both. Every node is added after its children, so a child's id is always smaller than its
-- parent's, and `for id = 1, #arena.nodes` visits children first.

local core_nodes = require 'clavius.ir.core_nodes'
local source_nodes = require 'clavius.ir.source_nodes'

--- An index into an arena.
--- @alias NodeId integer

--- An index into the run's file list.
--- @alias FileId integer

--- A byte range in one file. `start` and `finish` are 1-based and inclusive; an empty span has
--- `finish == start - 1`.
--- @class Span
--- @field file FileId
--- @field start integer
--- @field finish integer

--- The source arena: Lua nodes and Clavius source nodes. It is a tree.
--- @class SrcArena
--- @field nodes SrcNode[]
--- @field spans Span[]

--- The core arena. A node may be shared between parents, but children still have smaller ids.
--- @class CoreArena
--- @field nodes CoreNode[]
--- @field spans Span[]

local M = {}

--- Makes a span. Raises an error unless `start >= 1` and `finish >= start - 1`.
--- @param file FileId
--- @param start integer
--- @param finish integer
--- @return Span
function M.span(file, start, finish)
    assert(start >= 1 and finish >= start - 1, 'arena.span: bad range')
    return { file = file, start = start, finish = finish }
end

--- Makes an empty source arena.
--- @return SrcArena
function M.new_src()
    return { nodes = {}, spans = {} }
end

--- Makes an empty core arena.
--- @return CoreArena
function M.new_core()
    return { nodes = {}, spans = {} }
end

--- Adds a source node whose children are already in the arena and returns its id. Raises an error if
--- a child id isn't smaller than the new id.
--- @param a SrcArena
--- @param node SrcNode
--- @param span Span
--- @mut a
--- @return NodeId id
function M.add_src(a, node, span)
    local id = #a.nodes + 1
    for _, kid in ipairs(source_nodes.children(node)) do
        assert(kid >= 1 and kid < id, 'arena.add_src: child id must be smaller than the parent id')
    end
    a.nodes[id] = node
    a.spans[id] = span
    return id
end

--- Returns whether a source function has a directive of kind `tag`, such as `ClvUnsafe`.
--- @param a SrcArena
--- @param fn SrcFunction
--- @param tag SrcTag
--- @return boolean
function M.has_directive(a, fn, tag)
    for _, d in ipairs(fn.directives) do
        if a.nodes[d].tag == tag then
            return true
        end
    end
    return false
end

--- Adds a core node whose children are already in the arena and returns its id. Raises an error if a
--- child id isn't smaller than the new id.
--- @param a CoreArena
--- @param node CoreNode
--- @param span Span
--- @mut a
--- @return NodeId id
function M.add_core(a, node, span)
    local id = #a.nodes + 1
    for _, kid in ipairs(core_nodes.children(node)) do
        assert(kid >= 1 and kid < id, 'arena.add_core: child id must be smaller than the parent id')
    end
    a.nodes[id] = node
    a.spans[id] = span
    return id
end

--- Returns the offset of the first byte of each line of `text`.
--- @param text string
--- @return integer[] starts
function M.line_starts(text)
    local starts = { 1 }
    for i = 1, #text do
        if text:byte(i) == 10 then -- 10 = \n
            starts[#starts + 1] = i + 1
        end
    end
    return starts
end

--- Converts a byte offset of `text` to a 1-based line and column, using `line_starts(text)`. The column
--- counts only non-continuation bytes in UTF-8.
--- @param text string
--- @param starts integer[]
--- @param offset integer
--- @return integer line
--- @return integer col
function M.line_col(text, starts, offset)
    local lo, hi = 1, #starts
    -- the last line whose start is <= offset
    while lo < hi do
        local mid = lo + math.floor((hi - lo + 1) / 2) -- lo + hi + 1 could leave ±2^53
        if starts[mid] <= offset then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local col = 1
    for i = starts[lo], offset - 1 do
        local b = text:byte(i)
        if b < 0x80 or b >= 0xC0 then
            col = col + 1
        end
    end
    return lo, col
end

return M
