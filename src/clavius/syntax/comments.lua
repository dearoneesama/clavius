-- Clavius annotations in comments: `---@tag args` directives from short comments, and `--[[@spec`,
-- `--[[@lemma` and `--[[@proof` blocks from long comments.

--- A directive such as `---@clavius begin`, or its LuaLS spelling `--- @clavius begin`.
--- @class Directive
--- @field tag string e.g. `clavius`
--- @field args string the text after the tag with surrounding spaces removed, e.g. `begin`
--- @field span Span the whole comment

--- An annotation block such as `--[[@spec … ]]`.
--- @class AnnotationBlock
--- @field kind 'spec' | 'lemma' | 'proof'
--- @field span Span the whole comment

local M = {}

local BLOCK_KINDS = { spec = true, lemma = true, proof = true }

--- Returns the directives among short comments in their order.
--- @param comments Comment[]
--- @return Directive[]
function M.directives(comments)
    local out = {}
    for _, c in ipairs(comments) do
        -- the text follows the comment's `--`, so `---@tag` arrives as `-@tag`
        local tag, args = c.text:match '^%- ?@([%a_][%w_]*)(.*)$'
        if tag then
            out[#out + 1] = { tag = tag, args = args:match '^%s*(.-)%s*$', span = c.span }
        end
    end
    return out
end

--- Returns the annotation blocks among long comments in their order.
--- @param long_comments Comment[]
--- @return AnnotationBlock[]
function M.blocks(long_comments)
    local out = {}
    for _, c in ipairs(long_comments) do
        local kind = c.text:match '^@([%a_][%w_]*)'
        if kind and BLOCK_KINDS[kind] then
            out[#out + 1] = { kind = kind, span = c.span }
        end
    end
    return out
end

return M
