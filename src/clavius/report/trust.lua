-- The trust report: what a run assumed rather than proved, with where each assumption comes from. For
-- example:
--
--   Trust report: prog.lua
--
--     @unsafe functions
--       bump      prog.lua:8
--
--     @extern functions
--       host.log  game.meta.lua:12  @no_callback
--
--     callers outside verification
--       inc       prog.lua:15
--
--     stdlib specs (clavius dev)
--       math.min  clavius/meta/math.lua:14
--
--     stdlib unchanged
--       nothing outside verification replaces a library function
-- means:
--
-- - `bump`, defined on line 8, is `---@unsafe`. Its body isn't verified, yet verified code that calls it
--   relies on its `---@post`s and its value's type.
-- - `host.log` is a host function that a `---@meta` file declares. Verified code relies on its contract
--   and its flags.
-- - `inc` is verified, assuming its parameters' types and its `---@pre`s on entry. A verified caller
--   proves those at each call, but a caller in unmarked code doesn't, so they are trusted to hold there.
-- - `math.min`'s shipped spec is trusted, as written by the Clavius version named.
-- - Verified code that calls a library function, `math.floor(a / b)` included, relies on nothing outside
--   verification replacing it, as `math.min = f` would.

local arena = require 'clavius.ir.arena'
local clavius = require 'clavius'
local support = require 'clavius.ir.support'

local M = {}

--- A function in the report, with where it is defined and the flags it is trusted for.
--- @class TrustEntry
--- @field name string
--- @field file string
--- @field line integer
--- @field flags string

--- Adds a section to `out`: a blank line, its heading indented by 2, and an entry per line indented by
--- 4, with the names padded to `width` so the locations line up.
--- @param out string[]
--- @param heading string
--- @param entries TrustEntry[]
--- @param width integer
--- @mut out
local function section(out, heading, entries, width)
    if #entries == 0 then
        return
    end
    out[#out + 1] = ''
    out[#out + 1] = ('  %s'):format(heading)
    for _, e in ipairs(entries) do
        local line = ('    %s%s  %s:%d'):format(e.name, (' '):rep(width - #e.name), e.file, e.line)
        if e.flags ~= '' then
            line = ('%s  %s'):format(line, e.flags)
        end
        out[#out + 1] = line
    end
end

--- Returns the name that a trusted Function is called by: the name of the local that a `local function f`
--- or, after `local f`, a `function f` defines, or the name that a `---@meta` file declares it under, such
--- as `math.min`.
--- @param src SrcArena
--- @param index NodeIndex
--- @param id NodeId
--- @return string
local function name_of(src, index, id)
    local def = src.nodes[index.parent[id]]
    if def.tag == 'LocalFunction' then
        return (src.nodes[def.binder] --[[@as SrcBinder]]).name
    end
    -- `function f(…) end` after `local f`, or `function a.b(…) end` in a `---@meta` file
    local set = def --[[@as SrcSet]]
    local _, path = support.global_path(src, set.targets[1])
    return assert(path)
end

--- Returns the trust report of a run as lines, or no lines when it trusted nothing. The trusted
--- assumptions name their Functions: a trusted one, whose contract its callers rely on, or a verified
--- one, whose callers outside verification are trusted to meet its boundary assumptions.
--- @param prog CoreProgram
--- @param src SrcArena
--- @param index NodeIndex
--- @param files table<FileId, SourceFile> every file of the run
--- @param main FileId the Lua file that was verified
--- @return string[]
function M.report(prog, src, index, files, main)
    -- `math.floor(a / b)` outside contracts relies on `math.floor`, and only there does its Call have a
    -- `div_zero` check
    local floor_idiom = false
    for _, o in ipairs(prog.obligations) do
        if o.kind == 'div_zero' and src.nodes[o.node].tag == 'Call' then
            floor_idiom = true
        end
    end
    local seen, fns = {}, {}
    for _, a in ipairs(prog.assumptions) do
        if a.kind == 'trusted' and a.decl ~= nil and not seen[a.decl] then
            seen[a.decl] = true
            fns[#fns + 1] = a.decl
        end
    end
    if #fns == 0 and not floor_idiom then
        return {}
    end

    --- @param a NodeId
    --- @param b NodeId
    --- @return boolean
    local function before(a, b)
        local sa = src.spans[a]
        local sb = src.spans[b]
        if sa.file ~= sb.file then
            return sa.file < sb.file
        end
        return sa.start < sb.start
    end

    table.sort(fns, before)
    local starts = {}
    --- @type TrustEntry[]
    local unsafe = {}
    --- @type TrustEntry[]
    local externs = {}
    --- @type TrustEntry[]
    local callers = {}
    --- @type TrustEntry[]
    local stdlib = {}
    -- the longest name, so the locations line up across the sections
    local width = 0
    for _, id in ipairs(fns) do
        local def_span = src.spans[index.parent[id]]
        local f = files[def_span.file]
        starts[def_span.file] = starts[def_span.file] or arena.line_starts(f.text)
        local fn = src.nodes[id] --[[@as SrcFunction]]
        local flags = {}
        for _, d in ipairs(fn.directives) do
            local tag = src.nodes[d].tag
            if support.TRUST_FLAGS[tag] then
                flags[#flags + 1] = '@' .. support.DIRECTIVE_TAGS[tag]
            end
        end
        local entry = {
            name = name_of(src, index, id),
            file = f.name,
            line = (arena.line_col(f.text, starts[def_span.file], def_span.start)),
            flags = table.concat(flags, ' '),
        }
        if f.kind == 'stdlib' then
            stdlib[#stdlib + 1] = entry
        elseif f.kind == 'extern' then
            externs[#externs + 1] = entry
        elseif arena.has_directive(src, fn, 'ClvUnsafe') then
            unsafe[#unsafe + 1] = entry
        else
            callers[#callers + 1] = entry
        end
        width = math.max(width, #entry.name)
    end
    local out = { ('Trust report: %s'):format(files[main].name) }
    section(out, '@unsafe functions', unsafe, width)
    section(out, '@extern functions', externs, width)
    section(out, 'callers outside verification', callers, width)
    section(out, ('stdlib specs (clavius %s)'):format(clavius.VERSION), stdlib, width)
    if #stdlib > 0 or floor_idiom then
        out[#out + 1] = ''
        out[#out + 1] = '  stdlib unchanged'
        out[#out + 1] = '    nothing outside verification replaces a library function'
    end
    return out
end

return M
