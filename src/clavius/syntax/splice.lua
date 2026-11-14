-- Places annotations in the source tree. It groups the top-level statements between `---@clavius begin`
-- and `---@clavius end` into ClvRegion nodes under the root Block. It reports misplaced markers, and the
-- annotations in regions that Clavius doesn't verify.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'

--- A region found from its markers: the top-level statements `first` to `last`, and the span from its
--- `begin` to its `end`.
--- @class SpliceRegion
--- @field first integer
--- @field last integer
--- @field span Span

local M = {}

--- Returns whether `offset` lies within `s`.
--- @param s Span
--- @param offset integer
--- @return boolean
local function contains(s, offset)
    return s.start <= offset and offset <= s.finish
end

--- Pairs the region markers. A marker must sit between top-level statements, and markers must pair up
--- without nesting.
--- @param src SrcArena
--- @param statements NodeId[]
--- @param directives Directive[]
--- @param diags Diag[]
--- @mut diags
--- @return SpliceRegion[]
local function find_regions(src, statements, directives, diags)
    local regions = {}
    --- @type Directive|nil
    local open = nil
    local first = 1 -- of the open region
    local before = 0 -- top-level statements that end before the current marker
    for _, d in ipairs(directives) do
        if d.tag == 'clavius' and d.args == '' then
            diags[#diags + 1] = diag.at_span('E-unsupported-feature', d.span, { 'function-marker' })
        elseif d.tag == 'clavius' and d.args ~= 'begin' and d.args ~= 'end' then
            diags[#diags + 1] = diag.at_span('E-syntax', d.span, { 'clavius-args' })
        elseif d.tag == 'clavius' then
            while before < #statements and src.spans[statements[before + 1]].finish < d.span.start do
                before = before + 1
            end
            local inside = before < #statements and contains(src.spans[statements[before + 1]], d.span.start)
            if inside then
                diags[#diags + 1] = diag.at_span('E-misplaced-directive', d.span, { 'marker-in-block' })
            elseif d.args == 'begin' and open then
                diags[#diags + 1] = diag.at_span('E-misplaced-directive', d.span, { 'nested-begin' })
            elseif d.args == 'begin' then
                open, first = d, before + 1
            elseif not open then
                diags[#diags + 1] = diag.at_span('E-misplaced-directive', d.span, { 'unpaired-end' })
            else
                local s = arena.span(d.span.file, open.span.start, d.span.finish)
                regions[#regions + 1] = { first = first, last = before, span = s }
                open = nil
            end
        end
    end
    if open then
        diags[#diags + 1] = diag.at_span('E-misplaced-directive', open.span, { 'unpaired-begin' })
    end
    return regions
end

--- Returns whether `offset` lies within one of the regions.
--- @param regions SpliceRegion[]
--- @param offset integer
--- @return boolean
local function in_region(regions, offset)
    for _, r in ipairs(regions) do
        if contains(r.span, offset) then
            return true
        end
    end
    return false
end

--- Builds the root Block over the top-level statements and the ClvRegion node of each region. Returns the
--- root and the diagnostics.
--- @param src SrcArena
--- @param statements NodeId[] the top-level statements
--- @param directives Directive[]
--- @param blocks AnnotationBlock[]
--- @param root_span Span the whole file
--- @mut src
--- @return NodeId root
--- @return Diag[] diags
function M.run(src, statements, directives, blocks, root_span)
    local diags = {}
    local regions = find_regions(src, statements, directives, diags)
    for _, d in ipairs(directives) do
        if d.tag ~= 'clavius' and in_region(regions, d.span.start) then
            diags[#diags + 1] = diag.at_span('E-unsupported-directive', d.span, { d.tag })
        end
    end
    -- spec functions and lemmas are checked wherever they sit
    for _, b in ipairs(blocks) do
        if b.kind ~= 'proof' or in_region(regions, b.span.start) then
            diags[#diags + 1] = diag.at_span('E-unsupported-feature', b.span, { b.kind .. '-block' })
        end
    end

    local top = {}
    local i = 1
    for _, r in ipairs(regions) do
        while i < r.first do
            top[#top + 1] = statements[i]
            i = i + 1
        end
        local body = {}
        for j = r.first, r.last do
            body[#body + 1] = statements[j]
        end
        top[#top + 1] = arena.add_src(src, { tag = 'ClvRegion', statements = body }, r.span)
        i = r.last + 1
    end
    while i <= #statements do
        top[#top + 1] = statements[i]
        i = i + 1
    end
    return arena.add_src(src, { tag = 'Block', statements = top }, root_span), diags
end

return M
