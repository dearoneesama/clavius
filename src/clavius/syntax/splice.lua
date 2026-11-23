-- Places annotations in the source tree while the converter builds it: the directives above a function
-- or a loop become its directive nodes, and the top-level statements between `---@clavius begin` and `end` become
-- regions. It reports misplaced directives, and the annotations in marked code that it doesn't place.

local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local diag = require 'clavius.ir.diag'
local directive = require 'clavius.syntax.directive'

--- A region found from its markers: the top-level statements `first` to `last`, and the span from its
--- `begin` to its `end`.
--- @class SpliceRegion
--- @field first integer
--- @field last integer
--- @field span Span

--- A span where the marking changes: a region, a spec or lemma block, or a function whose body is
--- marked differently from the code around it.
--- @class MarkedSpan
--- @field span Span
--- @field marked boolean

--- A file's directives, and how far the converter has taken them.
--- @class SpliceCursor
--- @field src SrcArena
--- @field text string
--- @field directives Directive[] in source order
--- @field next integer the first directive not taken yet
--- @field code_parser CodeParser
--- @field diags Diag[]
--- @field ghosts GhostRange[] the unmasked ghost comments

--- The directive nodes of a function or a loop, and whether a function's body is marked code.
--- @class Placement
--- @field directives NodeId[]
--- @field marked boolean

--- What a statement is to the directives above it: a function definition, a loop, or anything else.
--- @alias SpliceBelow 'function' | 'loop' | 'other'

local M = {}

-- tags that annotate only the function below them
local FUNCTION_TAGS = {
    clavius = true,
    unsafe = true,
    pre = true,
    post = true,
    param = true,
    ['return'] = true,
    mut = true,
    move = true,
    len = true,
    disjoint = true,
    entry = true,
    no_callback = true,
    may_raise = true,
    proof_by = true,
    reveal_with_fuel = true,
    rlimit = true,
    generic = true,
    overload = true,
    vararg = true,
}

-- tags that annotate the function below them when there is one, and otherwise something else
local MAYBE_FUNCTION_TAGS = { decrease = true, frozen = true, extern = true, closure_invariant = true }

-- tags that annotate the loop below them
local LOOP_TAGS = { invariant = true, decrease = true }

-- tags of ghost code, which is unmasked in marked code unless it is ghost code already
local GHOST_TAGS = { ghost = true, proof = true, assert = true }

-- the tags of the long comments that hold ghost code
local BLOCK_TAGS = { spec = true, lemma = true, proof = true }

--- Returns whether `d` is `---@clavius begin` or `end`.
--- @param d Directive
--- @return boolean
local function is_region_marker(d)
    return d.tag == 'clavius' and (d.args == 'begin' or d.args == 'end')
end

--- Returns whether `d` marks the function below it.
--- @param d Directive
--- @return boolean
local function is_function_mark(d)
    return (d.tag == 'clavius' and d.args == '') or d.tag == 'unsafe'
end

--- @param cur SpliceCursor
--- @param code DiagCode
--- @param d Directive
--- @param args string[]
--- @mut cur
local function report(cur, code, d, args)
    cur.diags[#cur.diags + 1] = diag.at_span(code, d.span, args)
end

--- Pairs the region markers. A marker must sit between top-level statements, and markers must pair up
--- without nesting. Reports `---@clavius` with other arguments too.
--- @param spans Span[] the top-level statements'
--- @param directives Directive[]
--- @param diags Diag[]
--- @mut diags
--- @return SpliceRegion[]
function M.regions(spans, directives, diags)
    local regions = {}
    --- @type Directive|nil
    local open = nil
    local first = 1 -- of the open region
    local before = 0 -- top-level statements that end before the current marker
    for _, d in ipairs(directives) do
        if d.tag == 'clavius' and d.args ~= '' and not is_region_marker(d) then
            diags[#diags + 1] = diag.at_span('E-syntax', d.span, { 'clavius-args' })
        elseif is_region_marker(d) then
            while before < #spans and spans[before + 1].finish < d.span.start do
                before = before + 1
            end
            if before < #spans and arena.contains(spans[before + 1], d.span.start) then
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

--- Returns whether `offset` is in marked code. The innermost span that holds it says so, and code that
--- none holds is unmarked.
--- @param marks MarkedSpan[] each after the spans that hold it
--- @param offset integer
--- @return boolean
function M.marked_at(marks, offset)
    local marked = false
    for _, m in ipairs(marks) do
        if arena.contains(m.span, offset) then
            marked = m.marked
        end
    end
    return marked
end

--- Returns whether the `i`-th top-level statement is in one of the regions.
--- @param regions SpliceRegion[]
--- @param i integer
--- @return boolean
function M.in_region(regions, i)
    for _, r in ipairs(regions) do
        if r.first <= i and i <= r.last then
            return true
        end
    end
    return false
end

--- Makes a cursor at the first of a file's directives.
--- @param src SrcArena
--- @param text string the file
--- @param directives Directive[]
--- @param code_parser CodeParser
--- @param diags Diag[] where the cursor reports
--- @param ghosts GhostRange[]
--- @return SpliceCursor
function M.cursor(src, text, directives, code_parser, diags, ghosts)
    return { src = src, text = text, directives = directives, next = 1, code_parser = code_parser, diags = diags, ghosts = ghosts }
end

--- Returns why a ghost line or block at `offset` was left a comment: `proof-in-spec` or `ghost-in-ghost`
--- when it sits inside another ghost comment, and `ghost-outside` when it sits outside marked code,
--- such as among the directives above a marked function.
--- @param ghosts GhostRange[]
--- @param offset integer
--- @return string
local function nested_ghost(ghosts, offset)
    local gr = comments.ghost_at(ghosts, offset)
    if gr == nil then
        return 'ghost-outside'
    end
    return gr.kind == 'spec' and 'proof-in-spec' or 'ghost-in-ghost'
end

--- Returns whether code precedes `d` on its line. LuaLS attaches such a directive to that code.
--- e.g. `local x = 1 ---@type integer` has type integer by LuaLS but Clavius does not support it (yet).
--- @param cur SpliceCursor
--- @param d Directive
--- @return boolean
local function after_code(cur, d)
    local i = d.span.start - 1
    while i >= 1 and cur.text:byte(i) ~= 10 do -- 10 = \n
        if not cur.text:sub(i, i):match '%s' then
            return true
        end
        i = i - 1
    end
    return false
end

--- Reports directives that sit above no statement. In marked code, every directive needs one; elsewhere
--- only the function marks do.
--- e.g. a `---@type` inside a table constructor, a `---@pre` after the last statement of a function's body,
--- or a `---@param` that a blank line separates from its function.
--- @param cur SpliceCursor
--- @param list Directive[]
--- @param marked boolean
--- @mut cur
local function dangling(cur, list, marked)
    for _, d in ipairs(list) do
        if is_function_mark(d) or (marked and directive.is_tag(d.tag)) then
            if after_code(cur, d) then
                report(cur, 'E-unsupported-directive', d, { d.tag })
            elseif GHOST_TAGS[d.tag] then
                report(cur, 'E-misplaced-directive', d, { nested_ghost(cur.ghosts, d.span.start) })
            else
                report(cur, 'E-misplaced-directive', d, { 'not-above-statement' })
            end
        end
    end
end

--- Takes the directives that end before `offset` and returns them. At the top level, a region marker
--- splits them: those before it are above no statement.
--- @param cur SpliceCursor
--- @param offset number
--- @param top boolean
--- @mut cur
--- @return Directive[]
local function take_all(cur, offset, top)
    local above = {}
    while cur.next <= #cur.directives and cur.directives[cur.next].span.finish < offset do
        local d = cur.directives[cur.next]
        cur.next = cur.next + 1
        -- `regions` has reported every `---@clavius` with arguments that is out of place
        if d.tag == 'clavius' and d.args ~= '' then
            if top and is_region_marker(d) then
                dangling(cur, above, d.args == 'end')
                above = {}
            end
        else
            above[#above + 1] = d
        end
    end
    return above
end

--- Takes the directives that end before `offset`, where a statement starts, and returns those above it.
--- As in LuaLS, a blank line between a directive and the statement leaves the directive above no
--- statement, and so does a region marker at the top level.
--- @param cur SpliceCursor
--- @param offset integer
--- @param top boolean
--- @param marked boolean whether the statement is marked code
--- @mut cur
--- @return Directive[]
function M.take(cur, offset, top, marked)
    local above = take_all(cur, offset, top)
    -- the first directive with only comment lines between it and the statement
    local first = #above + 1
    while first > 1 and not cur.text:sub(above[first - 1].span.finish + 1, offset - 1):find '\n[ \t\r]*\n' do
        first = first - 1
    end
    local apart, attached = {}, {}
    for i, d in ipairs(above) do
        if i < first then
            apart[#apart + 1] = d
        else
            attached[#attached + 1] = d
        end
    end
    dangling(cur, apart, marked)
    return attached
end

--- Takes the directives that start at or before `finish`, the end of a statement or a function body,
--- and reports them as above no statement.
--- e.g. in marked code
---
---     local t = { 1,
---         ---@type integer
---         2 }
---
--- no statement of its own takes the `---@type`, so dangling the end of the `local` reports it. The
--- converter also dangles the end of a function's parameter list, and the `end` of its body.
--- @param cur SpliceCursor
--- @param finish integer
--- @param marked boolean whether the code that holds them is marked
--- @mut cur
function M.dangle(cur, finish, marked)
    local list = {}
    while cur.next <= #cur.directives and cur.directives[cur.next].span.start <= finish do
        local d = cur.directives[cur.next]
        cur.next = cur.next + 1
        if not (d.tag == 'clavius' and d.args ~= '') then
            list[#list + 1] = d
        end
    end
    dangling(cur, list, marked)
end

--- Takes the directives after the last top-level statement and reports them.
--- @param cur SpliceCursor
--- @mut cur
function M.finish(cur)
    dangling(cur, take_all(cur, math.huge, true), false)
end

--- Places the directives above a statement and returns the nodes for the function it defines or the
--- loop it is.
---
--- Marked code is the statements of regions and the bodies of functions marked `---@clavius`. There, and
--- above a function marked `---@clavius` or `---@unsafe`, directives become nodes. Elsewhere only those
--- two marks are read, since the other annotations there are LuaLS's.
--- @param cur SpliceCursor
--- @param above Directive[]
--- @param below SpliceBelow
--- @param marked boolean whether the statement is marked code
--- @mut cur
--- @return Placement
function M.place(cur, above, below, marked)
    local has_function = below == 'function'
    local marker, unsafe = false, false
    for _, d in ipairs(above) do
        marker = marker or d.tag == 'clavius'
        unsafe = unsafe or d.tag == 'unsafe'
    end
    local active = marked or (has_function and (marker or unsafe))
    local ids = {}
    -- a tag that Clavius doesn't read is ignored wherever it sits
    local known = {}
    for _, d in ipairs(above) do
        if directive.is_tag(d.tag) then
            known[#known + 1] = d
        end
    end
    for _, d in ipairs(known) do
        local tag = d.tag
        -- whether the tag annotates the statement below
        local fits = (has_function and (FUNCTION_TAGS[tag] or MAYBE_FUNCTION_TAGS[tag])) or (below == 'loop' and LOOP_TAGS[tag])
        if (active or is_function_mark(d)) and after_code(cur, d) then
            report(cur, 'E-unsupported-directive', d, { tag })
        elseif is_function_mark(d) and not has_function then
            report(cur, 'E-misplaced-directive', d, { 'no-function-below' })
        elseif active and GHOST_TAGS[tag] then
            report(cur, 'E-misplaced-directive', d, { nested_ghost(cur.ghosts, d.span.start) })
        elseif active and fits then
            local nodes, diags = directive.parse(cur.src, d, cur.code_parser)
            for _, id in ipairs(nodes) do
                ids[#ids + 1] = id
            end
            for _, e in ipairs(diags) do
                cur.diags[#cur.diags + 1] = e
            end
        elseif active and FUNCTION_TAGS[tag] then
            report(cur, 'E-misplaced-directive', d, { 'no-function-below' })
        elseif active and LOOP_TAGS[tag] then
            report(cur, 'E-misplaced-directive', d, { 'no-loop-below' })
        elseif active then
            report(cur, 'E-unsupported-directive', d, { tag })
        end
    end
    -- an `---@unsafe` function's body is never marked code
    return { directives = ids, marked = marker or (marked and not unsafe) }
end

--- Builds the root Block over the top-level statements and the ClvRegion node of each region. Returns
--- the root and what it reports about the long-comment annotations that are still comments: a ghost
--- block inside ghost code, and in marked code LuaLS directives such as `--[[@as T]]`.
--- @param src SrcArena
--- @param chunk Chunk
--- @param root_span Span the whole file
--- @mut src
--- @return NodeId root
--- @return Diag[] diags
function M.run(src, chunk, root_span)
    local diags = {}
    for _, a in ipairs(chunk.annotations) do
        if BLOCK_TAGS[a.tag] and comments.ghost_at(chunk.ghosts, a.span.start) then
            diags[#diags + 1] = diag.at_span('E-misplaced-directive', a.span, { nested_ghost(chunk.ghosts, a.span.start) })
        elseif not BLOCK_TAGS[a.tag] and M.marked_at(chunk.marks, a.span.start) then
            diags[#diags + 1] = diag.at_span('E-unsupported-directive', a.span, { a.tag })
        end
    end

    local statements = chunk.statements
    local top = {}
    local i = 1
    for _, r in ipairs(chunk.regions) do
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
