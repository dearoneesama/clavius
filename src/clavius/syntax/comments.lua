-- Annotations in comments: `---@tag args` directives from short comments, and long comments that
-- start with a tag, such as `--[[@spec` blocks.

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

local arena = require 'clavius.ir.arena'

local M = {}

-- the text follows the comment's `--`, so `---@tag` arrives as `-@tag`; LuaLS allows any spaces before `@`
local HEAD = '^%-%s*@'

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

return M
