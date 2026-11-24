-- Annotations in comments: `---@tag args` directives from short comments, long comments that start
-- with a tag, such as `--[[@spec` blocks, and the ghost code in comments. Unmasking ghost code blanks
-- out its comment markers and tag, so it becomes code at its own offsets:
--
--   ---@ghost local seen = 0       becomes       local seen = 0
--   --[[@proof lemma(n) ]]         becomes       lemma(n)
--   ---@assert seen > 0            becomes       local _ = seen > 0

--- A directive such as `---@clavius begin`, or its LuaLS spelling `--- @clavius begin`.
--- @class Directive
--- @field tag string e.g. `clavius`
--- @field args string the text after the tag with surrounding spaces removed, e.g. `begin`
--- @field args_span Span where `args` is in the file
--- @field span Span the whole comment
--- @field next_lines Comment[] the `---` lines right below it that start no directive, e.g. `---| 'a'`

--- A long comment that starts with a tag: an annotation block such as `--[[@spec … ]]`, or a LuaLS
--- directive such as `--[[@as T]]`.
--- @class LongAnnotation
--- @field tag string
--- @field span Span the whole comment

--- What a ghost comment holds: a `--[[@spec`, `--[[@lemma`, `--[[@proof` or `--[[@ghost` block, or a
--- `---@proof`, `---@ghost` or `---@assert` line.
--- @alias GhostKind 'spec' | 'lemma' | 'proof' | 'ghost_block' | 'proof_line' | 'ghost' | 'assert' | 'assume'

--- A comment that holds ghost code. Its code lies between `head` and `close`.
--- @class GhostRange
--- @field kind GhostKind
--- @field span Span the whole comment
--- @field head integer the last offset of the comment's opening and tag
--- @field close integer the first offset of a block's closing bracket, or `span.finish + 1` for a line

local arena = require 'clavius.ir.arena'

local M = {}

-- the text follows the comment's `--`, so `---@tag` arrives as `-@tag`; LuaLS allows any spaces before `@`
local HEAD = '^%-%s*@'

--- @type table<string, GhostKind>
local BLOCK_KINDS = { spec = 'spec', lemma = 'lemma', proof = 'proof', ghost = 'ghost_block' }

--- @type table<string, GhostKind>
local LINE_KINDS = { ghost = 'ghost', proof = 'proof_line', assert = 'assert', assume = 'assume' }

-- an `---@assert E` or `---@assume E` line becomes this statement, which is no wider than its opening and tag
local ASSERT = 'local _ ='

--- Returns the directives among short comments in their order.
--- @param comments Comment[]
--- @return Directive[]
function M.directives(comments)
    local out = {}
    for i, c in ipairs(comments) do
        local tag, after = c.text:match(HEAD .. '([%a_][%w_]*)()')
        if tag then
            local lead, args = c.text:match('^(%s*)(.-)%s*$', after)
            -- text index k is at file offset span.start + 1 + k
            local start = c.span.start + 1 + after + #lead
            local next_lines = {}
            local j = i + 1
            while
                j <= #comments
                and comments[j].line == comments[j - 1].line + 1
                and comments[j].text:sub(1, 1) == '-'
                and not comments[j].text:find(HEAD)
            do
                next_lines[#next_lines + 1] = comments[j]
                j = j + 1
            end
            out[#out + 1] = {
                tag = tag,
                args = args,
                args_span = arena.span(c.span.file, start, start + #args - 1),
                span = c.span,
                next_lines = next_lines,
            }
        end
    end
    return out
end

--- Returns the long comments that start with a tag, in their order. As in LuaLS, spaces may come
--- before the `@`.
--- @param long_comments Comment[]
--- @return LongAnnotation[]
function M.annotations(long_comments)
    local out = {}
    for _, c in ipairs(long_comments) do
        local tag = c.text:match '^%s*@([%a_][%w_]*)'
        if tag then
            out[#out + 1] = { tag = tag, span = c.span }
        end
    end
    return out
end

--- Returns the comments of `text` that hold ghost code, in source order. A line counts only when no code
--- comes before it on its line.
--- @param short Comment[]
--- @param long Comment[]
--- @param text string
--- @return GhostRange[]
function M.ghost_ranges(short, long, text)
    local out = {}
    for _, c in ipairs(long) do
        local lead, tag = c.text:match '^(%s*)@([%a_][%w_]*)'
        local kind = tag and BLOCK_KINDS[tag]
        if kind then
            local level = #text:match('^%-%-%[(=*)%[', c.span.start)
            -- `--[`, the `=`s and `[` come before the text, and the `@` is one byte before the tag
            local head = c.span.start + 3 + level + #lead + 1 + #tag
            out[#out + 1] = { kind = kind, span = c.span, head = head, close = c.span.finish - level - 1 }
        end
    end
    for _, c in ipairs(short) do
        local prefix, tag = c.text:match '^(%-%s*@)([%a_][%w_]*)'
        local kind = tag and LINE_KINDS[tag]
        -- the start of its line, unless code comes first
        local i = c.span.start - 1
        while i >= 1 and text:byte(i) ~= 10 and text:sub(i, i):match '%s' do -- 10 = \n
            i = i - 1
        end
        if kind and (i < 1 or text:byte(i) == 10) then
            -- the text starts after `--`
            local head = c.span.start + 1 + #prefix + #tag
            out[#out + 1] = { kind = kind, span = c.span, head = head, close = c.span.finish + 1 }
        end
    end
    --- @param a GhostRange
    --- @param b GhostRange
    --- @return boolean
    local function before_range(a, b)
        return a.span.start < b.span.start
    end
    table.sort(out, before_range)
    return out
end

--- Returns the ghost comment that holds `offset`, if any.
--- @param ranges GhostRange[]
--- @param offset integer
--- @return GhostRange|nil
function M.ghost_at(ranges, offset)
    for _, gr in ipairs(ranges) do
        if arena.contains(gr.span, offset) then
            return gr
        end
    end
    return nil
end

--- Returns `text` with the comment markers and tags of `ranges` blanked out, and each `---@assert E` and
--- `---@assume E` line turned into the statement `local _ = E`. Every offset stays where it was.
--- @param text string
--- @param ranges GhostRange[] in source order
--- @return string
function M.unmask(text, ranges)
    local parts = {}
    local at = 1
    for _, gr in ipairs(ranges) do
        local width = gr.head - gr.span.start + 1
        parts[#parts + 1] = text:sub(at, gr.span.start - 1)
        if gr.kind == 'assert' or gr.kind == 'assume' then
            parts[#parts + 1] = (' '):rep(width - #ASSERT) .. ASSERT
        else
            parts[#parts + 1] = (' '):rep(width)
        end
        parts[#parts + 1] = text:sub(gr.head + 1, gr.close - 1)
        parts[#parts + 1] = (' '):rep(gr.span.finish - gr.close + 1)
        at = gr.span.finish + 1
    end
    parts[#parts + 1] = text:sub(at)
    return table.concat(parts)
end

return M
