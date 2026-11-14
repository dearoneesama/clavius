-- The parse stage: Lua text to a source arena. Its root Block holds the file's statements and a ClvRegion
-- node for each `---@clavius begin` … `end` region.

local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local luacheck = require 'clavius.syntax.luacheck'
local splice = require 'clavius.syntax.splice'

--- @class ParseResult
--- @field src SrcArena
--- @field root NodeId the root Block, or 0 when the text doesn't parse

local M = {}

--- Parses one file. Returns the arena and every syntax and annotation error.
--- @param text string
--- @param file FileId
--- @return ParseResult
--- @return Diag[] diags
function M.run(text, file)
    local src = arena.new_src()
    local chunk, diags = luacheck.convert(src, text, file)
    if not chunk then
        return { src = src, root = 0 }, diags
    end
    local directives = comments.directives(chunk.comments)
    local blocks = comments.blocks(chunk.long_comments)
    local root, splice_diags = splice.run(src, chunk.statements, directives, blocks, arena.span(file, 1, #text))
    for _, d in ipairs(splice_diags) do
        diags[#diags + 1] = d
    end
    return { src = src, root = root }, diags
end

return M
