-- Turns diagnostics into messages.

local arena = require 'clavius.ir.arena'

local M = {}

--- Message templates by code. Each is filled in with the diagnostic's arguments in order.
--- @type table<string, string>
local TEMPLATES = {
    ['E-internal-node'] = '%s where a %s belongs',
    ['E-internal-check'] = 'Check O%s has no obligation of a known kind',
    ['E-internal-assume'] = 'Assume A%s has no allowed justification',
}

--- Formats a diagnostic as `line:col: code: message`.
--- @param d Diag
--- @param spans Span[] belong to the arena that the node is in
--- @param text string file that the spans point into
--- @return string
function M.diag(d, spans, text)
    local span = d.span or spans[d.node]
    local line, col = arena.line_col(arena.line_starts(text), span.start)
    local template = assert(TEMPLATES[d.code], ('messages: no template for %s'):format(d.code))
    return ('%d:%d: %s: %s'):format(line, col, d.code, template:format(unpack(d.args)))
end

return M
