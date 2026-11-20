-- Turns diagnostics and failing obligations into messages in source order.

local arena = require 'clavius.ir.arena'

local M = {}

local UNSUPPORTED = "%s isn't supported in this version; leave this code unmarked"

--- Message templates by code. `PHRASES` first replaces the arguments it names, and the template is then
--- filled in with the diagnostic's arguments in order.
--- @type table<string, string>
local TEMPLATES = {
    ['E-syntax'] = '%s',
    ['E-misplaced-directive'] = '%s',
    ['E-unsupported-feature'] = UNSUPPORTED,
    ['E-unsupported-type'] = "values of type %s aren't supported in this version; leave this code unmarked",
    ['E-unsupported-directive'] = UNSUPPORTED:format '`---@%s`',
    ['E-unsupported-call'] = UNSUPPORTED:format '`%s`',
    ['E-banned-call'] = "`%s` can't be used in verified code",
    ['E-banned-global'] = "the global `%s` can't be used in verified code",
    ['E-banned-goto'] = "`goto` and labels can't be used in verified code",
    ['E-type-mismatch'] = 'expected %s, found %s',
    ['E-internal-node'] = '%s where a %s belongs',
    ['E-internal-check'] = 'Check O%s has no obligation of a known kind',
    ['E-internal-assume'] = 'Assume A%s has no allowed justification',
    ['E-internal-exit'] = 'Exit %s has no enclosing Block with that label',
    ['E-internal-label'] = 'Block label %s is already used in this unit',
    ['E-internal-back-edge'] = 'Assume A%s ends the path but has statements after it',
    ['E-internal-coverage'] = '%s has no %s obligation',
}

--- The codes whose arguments are keys of `PHRASES`. The arguments of other codes are names from the
--- program and must never be read as keys.
--- @type table<string, boolean>
local KEYED = { ['E-syntax'] = true, ['E-misplaced-directive'] = true, ['E-unsupported-feature'] = true }

--- What the keys in diagnostic arguments stand for. An argument that isn't a key, such as one of
--- luacheck's syntax errors, is used as it is.
--- @type table<string, string>
local PHRASES = {
    -- syntax that luacheck accepts and the LuaJIT 2.1 grammar rejects; recent LuaJIT releases accept some of it
    ['lua53-operator'] = "`//` and bit operators aren't supported; use the `bit` library",
    ['compound-assignment'] = "compound assignment isn't supported",
    ['local-attribute'] = 'local attributes are not LuaJIT syntax',
    ['malformed-number'] = 'malformed number',
    ['empty-statement'] = "an empty statement isn't supported",
    ['break-not-last'] = '`break` must be the last statement of its block',
    ['break-outside-loop'] = '`break` outside a loop',
    ['vararg-outside-vararg-function'] = '`...` outside a vararg function',
    ['clavius-args'] = '`---@clavius` takes `begin`, `end` or nothing',
    -- directive arguments
    ['unexpected-text'] = 'unexpected text after the directive',
    ['expected-type'] = 'expected a type',
    ['expected-name'] = 'expected a name',
    ['expected-code'] = 'expected Lua code after the tag',
    ['one-expression'] = 'expected one expression',
    ['unknown-attribute'] = 'unknown attribute',
    ['expected-positive-integer'] = 'expected a positive integer',
    ['expected-string'] = 'expected a string',
    ['expected-fun'] = 'expected a `fun(…)` type',
    ['unknown-theory'] = '`---@proof_by` takes `nonlinear_arith` or `bit_vector`',
    ['expected-('] = 'expected `(`',
    ['expected-)'] = 'expected `)`',
    ['expected-<'] = 'expected `<`',
    ['expected->'] = 'expected `>`',
    ['expected-]'] = 'expected `]`',
    ['expected-}'] = 'expected `}`',
    ['expected-:'] = 'expected `:`',
    ['expected-,'] = 'expected `,`',
    -- region markers
    ['marker-in-block'] = 'a region marker must sit between top-level statements',
    ['nested-begin'] = "regions can't nest",
    ['unpaired-end'] = '`---@clavius end` without a `begin`',
    ['unpaired-begin'] = '`---@clavius begin` without an `end`',
    -- directive placement
    ['no-function-below'] = 'this directive belongs right above a function definition',
    ['no-loop-below'] = 'this directive belongs right above a loop',
    ['not-above-statement'] = 'a directive must sit on its own line above a statement',
    ['no-such-param'] = 'no parameter has this name',
    ['repeated-param'] = 'this parameter already has a `---@param`',
    ['return-name-clash'] = "a parameter has the name of the function's value",
    ['marked-unsafe'] = "a function can't be both `---@clavius` and `---@unsafe`",
    ['repeated-decrease'] = 'this loop already has a `---@decrease`',
    ['missing-decrease'] = 'a `while` or `repeat` loop needs a `---@decrease` above it',
    -- node kinds
    Index = 'indexing',
    Table = 'a table constructor',
    Forin = 'a generic `for` loop',
    Dots = '`...`',
    -- operators
    div = 'the `/` operator',
    mod = 'the `%` operator',
    pow = 'the `^` operator',
    concat = 'the `..` operator',
    len = 'the `#` operator',
    -- forms
    ['local-values'] = 'a `local` whose names and values differ in number',
    ['assign-values'] = 'an assignment whose targets and values differ in number',
    ['repeated-target'] = 'assigning a local twice in one assignment',
    ['call'] = 'a call of anything but `assert`, `error` or a `local function` by its name',
    ['call-args'] = "a call whose arguments and the callee's parameters differ in number",
    ['call-in-contract'] = 'a call in a contract or a loop annotation',
    ['recursion'] = 'recursion',
    ['unmarked-callee'] = 'a call to a function that is neither `---@clavius` nor `---@unsafe`',
    ['reassigned-function'] = 'a call to a function that is assigned somewhere in the file',
    ['function-value'] = 'a function other than a top-level `local function`, or one used as a value',
    ['return-outside-function'] = '`return` outside a function',
    ['multiple-returns'] = 'more than one return value',
    ['call-value'] = '`assert` or `error` used other than as a call statement',
    ['assert-args'] = '`assert` with arguments other than a condition and a literal message',
    ['error-args'] = '`error` with arguments that are not literals',
    ['outer-local'] = 'a local declared outside this region',
    ['truthiness'] = 'a condition or an operand of `and`, `or` or `not` that is not a boolean',
    ['for-step'] = 'a numeric `for` loop whose step is neither omitted nor a nonzero integer literal',
    ['loop-variable-write'] = "assigning a numeric `for` loop's variable",
    ['spec-block'] = 'a `--[[@spec` block',
    ['lemma-block'] = 'a `--[[@lemma` block',
    ['proof-block'] = 'a `--[[@proof` block',
}

--- What a failing obligation of each kind means. `%s` is the source text of its clause's condition or
--- measure, if it has one, or else of its node.
--- @type table<string, string>
local FAILURES = {
    range = '%s may leave ±2^53',
    assert = 'this assertion may fail',
    unreachable = 'this `error` may be reached',
    pre = 'this call may not satisfy its precondition `%s`',
    post = 'the function may return here without satisfying its postcondition `%s`',
    missing_return = 'the end of this function may be reached, where it returns no value',
    invariant_entry = 'the loop invariant `%s` may not hold when the loop starts',
    invariant_preserved = 'the loop invariant `%s` may not hold again after an iteration',
    decrease = 'an iteration may start with the measure `%s` negative, or may not decrease it',
    for_bound = "this loop's limit plus its step may leave ±2^53",
}

--- What a failing obligation that the counter of a numeric `for` needs means. It has no clause.
--- @type table<string, string>
local COUNTER_FAILURES = {
    invariant_entry = "the loop counter's range may not hold when the loop starts",
    invariant_preserved = "the loop counter's range may not hold again after an iteration",
}

--- @param text string
--- @param offset integer
--- @return string `line:col`
local function position(text, offset)
    local line, col = arena.line_col(text, arena.line_starts(text), offset)
    return ('%d:%d'):format(line, col)
end

--- Formats a diagnostic as `line:col: code: message`.
--- @param d Diag
--- @param spans Span[] belong to the arena that the node is in
--- @param text string the file that the spans point into
--- @return string
function M.diag(d, spans, text)
    local span = d.span or spans[d.node]
    local template = assert(TEMPLATES[d.code], ('messages: no template for %s'):format(d.code))
    local args = {}
    for i, a in ipairs(d.args) do
        args[i] = KEYED[d.code] and PHRASES[a] or a
    end
    return ('%s: %s: %s'):format(position(text, span.start), d.code, template:format(unpack(args)))
end

--- Formats the failing obligation `id` as `line:col: kind: message [O17]`.
--- @param id integer
--- @param o Obligation
--- @param src SrcArena
--- @param text string
--- @return string
function M.failure(id, o, src, text)
    local span = src.spans[o.node]
    -- a clause is quoted without its tag
    local quoted = span
    local template = FAILURES[o.kind]
    if o.clause ~= nil then
        local clause = src.nodes[o.clause]
        if clause.tag == 'ClvDecrease' then
            local first = src.spans[clause.measures[1]]
            quoted = arena.span(first.file, first.start, src.spans[clause.measures[#clause.measures]].finish)
        elseif clause.tag == 'ClvPre' or clause.tag == 'ClvPost' or clause.tag == 'ClvInvariant' then
            quoted = src.spans[clause.cond]
        end
    elseif COUNTER_FAILURES[o.kind] then
        template = COUNTER_FAILURES[o.kind]
    end
    local snippet = text:sub(quoted.start, quoted.finish):gsub('%s+', ' ')
    local message = assert(template, ('messages: no message for %s'):format(o.kind)):format(snippet)
    return ('%s: %s: %s [O%d]'):format(position(text, span.start), o.kind, message, id)
end

--- A message with its sort key.
--- @class SortedMessage
--- @field start integer
--- @field key string
--- @field text string

--- @param list SortedMessage[]
--- @return string[]
local function in_order(list)
    --- @param a SortedMessage
    --- @param b SortedMessage
    --- @return boolean
    local function before(a, b)
        if a.start ~= b.start then
            return a.start < b.start
        end
        return a.key < b.key
    end
    table.sort(list, before)
    local out = {}
    for i, m in ipairs(list) do
        out[i] = m.text
    end
    return out
end

--- Formats diagnostics in source order: by span start, then code.
--- @param diags Diag[]
--- @param spans Span[]
--- @param text string
--- @return string[]
function M.diags(diags, spans, text)
    local list = {}
    for i, d in ipairs(diags) do
        local span = d.span or spans[d.node]
        -- table.sort isn't stable, so the index keeps equal keys in order
        list[i] = { start = span.start, key = ('%s %08d'):format(d.code, i), text = M.diag(d, spans, text) }
    end
    return in_order(list)
end

--- Formats failing obligations in source order: by span start, then kind.
--- @param failed integer[] obligation ids
--- @param obligations Obligation[]
--- @param src SrcArena
--- @param text string
--- @return string[]
function M.failures(failed, obligations, src, text)
    local list = {}
    for i, id in ipairs(failed) do
        local o = obligations[id]
        list[i] = { start = src.spans[o.node].start, key = ('%s %08d'):format(o.kind, id), text = M.failure(id, o, src, text) }
    end
    return in_order(list)
end

return M
