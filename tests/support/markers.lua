-- Expected results written into Lua test sources as `--!` comments. Each name after `--!` is a
-- diagnostic code or an obligation kind expected on that line. A marker alone on its line is for the
-- line above. A directive is itself a comment, so that is how it gets one:
--
--   local x = y + 1 --! E-banned-global
--   ---@clavius end
--   --! E-misplaced-directive

local arena = require 'clavius.ir.arena'
local driver = require 'clavius.driver'
local luassert = require 'luassert'
local stringx = require 'pl.stringx'

--- A diagnostic code or obligation kind on a line.
--- @class Marker
--- @field line integer
--- @field name string

local M = {}

--- @param list Marker[]
--- @return Marker[]
local function sorted(list)
    --- @param a Marker
    --- @param b Marker
    --- @return boolean
    local function before(a, b)
        if a.line ~= b.line then
            return a.line < b.line
        end
        return a.name < b.name
    end
    table.sort(list, before)
    return list
end

--- @param text string
--- @param offset integer
--- @return integer
local function line_of(text, offset)
    return (arena.line_col(text, arena.line_starts(text), offset))
end

--- Returns the markers in `text` ordered by line and name.
--- @param text string
--- @return Marker[]
function M.read(text)
    local out = {}
    local line = 0
    for l in (text .. '\n'):gmatch '([^\n]*)\n' do
        line = line + 1
        local code, names = l:match '^(.-)%-%-!%s*(.-)%s*$'
        local target = (code and code:match '^%s*$') and line - 1 or line
        for name in (names or ''):gmatch '%S+' do
            out[#out + 1] = { line = target, name = name }
        end
    end
    return sorted(out)
end

--- Returns the diagnostics in a compiler context as markers.
--- @param c CompilerContext
--- @return Marker[]
function M.diags(c)
    local out = {}
    for i, d in ipairs(c.diags) do
        local span = d.span or c.spans[d.node]
        out[i] = { line = line_of(c.text, span.start), name = d.code }
    end
    return sorted(out)
end

--- Dedents an indented Lua source, runs the stages up to `stage` on it, and checks that the diagnostics
--- are exactly those its markers name. Returns the compiler context.
--- @param stage string
--- @param source string
--- @return CompilerContext
function M.expect_diags(stage, source)
    local text = stringx.dedent(source)
    local c = driver.run_until(stage, text, 1)
    luassert.are.same(M.read(text), M.diags(c))
    return c
end

return M
