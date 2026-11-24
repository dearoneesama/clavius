-- The parse stage: Lua text to a source arena. Its root Block holds the file's statements and a ClvRegion
-- node for each `---@clavius begin` … `end` region, and a function's directives are nodes under it.

local arena = require 'clavius.ir.arena'
local luacheck = require 'clavius.syntax.luacheck'
local splice = require 'clavius.syntax.splice'

--- @class ParseResult
--- @field src SrcArena
--- @field root NodeId the root Block, or 0 when the text doesn't parse

local M = {}

-- How a file like this is parsed:
--
--   ---@clavius begin
--   ---@param n integer
--   ---@pre n > 0
--   local function f(n)
--       ---@assert n > 0
--       return n
--   end
--
--   ---@param m integer
--   ---@return integer
--   local function g(m) return m + 1 end
--   ---@clavius end
--
-- 1. luacheck's parser reads the whole text: an AST with two `Localrec` statements, and the short
--    comments with their offsets and lines. Directives and ghost code are only comments to it.
-- 2. `comments.directives` turns each `---@` comment into a Directive: its tag, its arguments and their
--    span, and the `---` lines below it that a type may continue onto.
-- 3. `splice.regions` pairs `begin` with `end` against the offsets of the top-level statements, before
--    any of them is converted: statements 1 and 2 form a region, so both are marked code.
-- 4. `comments.ghost_ranges` finds the comments that hold ghost code, and `comments.unmask` turns their
--    markers and tags into spaces, so the code sits at its own offsets. Spec and lemma blocks are
--    unmasked anywhere, and other ghost code only in marked code, which a first conversion of the text
--    as written finds. Steps 1 to 3 then run again on the unmasked text.
-- 5. The converter walks the statements. Before each one, `splice.take` hands it the directives above
--    it. The statements of each ghost comment become one ClvSpec, ClvLemma, ClvProof, ClvGhost,
--    ClvAssert or ClvAssume node, so the `---@assert` becomes `(ClvAssert (BinOp gt (Id n) (Literal number 0)))`.
-- 6. `splice.place` parses the directives above a function or loop in marked code with `directive.parse`.
--    Types become ClvType nodes through `typeexpr`. Lua code, such as the `n > 0`, is parsed by
--    `luacheck.expressions` as `return n > 0`, with spans moved to where it is in the file. So
--    `---@pre n > 0` becomes `(ClvPre (BinOp gt (Id n) (Literal number 0)))`.
-- 7. The function is converted after its directive nodes, and they become its `directives` field:
--    `(Function [(ClvParam n …) (ClvPre …)] [(Binder n)] false (Block …))`.
-- 8. `splice.run` wraps statements 1 and 2 in a ClvRegion under the root Block, and reports the
--    long-comment annotations that marked code may not have, such as `--[[@as T]]`.

--- Parses one file into a new arena. Returns the arena and every syntax and annotation error.
--- @param text string
--- @param file FileId
--- @return ParseResult
--- @return Diag[] diags
function M.run(text, file)
    local src = arena.new_src()
    local root, diags = M.append(src, text, file, false)
    return { src = src, root = root }, diags
end

--- Parses one file of a run into the run's arena, after the files already in it. Returns the file's root
--- Block, or 0 when the text doesn't parse, and every syntax and annotation error.
--- @param src SrcArena
--- @param text string
--- @param file FileId
--- @param meta boolean whether the file is a `---@meta` file
--- @mut src
--- @return NodeId root
--- @return Diag[] diags
function M.append(src, text, file, meta)
    local chunk, diags = luacheck.convert(src, text, file, meta)
    if not chunk then
        return 0, diags
    end
    local root, splice_diags = splice.run(src, chunk, arena.span(file, 1, #text))
    for _, d in ipairs(splice_diags) do
        diags[#diags + 1] = d
    end
    return root, diags
end

return M
