-- Obligation and assumption records. Each `Check` in the core names an obligation: what the check
-- proves and the source node it covers. Each `Assume` names an assumption: the fact's justification
-- and the source node it comes from.

--- What a check proves.
--- @alias ObligationKind
--- | 'range' # an integer result stays within ±2^53
--- | 'assert' # an `assert` call holds
--- | 'unreachable' # the code never runs, as with `error`
--- | 'pre' # a call meets one of the callee's `---@pre`s
--- | 'post' # a function's value and parameters meet one of its `---@post`s where it returns
--- | 'missing_return' # a function with a `---@return` never reaches the end of its body
--- | 'invariant_entry' # a loop's `---@invariant`, or the range of a numeric `for`'s counter, holds when the loop starts
--- | 'invariant_preserved' # a loop's invariant, or the counter's range, holds again after an iteration
--- | 'decrease' # a `---@decrease` measure decreases, on a loop's back edge or at a recursive call
--- | 'for_bound' # a numeric `for`'s limit plus its step stays within ±2^53, so the counter can pass it
--- | 'for_step' # a numeric `for`'s step is not 0
--- | 'div_zero' # the divisor of `%` or of `math.floor(a / b)` isn't 0
--- | 'mod_range' # `a - a % b` stays within ±2^53, so LuaJIT computes `a % b` exactly

--- Why an assumption may be made. Nothing proves a `trusted` one, so the trust report lists each. The
--- `false` of a `back_edge` ends an iteration whose checks are done, since the loop's head, with its
--- havoc and invariants, stands for every later iteration. At a recursive call, `callee_post` holds by
--- induction on the measure that the call decreases.
--- @alias Justification
--- | 'type_fact' # a value of a declared type satisfies that type's predicate
--- | 'branch' # the condition of the branch being taken
--- | 'callee_post' # a verified callee's `---@post`, proved where the callee returns
--- | 'trusted' # what a trusted callee promises, or what a verified function assumes on entry about outside callers
--- | 'invariant' # a loop invariant at the loop's head, checked on entry and after each iteration
--- | 'back_edge' # `false` at the end of an iteration that iterates again

--- @class Obligation
--- @field kind ObligationKind
--- @field node NodeId the source node it covers
--- @field clause NodeId|nil the ClvPre, ClvPost, ClvInvariant or ClvDecrease it is for

--- @class Assumption
--- @field kind Justification
--- @field node NodeId the source node it comes from
--- @field decl NodeId|nil for a trusted one, the Function whose contract or callers it trusts

local M = {}

--- The obligation kinds as a set.
--- @type table<string, boolean>
M.OBLIGATION_KINDS = {
    range = true,
    assert = true,
    unreachable = true,
    pre = true,
    post = true,
    missing_return = true,
    invariant_entry = true,
    invariant_preserved = true,
    decrease = true,
    for_bound = true,
    for_step = true,
    div_zero = true,
    mod_range = true,
}

--- The justifications an `Assume` may have as a set.
--- @type table<string, boolean>
M.JUSTIFICATIONS = { type_fact = true, branch = true, callee_post = true, trusted = true, invariant = true, back_edge = true }

return M
