-- Diagnostic records: a code, a primary node, arguments and related nodes, but no message text.

--- The part of a code after `E-` names its family: `syntax`, `misplaced` (an annotation in the wrong
--- place), `unsupported` (a feature Clavius doesn't verify), `banned` (a feature verified code must
--- not use), `type` (legal Lua that the type rules reject), `mode` (code that does what its mode, exec
--- or ghost, rules out) or `internal` (a bug in Clavius).
--- @alias DiagCode
--- | 'E-syntax' # the file doesn't parse, or uses unsupported syntax
--- | 'E-misplaced-directive' # a directive where it can't apply, such as an unpaired `---@clavius end`
--- | 'E-unsupported-feature' # a node kind, operator or form that Clavius doesn't verify
--- | 'E-unsupported-type' # a type that Clavius doesn't verify
--- | 'E-unsupported-directive' # a directive that Clavius doesn't verify
--- | 'E-unsupported-call' # a library name that Clavius doesn't verify
--- | 'E-banned-global' # a global variable in verified code
--- | 'E-banned-goto' # a `goto` or label in verified code
--- | 'E-banned-call' # a library function that verified code must not use, such as `pcall`
--- | 'E-type-mismatch' # an operand or value of the wrong type, such as `1 + true`
--- | 'E-mode' # exec code that uses ghost code, or ghost code that does what proof code can't
--- | 'E-internal-node' # a core node where its kind doesn't belong, such as a statement among terms
--- | 'E-internal-check' # a `Check` with no obligation of a known kind
--- | 'E-internal-assume' # an `Assume` with no allowed justification
--- | 'E-internal-exit' # an `Exit` that no `Block` with its label encloses
--- | 'E-internal-label' # a `Block` label that is already used in the unit
--- | 'E-internal-back-edge' # a `back_edge` `Assume` with statements after it in its list
--- | 'E-internal-coverage' # a source node with no obligation for a check it needs

--- @class Diag
--- @field code DiagCode
--- @field node NodeId primary node, or 0 when there is none
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
