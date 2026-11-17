-- Obligation and assumption records. Each `Check` in the core names an obligation: what the check
-- proves and the source node it covers. Each `Assume` names an assumption: the fact's justification
-- and the source node it comes from.

--- What a check proves:
--- - `range`: an integer result stays within ±2^53;
--- - `assert`: an `assert` call holds;
--- - `unreachable`: the code never runs, as with `error`;
--- - `pre`: a call meets one of the callee's `---@pre`s;
--- - `post`: a function's value and parameters meet one of its `---@post`s where it returns;
--- - `missing_return`: a function with a `---@return` never reaches the end of its body.
--- @alias ObligationKind 'range' | 'assert' | 'unreachable' | 'pre' | 'post' | 'missing_return'

--- Why an assumption may be made:
--- - `type_fact`: a value of a declared type satisfies that type's predicate;
--- - `branch`: the condition of the branch being taken;
--- - `callee_post`: a verified callee's `---@post`, proved where the callee returns;
--- - `trusted`: a fact that nothing proves, which the trust report lists: what an `---@unsafe` callee
---   promises, and what a verified function assumes on entry about callers outside verification.
--- @alias Justification 'type_fact' | 'branch' | 'callee_post' | 'trusted'

--- @class Obligation
--- @field kind ObligationKind
--- @field node NodeId the source node it covers
--- @field clause NodeId|nil the ClvPre or ClvPost it is for

--- @class Assumption
--- @field kind Justification
--- @field node NodeId the source node it comes from
--- @field decl NodeId|nil for a trusted one, the Function whose contract or callers it trusts

local M = {}

--- The obligation kinds as a set.
--- @type table<string, boolean>
M.OBLIGATION_KINDS = { range = true, assert = true, unreachable = true, pre = true, post = true, missing_return = true }

--- The justifications an `Assume` may have as a set.
--- @type table<string, boolean>
M.JUSTIFICATIONS = { type_fact = true, branch = true, callee_post = true, trusted = true }

return M
