-- The trust report: what a run assumed rather than proved, with where each assumption comes from. For
-- example:
--
--   Trust report: prog.lua
--
--     @unsafe functions
--       bump  prog.lua:8
--
--     callers outside verification
--       inc   prog.lua:15
--       max   prog.lua:22
--
--     assumptions
--       n > 0  prog.lua:30
-- means:
--
-- - `bump`, defined on line 8, is `---@unsafe`. Its body isn't verified, yet verified code that calls it
--   relies on its `---@post`s and its value's type.
-- - `inc` and `max` are verified, assuming their parameters' types and their `---@pre`s on entry. A
--   verified caller proves those at each call, but a caller in unmarked code doesn't, so they are trusted
--   to hold there.
-- - the `---@assume n > 0` on line 30 is a fact that nothing proves.

local arena = require 'clavius.ir.arena'

local M = {}

--- A function in the report, with the line of its `local function`, or an assumption's condition.
--- @class TrustEntry
--- @field name string
--- @field line integer

--- Adds a section to `out`: a blank line, its heading indented by 2, and an entry per line indented by
--- 4, with the names padded to `width` so the locations line up.
--- @param out string[]
--- @param heading string
--- @param entries TrustEntry[]
--- @param width integer
--- @param file string
--- @mut out
local function section(out, heading, entries, width, file)
    if #entries == 0 then
        return
    end
    out[#out + 1] = ''
    out[#out + 1] = ('  %s'):format(heading)
    for _, e in ipairs(entries) do
        out[#out + 1] = ('    %s%s  %s:%d'):format(e.name, (' '):rep(width - #e.name), file, e.line)
    end
end

--- Returns the trust report of a run as lines, or no lines when it trusted nothing. The trusted
--- assumptions name their Functions: an `---@unsafe` one, whose contract its callers rely on, or a
--- verified one, whose callers outside verification are trusted to meet its boundary assumptions. The
--- assumed ones are `---@assume` lines and `assume` calls, each listed by its condition.
--- @param prog CoreProgram
--- @param src SrcArena
--- @param index NodeIndex
--- @param text string
--- @param file string the file's name as the report shows it
--- @return string[]
function M.report(prog, src, index, text, file)
    local seen, fns, assumes = {}, {}, {}
    for _, a in ipairs(prog.assumptions) do
        if a.kind == 'trusted' and a.decl ~= nil and not seen[a.decl] then
            seen[a.decl] = true
            fns[#fns + 1] = a.decl
        elseif a.kind == 'assumed' and not seen[a.node] then
            seen[a.node] = true
            assumes[#assumes + 1] = a.node
        end
    end
    if #fns == 0 and #assumes == 0 then
        return {}
    end

    --- @param a NodeId
    --- @param b NodeId
    --- @return boolean
    local function before(a, b)
        return src.spans[a].start < src.spans[b].start
    end

    table.sort(fns, before)
    table.sort(assumes, before)
    local starts = arena.line_starts(text)
    --- @type TrustEntry[]
    local unsafe = {}
    --- @type TrustEntry[]
    local callers = {}
    -- the longest name, so the locations line up across both sections
    local width = 0
    for _, id in ipairs(fns) do
        -- every trusted Function is defined by a `local function f`,
        -- or, after `local f`, a `function f`
        local def = src.nodes[index.parent[id]] --[[@as SrcLocalFunction|SrcSet]]
        local named = def.tag == 'Set' and def.targets[1] or def.binder
        local name = (src.nodes[named] --[[@as SrcBinder|SrcId]]).name
        local fn = src.nodes[id] --[[@as SrcFunction]]
        local entry = { name = name, line = arena.line_col(text, starts, src.spans[index.parent[id]].start) }
        if arena.has_directive(src, fn, 'ClvUnsafe') then
            unsafe[#unsafe + 1] = entry
        else
            callers[#callers + 1] = entry
        end
        width = math.max(width, #name)
    end
    --- @type TrustEntry[]
    local assumed = {}
    for _, id in ipairs(assumes) do
        -- an `---@assume` line, or an `assume` call in proof code
        local n = src.nodes[id] --[[@as SrcClvAssume|SrcCall]]
        local cond = src.spans[n.tag == 'Call' and n.args[1] or n.cond]
        local name = (text:sub(cond.start, cond.finish):gsub('%s+', ' '))
        assumed[#assumed + 1] = { name = name, line = arena.line_col(text, starts, src.spans[id].start) }
        width = math.max(width, #name)
    end
    local out = { ('Trust report: %s'):format(file) }
    section(out, '@unsafe functions', unsafe, width, file)
    section(out, 'callers outside verification', callers, width, file)
    section(out, 'assumptions', assumed, width, file)
    return out
end

return M
