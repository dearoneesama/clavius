-- Diagnostic records: a code, a primary node, arguments and related nodes, but no message text.

--- The part of a code after `E-` names its family: `syntax`, `misplaced` (an annotation in the wrong
--- place), `unsupported` (a feature Clavius doesn't verify), `banned` (a feature verified code must not
--- use) or `internal` (a bug in Clavius).
--- @alias DiagCode
--- | 'E-syntax' # the file doesn't parse
--- | 'E-misplaced-directive' # a directive where it can't apply, such as a `---@require` with no function below it
--- | 'E-unsupported-kind' # a node kind or operator that Clavius doesn't verify
--- | 'E-unsupported-type' # a type that Clavius doesn't verify
--- | 'E-unsupported-directive' # a directive that Clavius doesn't verify
--- | 'E-unsupported-call' # a call to a library function that Clavius doesn't verify
--- | 'E-banned-global' # a global variable in verified code
--- | 'E-banned-goto' # a `goto` or label in verified code
--- | 'E-banned-call' # a call to a function that verified code must not use, such as `pcall`
--- | 'E-internal-node' # a node where its kind doesn't belong, such as a statement among terms
--- | 'E-internal-check' # a `Check` with no obligation of a known kind
--- | 'E-internal-assume' # an `Assume` with no allowed justification
--- | 'E-internal-exit' # an `Exit` that no `Block` with its label encloses
--- | 'E-internal-label' # a `Block` label that is already used in the unit

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
