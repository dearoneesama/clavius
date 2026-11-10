-- Diagnostic records: a code, a primary node, arguments and related nodes, but no message text.

--- The part of a code after `E-` names its family: `syntax`, `misplaced` (an annotation in the wrong
--- place), `unsupported` (a feature Clavius doesn't verify), `banned` (a feature verified code must not
--- use) or `internal` (a bug in Clavius).
--- @alias DiagCode
--- | 'E-syntax'
--- | 'E-misplaced-directive'
--- | 'E-unsupported-kind'
--- | 'E-unsupported-type'
--- | 'E-unsupported-directive'
--- | 'E-unsupported-call'
--- | 'E-banned-global'
--- | 'E-banned-goto'
--- | 'E-banned-call'
--- | 'E-internal'

--- @class Diag
--- @field code DiagCode
--- @field node NodeId primary node, or 0 when there is none (syntax errors)
--- @field span Span|nil the location of a diagnostic with no node
--- @field args string[] message arguments, such as the unsupported name
--- @field related NodeId[] other nodes the message points at

local M = {}

--- Makes a diagnostic on a node.
--- @param code DiagCode
--- @param node NodeId
--- @param args string[]
--- @return Diag
function M.at_node(code, node, args)
    return { code = code, node = node, span = nil, args = args, related = {} }
end

--- Makes a diagnostic at a span, for errors found before any node exists. Its node is 0.
--- @param code DiagCode
--- @param span Span
--- @param args string[]
--- @return Diag
function M.at_span(code, span, args)
    return { code = code, node = 0, span = span, args = args, related = {} }
end

return M
