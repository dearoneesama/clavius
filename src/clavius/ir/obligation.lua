-- Obligation and assumption records. Each `Check` in the core names an obligation: what the check
-- proves and the source node it covers. Each `Assume` names an assumption: the fact's justification
-- and the source node it comes from.

--- What a check proves:
--- - `range`: an integer result stays within ±2^53;
--- - `assert`: an `assert` call holds;
--- - `unreachable`: the code never runs, as with `error`.
--- @alias ObligationKind 'range' | 'assert' | 'unreachable'

--- Why an assumption may be made:
--- - `type_fact`: a value of a declared type satisfies that type's predicate;
--- - `branch`: the condition of the branch being taken.
--- @alias Justification 'type_fact' | 'branch'

--- @class Obligation
--- @field kind ObligationKind
--- @field node NodeId the source node it covers

--- @class Assumption
--- @field kind Justification
--- @field node NodeId the source node it comes from

local M = {}

--- The obligation kinds as a set.
--- @type table<string, boolean>
M.OBLIGATION_KINDS = { range = true, assert = true, unreachable = true }

--- The justifications an `Assume` may have as a set.
--- @type table<string, boolean>
M.JUSTIFICATIONS = { type_fact = true, branch = true }

return M
