-- The elaborate pass: lowers marked code to core units with their obligations. Each verified function
-- becomes one unit, and so do the other top-level statements of each region.

local arena = require 'clavius.ir.arena'
local builder = require 'clavius.elaborate.builder'
local expr = require 'clavius.elaborate.expr'

local M = {}

local statement

--- Checks each `---@post` of the function being built, where it returns at `origin`. A parameter in a
--- `---@post` means its value on entry.
--- @param b Builder
--- @param out NodeId[]
--- @param origin NodeId a Return, or the Function when its body ends
--- @mut b
--- @mut out
local function check_posts(b, out, origin)
    local fn = assert(b.fn)
    for _, post in ipairs(fn.posts) do
        local cond = (b.src.nodes[post] --[[@as SrcClvPost]]).cond
        builder.check(b, out, 'post', expr.clause(b, cond, fn.entry), origin, post)
    end
end

--- Lowers an `if` from its arm `i` on.
--- @param b Builder
--- @param n SrcIf
--- @param i integer
--- @param out NodeId[]
--- @mut b
--- @mut out
local function lower_if(b, n, i, out)
    local arm_id = n.arms[i]
    local arm = b.src.nodes[arm_id] --[[@as SrcIfArm]]
    local cond = expr.lower(b, arm.cond, out)
    local then_body, else_body = {}, {}
    statement(b, arm.body, then_body)
    if i < #n.arms then
        lower_if(b, n, i + 1, else_body)
    elseif n.else_block ~= nil then
        statement(b, n.else_block, else_body)
    end
    builder.emit(b, out, { tag = 'Branch', cond = cond, then_body = then_body, else_body = else_body }, arm_id)
end

--- Checks each `---@invariant` of a loop, with obligations of `kind` on the loop.
--- @param b Builder
--- @param out NodeId[]
--- @param kind 'invariant_entry' | 'invariant_preserved'
--- @param id NodeId the loop
--- @mut b
--- @mut out
local function check_invariants(b, out, kind, id)
    local loop = b.src.nodes[id] --[[@as SrcWhile|SrcRepeat|SrcFornum]]
    for _, inv in ipairs(arena.directives(b.src, loop, 'ClvInvariant')) do
        local cond = (b.src.nodes[inv] --[[@as SrcClvInvariant]]).cond
        builder.check(b, out, kind, expr.clause(b, cond, {}), id, inv)
    end
end

--- Starts an iteration at a loop's head, which stands for every iteration. The locals that the loop
--- writes become arbitrary but for their types and the invariants. Returns the variables that hold the
--- values of the measure's expressions at the head, or nil when the loop has no `---@decrease`.
--- @param b Builder
--- @param out NodeId[]
--- @param id NodeId the loop
--- @mut b
--- @mut out
--- @return string[]|nil top
local function loop_head(b, out, id)
    local loop = b.src.nodes[id] --[[@as SrcWhile|SrcRepeat|SrcFornum]]
    for _, w in ipairs(b.effects.writes[id] or {}) do
        local name = builder.name_of(b, w.root)
        builder.emit(b, out, { tag = 'Havoc', target = name }, id)
        if b.info.types[w.root] == 'int53' then
            local value = builder.add(b, { tag = 'Var', name = name }, id)
            builder.assume(b, out, 'type_fact', builder.is_int53(b, value, id), id)
        end
    end
    for _, inv in ipairs(arena.directives(b.src, loop, 'ClvInvariant')) do
        local cond = (b.src.nodes[inv] --[[@as SrcClvInvariant]]).cond
        builder.assume(b, out, 'invariant', expr.clause(b, cond, {}), inv)
    end
    local d = arena.directives(b.src, loop, 'ClvDecrease')[1]
    if d == nil then
        return nil
    end
    local decrease = b.src.nodes[d] --[[@as SrcClvDecrease]]
    local top = {}
    for i, m in ipairs(decrease.measures) do
        top[i] = builder.temp(b, 'int', d)
        builder.emit(b, out, { tag = 'Assign', target = top[i], value = expr.clause(b, m, {}) }, d)
    end
    return top
end

--- Ends an iteration that iterates again: checks the invariants, and that the measure is below its
--- value at the head. The path then ends, since the head stands for the next iteration.
--- @param b Builder
--- @param out NodeId[]
--- @param id NodeId the loop
--- @param top string[]|nil the values of the measure's expressions at the head
--- @mut b
--- @mut out
local function loop_back(b, out, id, top)
    check_invariants(b, out, 'invariant_preserved', id)
    if top ~= nil then
        local loop = b.src.nodes[id] --[[@as SrcWhile|SrcRepeat|SrcFornum]]
        local d = arena.directives(b.src, loop, 'ClvDecrease')[1]
        local decrease = b.src.nodes[d] --[[@as SrcClvDecrease]]
        -- m_top, the values at the head, and m_next, the measure lowered again here, after the body
        local before, after = {}, {}
        for i, m in ipairs(decrease.measures) do
            before[i] = builder.add(b, { tag = 'Var', name = top[i] }, d)
            after[i] = expr.clause(b, m, {})
        end
        builder.check(b, out, 'decrease', builder.decreases(b, before, after, d), id, d)
    end
    -- end the path: the head's havoc and invariants already cover the next iteration, and falling through
    -- would reach the code after the loop without testing the condition again
    builder.assume(b, out, 'back_edge', builder.add(b, { tag = 'Bool', value = false }, id), id)
end

--- Lowers a loop's body, in which `break` exits the loop's Block.
--- @param b Builder
--- @param body NodeId
--- @param label string
--- @param out NodeId[]
--- @mut b
--- @mut out
local function loop_body(b, body, label, out)
    b.breaks[#b.breaks + 1] = label
    statement(b, body, out)
    b.breaks[#b.breaks] = nil
end

--- Lowers `while cond do body end`. Each iteration evaluates the condition at the head; when it holds,
--- the body runs and iterates again, and otherwise the loop exits.
--- e.g.
---
---     ---@invariant i <= n
---     ---@decrease n - i
---     while i < n do
---         i = i + 1
---     end
---
--- becomes this core, where `(int53 e)` stands for `-2^53 <= e and e <= 2^53`:
---
---     (Check 1 (BinOp <= (Var i) (Var n)))                    ; invariant_entry
---     (Block loop$1
---       [(Havoc i)                                            ; what the loop writes
---        (Assume 1 (int53 (Var i)))                           ; type_fact
---        (Assume 2 (BinOp <= (Var i) (Var n)))                ; invariant
---        (Assign $t1 (BinOp - (Var n) (Var i)))               ; the measure at the head
---        (Branch
---          (BinOp < (Var i) (Var n))
---          [(Check 2 (int53 (BinOp + (Var i) (Int 1))))       ; range
---           (Assign i (BinOp + (Var i) (Int 1)))
---           (Check 3 (BinOp <= (Var i) (Var n)))              ; invariant_preserved
---           (Check 4                                          ; decrease
---             (BinOp and (BinOp <= (Int 0) (Var $t1)) (BinOp < (BinOp - (Var n) (Var i)) (Var $t1))))
---           (Assume 3 (Bool false))]                          ; back_edge
---          [])])                                              ; `break` is `(Exit loop$1)`
--- @param b Builder
--- @param id NodeId
--- @param n SrcWhile
--- @param out NodeId[]
--- @mut b
--- @mut out
local function lower_while(b, id, n, out)
    check_invariants(b, out, 'invariant_entry', id)
    local label = builder.loop_label(b)
    local inner = {}
    local top = loop_head(b, inner, id)
    local cond = expr.lower(b, n.cond, inner)
    local again = {}
    loop_body(b, n.body, label, again)
    loop_back(b, again, id, top)
    builder.emit(b, inner, { tag = 'Branch', cond = cond, then_body = again, else_body = {} }, id)
    builder.emit(b, out, { tag = 'Block', label = label, body = inner }, id)
end

--- Lowers `repeat body until cond`. The body runs from the head, and the condition, which sees the body's
--- locals, then decides between the exit and iterating again.
--- e.g.
---
---     ---@decrease n - i
---     repeat
---         local j = i + 1
---         i = j
---     until j >= n
---
--- becomes this core:
---
---     (Block loop$1
---       [(Havoc i)
---        (Assume 1 (int53 (Var i)))                           ; type_fact
---        (Assign $t1 (BinOp - (Var n) (Var i)))
---        (Check 1 (int53 (BinOp + (Var i) (Int 1))))          ; range
---        (Assign j (BinOp + (Var i) (Int 1)))
---        (Assign i (Var j))
---        (Branch
---          (BinOp >= (Var j) (Var n))
---          []
---          [(Check 2                                          ; decrease
---             (BinOp and (BinOp <= (Int 0) (Var $t1)) (BinOp < (BinOp - (Var n) (Var i)) (Var $t1))))
---           (Assume 2 (Bool false))])])                       ; back_edge
--- @param b Builder
--- @param id NodeId
--- @param n SrcRepeat
--- @param out NodeId[]
--- @mut b
--- @mut out
local function lower_repeat(b, id, n, out)
    check_invariants(b, out, 'invariant_entry', id)
    local label = builder.loop_label(b)
    local inner = {}
    local top = loop_head(b, inner, id)
    loop_body(b, n.body, label, inner)
    local cond = expr.lower(b, n.cond, inner)
    local again = {}
    loop_back(b, again, id, top)
    builder.emit(b, inner, { tag = 'Branch', cond = cond, then_body = {}, else_body = again }, id)
    builder.emit(b, out, { tag = 'Block', label = label, body = inner }, id)
end

--- Evaluates a bound of a numeric `for` once: a literal stays as it is, and anything else goes into a
--- temporary, since the body may assign what it reads.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @return NodeId term
local function bound_once(b, id, out)
    local t = expr.lower(b, id, out)
    if b.core.nodes[t].tag == 'Int' then
        return t
    end
    local name = builder.temp(b, 'int', id)
    builder.emit(b, out, { tag = 'Assign', target = name, value = t }, id)
    return builder.add(b, { tag = 'Var', name = name }, id)
end

--- Returns `at <= limit` when the step is positive, and `at >= limit` when it is negative.
--- @param b Builder
--- @param up boolean
--- @param at NodeId
--- @param limit NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId
local function within(b, up, at, limit, origin)
    return builder.add(b, { tag = 'BinOp', op = up and '<=' or '>=', lhs = at, rhs = limit }, origin)
end

--- Returns the counter's range: `start <= i <= last` when the step is positive, and `last <= i <= start`
--- when it is negative.
--- @param b Builder
--- @param up boolean
--- @param counter NodeId
--- @param start NodeId
--- @param last NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId
local function counter_range(b, up, counter, start, last, origin)
    local lo = up and start or last -- the smaller end
    local hi = up and last or start -- the larger end
    local above = builder.add(b, { tag = 'BinOp', op = '<=', lhs = lo, rhs = counter }, origin)
    local below = builder.add(b, { tag = 'BinOp', op = '<=', lhs = counter, rhs = hi }, origin)
    return builder.add(b, { tag = 'BinOp', op = 'and', lhs = above, rhs = below }, origin)
end

--- Returns `(0 < step and when_up) or (step < 0 and when_down)`.
--- @param b Builder
--- @param step NodeId
--- @param when_up NodeId
--- @param when_down NodeId
--- @param origin NodeId
--- @mut b
--- @return NodeId
local function by_sign(b, step, when_up, when_down, origin)
    local zero = builder.add(b, { tag = 'Int', text = '0' }, origin)
    local up = builder.add(b, { tag = 'BinOp', op = '<', lhs = zero, rhs = step }, origin)
    local down = builder.add(b, { tag = 'BinOp', op = '<', lhs = step, rhs = zero }, origin)
    local first = builder.add(b, { tag = 'BinOp', op = 'and', lhs = up, rhs = when_up }, origin)
    local second = builder.add(b, { tag = 'BinOp', op = 'and', lhs = down, rhs = when_down }, origin)
    return builder.add(b, { tag = 'BinOp', op = 'or', lhs = first, rhs = second }, origin)
end

--- Lowers `for i = start, limit, step do body end`. The loop runs only when `start` is within `limit`.
--- Its counter `i` then goes from `start` to `limit + step`, which is an invariant that Clavius generates
--- and checks like the written ones. A step that is a nonzero literal fixes the direction, and the
--- counter also moves by whole steps. Any other step is read once and checked to be nonzero, and each
--- comparison splits on its sign.
--- e.g.
---
---     ---@invariant s >= 0
---     for k = n, 1, -2 do
---         s = s + k
---     end
---
--- becomes this core, where R stands for the counter's range
--- `(BinOp and (BinOp and (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k)) (BinOp <= (Var k) (Var $t1)))
--- (BinOp == (BinOp mod (BinOp - (Var k) (Var $t1)) (Int 2)) (Int 0)))`:
---
---     (Assign $t1 (Var n))                                    ; the bound, read once
---     (Branch
---       (BinOp >= (Var $t1) (Int 1))
---       [(Check 1 (int53 (BinOp + (Int 1) (Int -2))))         ; for_bound
---        (Assign k (Var $t1))
---        (Check 2 R)                                          ; invariant_entry
---        (Check 3 (BinOp >= (Var s) (Int 0)))                 ; invariant_entry
---        (Block loop$1
---          [(Havoc k)
---           (Assume 1 R)                                      ; invariant
---           (Havoc s)
---           (Assume 2 (int53 (Var s)))                        ; type_fact
---           (Assume 3 (BinOp >= (Var s) (Int 0)))             ; invariant
---           (Branch
---             (BinOp >= (Var k) (Int 1))
---             [(Check 4 (int53 (BinOp + (Var s) (Var k))))    ; range
---              (Assign s (BinOp + (Var s) (Var k)))
---              (Assign k (BinOp + (Var k) (Int -2)))
---              (Check 5 R)                                    ; invariant_preserved
---              (Check 6 (BinOp >= (Var s) (Int 0)))           ; invariant_preserved
---              (Assume 4 (Bool false))]                       ; back_edge
---             [])])]
---       [])
--- @param b Builder
--- @param id NodeId
--- @param n SrcFornum
--- @param out NodeId[]
--- @mut b
--- @mut out
local function lower_fornum(b, id, n, out)
    local start = bound_once(b, n.start, out)
    local limit = bound_once(b, n.limit, out)
    local literal, negative = nil, false
    if n.step ~= nil then
        literal, negative = arena.nonzero_literal(b.src, n.step)
    end
    local abs = '1' -- |step| as digits, when the step is a literal
    local step
    if n.step == nil then
        step = builder.add(b, { tag = 'Int', text = abs }, id)
    elseif literal ~= nil then
        abs = expr.int_text((b.src.nodes[literal] --[[@as SrcLiteral]]).text)
        step = builder.add(b, { tag = 'Int', text = negative and ('-' .. abs) or abs }, n.step)
    else
        step = bound_once(b, n.step, out)
        -- checked even when the loop doesn't run: LuaJIT never ends `for i = 1, 3, 0`, Lua 5.1 `for i = 3, 1, 0`
        local zero = builder.add(b, { tag = 'Int', text = '0' }, id)
        builder.check(b, out, 'for_step', builder.add(b, { tag = 'BinOp', op = '!=', lhs = step, rhs = zero }, id), id)
    end
    local i = builder.name_of(b, n.var)
    builder.var(b, i, 'int', n.var)
    local counter = builder.add(b, { tag = 'Var', name = i }, n.var)
    local last = builder.add(b, { tag = 'BinOp', op = '+', lhs = limit, rhs = step }, id)

    local guard, cond, range
    if n.step == nil or literal ~= nil then
        local up = not negative
        guard = within(b, up, start, limit, id)
        cond = within(b, up, counter, limit, id)
        range = counter_range(b, up, counter, start, last, id)
        -- every integer is a whole number of steps of 1 from start
        if abs ~= '1' then
            local diff = builder.add(b, { tag = 'BinOp', op = '-', lhs = counter, rhs = start }, id) -- i - start
            local size = builder.add(b, { tag = 'Int', text = abs }, id) -- |step|
            local rem = builder.add(b, { tag = 'BinOp', op = 'mod', lhs = diff, rhs = size }, id) -- (i - start) mod |step|
            local zero = builder.add(b, { tag = 'Int', text = '0' }, id)
            local whole = builder.add(b, { tag = 'BinOp', op = '==', lhs = rem, rhs = zero }, id) -- a whole number of steps from start
            range = builder.add(b, { tag = 'BinOp', op = 'and', lhs = range, rhs = whole }, id) -- lo <= i <= hi and whole steps
        end
    else
        -- linear in either direction; whole steps of a variable size would be nonlinear
        guard = by_sign(b, step, within(b, true, start, limit, id), within(b, false, start, limit, id), id)
        cond = by_sign(b, step, within(b, true, counter, limit, id), within(b, false, counter, limit, id), id)
        local up_range = counter_range(b, true, counter, start, last, id)
        local down_range = counter_range(b, false, counter, start, last, id)
        range = by_sign(b, step, up_range, down_range, id)
    end

    local runs = {}
    -- past ±2^53, `i + step` would round back to `i` and the loop would never end
    builder.check(b, runs, 'for_bound', builder.is_int53(b, last, id), id)
    builder.emit(b, runs, { tag = 'Assign', target = i, value = start }, n.var)
    builder.check(b, runs, 'invariant_entry', range, id)
    check_invariants(b, runs, 'invariant_entry', id)
    local label = builder.loop_label(b)
    local inner = {}
    builder.emit(b, inner, { tag = 'Havoc', target = i }, id) -- counter changes in every iteration
    builder.assume(b, inner, 'invariant', range, id) -- is within its range
    local top = loop_head(b, inner, id) -- the writes and invariants; top holds the measure at the head
    local again = {} -- one more iteration
    loop_body(b, n.body, label, again)
    local stepped = builder.add(b, { tag = 'BinOp', op = '+', lhs = counter, rhs = step }, id) -- i + step
    -- i is within limit here, so i + step is between i and limit + step, which `for_bound` keeps within ±2^53
    builder.emit(b, again, { tag = 'Assign', target = i, value = stepped }, id)
    builder.check(b, again, 'invariant_preserved', range, id) -- the stepped counter is within its range
    loop_back(b, again, id, top) -- check the invariants and the measure, then end the path
    -- one more iteration while i is within limit, and otherwise the exit, which falls past the Branch
    builder.emit(b, inner, { tag = 'Branch', cond = cond, then_body = again, else_body = {} }, id)
    builder.emit(b, runs, { tag = 'Block', label = label, body = inner }, id)
    -- an empty loop runs nothing and checks nothing
    builder.emit(b, out, { tag = 'Branch', cond = guard, then_body = runs, else_body = {} }, id)
end

--- Lowers a statement and adds its core statements to `out`.
--- @param b Builder
--- @param id NodeId
--- @param out NodeId[]
--- @mut b
--- @mut out
--- @decrease id
function statement(b, id, out)
    local n = b.src.nodes[id]
    if b.res.defined[id] ~= nil or (n.tag == 'Local' and #n.values == 0) then -- luacheck: ignore 542
        -- a function definition is a unit of its own, and a forward declaration declares only functions
    elseif n.tag == 'Local' then
        local terms = {}
        for i, v in ipairs(n.values) do
            terms[i] = expr.lower(b, v, out)
        end
        -- the names are fresh, so the values can't refer to them
        for i, name in ipairs(n.names) do
            builder.var(b, builder.name_of(b, name), builder.sort(b.info.types[name]), name)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, name), value = terms[i] }, id)
        end
    elseif n.tag == 'Set' then
        local terms = {}
        for i, v in ipairs(n.values) do
            terms[i] = expr.lower(b, v, out)
        end
        if #n.targets == 1 then
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, n.targets[1]), value = terms[1] }, id)
            return
        end
        -- every value is evaluated before the first assignment
        local temps = {}
        for i, v in ipairs(n.values) do
            temps[i] = builder.temp(b, builder.sort(b.info.types[v]), v)
            builder.emit(b, out, { tag = 'Assign', target = temps[i], value = terms[i] }, v)
        end
        for i, t in ipairs(n.targets) do
            local value = builder.add(b, { tag = 'Var', name = temps[i] }, t)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, t), value = value }, id)
        end
    elseif n.tag == 'Block' then
        for _, s in ipairs(n.statements) do
            statement(b, s, out)
        end
    elseif n.tag == 'If' then
        lower_if(b, n, 1, out)
    elseif n.tag == 'While' then
        lower_while(b, id, n, out)
    elseif n.tag == 'Repeat' then
        lower_repeat(b, id, n, out)
    elseif n.tag == 'Fornum' then
        lower_fornum(b, id, n, out)
    elseif n.tag == 'Break' then
        builder.emit(b, out, { tag = 'Exit', label = assert(b.breaks[#b.breaks]) }, id)
    elseif n.tag == 'Call' and b.info.callees[id] ~= nil then
        expr.call(b, id, out)
    elseif n.tag == 'Call' then
        local callee = b.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            builder.check(b, out, 'assert', expr.lower(b, n.args[1], out), id)
        else
            -- `error` must be unreachable
            builder.check(b, out, 'unreachable', builder.add(b, { tag = 'Bool', value = false }, id), id)
        end
    elseif n.tag == 'Return' then
        local fn = assert(b.fn)
        if n.values[1] ~= nil then
            local value = expr.lower(b, n.values[1], out)
            builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, assert(fn.result)), value = value }, id)
        end
        check_posts(b, out, id)
        builder.emit(b, out, { tag = 'Exit', label = 'body' }, id)
    else
        error(('elaborate: unhandled statement %s'):format(n.tag))
    end
end

--- Lowers a verified function to a unit named like its Binder. Its callers are trusted to pass well-typed
--- arguments that meet its `---@pre`s, since some may be outside verification; verified ones check the
--- `---@pre`s. Its body runs in a Block labeled `body`, which `return` exits.
--- @param b Builder
--- @param binder NodeId the Binder that the function's definition defines
--- @mut b
--- @return NodeId unit
local function function_unit(b, binder)
    local fn_id = b.res.functions[binder]
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    builder.start_unit(b)
    local body = {}
    for _, p in ipairs(fn.params) do
        local ty = b.info.types[p]
        builder.var(b, builder.name_of(b, p), builder.sort(ty), p)
        if ty == 'int53' then
            local value = builder.add(b, { tag = 'Var', name = builder.name_of(b, p) }, p)
            builder.assume(b, body, 'trusted', builder.is_int53(b, value, p), p, fn_id)
        end
    end
    local result = arena.directives(b.src, fn, 'ClvReturn')[1]
    if result ~= nil then
        builder.var(b, builder.name_of(b, result), builder.sort(b.info.types[result]), result)
    end
    --- @type table<NodeId, NodeId>
    local entry = {}
    for _, p in ipairs(fn.params) do
        if b.res.assigned[p] then
            local t = builder.temp(b, builder.sort(b.info.types[p]), p)
            local value = builder.add(b, { tag = 'Var', name = builder.name_of(b, p) }, p)
            builder.emit(b, body, { tag = 'Assign', target = t, value = value }, p)
            entry[p] = builder.add(b, { tag = 'Var', name = t }, p)
        end
    end
    for _, pre in ipairs(arena.directives(b.src, fn, 'ClvPre')) do
        local cond = (b.src.nodes[pre] --[[@as SrcClvPre]]).cond
        builder.assume(b, body, 'trusted', expr.clause(b, cond, {}), pre, fn_id)
    end
    b.fn = { id = fn_id, result = result, posts = arena.directives(b.src, fn, 'ClvPost'), entry = entry }
    local inner = {}
    statement(b, fn.body, inner)
    -- checks after control has reached end
    if result ~= nil then
        -- Lua would return nothing here. don't let it happen in verified code
        builder.check(b, inner, 'missing_return', builder.add(b, { tag = 'Bool', value = false }, fn_id), fn_id)
    else
        -- add post conds for the implicit return
        check_posts(b, inner, fn_id)
    end
    b.fn = nil
    builder.emit(b, body, { tag = 'Block', label = 'body', body = inner }, fn_id)
    return builder.add(b, { tag = 'Unit', name = builder.name_of(b, binder), vars = b.vars, body = body }, fn_id)
end

--- Returns whether a top-level function definition is verified: marked `---@clavius`, or in a region and
--- not `---@unsafe`.
--- @param b Builder
--- @param binder NodeId the Binder that it defines
--- @param in_region boolean
--- @return boolean
local function is_verified(b, binder, in_region)
    local fn = b.src.nodes[b.res.functions[binder]] --[[@as SrcFunction]]
    if arena.has_directive(b.src, fn, 'ClvMarker') then
        return true
    end
    return in_region and not arena.has_directive(b.src, fn, 'ClvUnsafe')
end

--- Lowers the marked code of a typed file in source order. Each verified function's unit is named like
--- its Binder, and the units of the regions' other statements `main$1`, `main$2` and so on.
--- @param src SrcArena
--- @param root NodeId
--- @param res Resolution
--- @param info TypeInfo
--- @param effects Effects
--- @param termination Termination
--- @return CoreProgram
function M.run(src, root, res, info, effects, termination)
    local b = builder.new(src, res, info, effects, termination)
    local units = {}
    local regions = 0
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        local binder = res.defined[id]
        if binder ~= nil and is_verified(b, binder, false) then
            units[#units + 1] = function_unit(b, binder)
        elseif n.tag == 'ClvRegion' then
            local others = {}
            for _, s in ipairs(n.statements) do
                local sn = src.nodes[s]
                local defines = res.defined[s]
                if defines ~= nil and is_verified(b, defines, true) then
                    units[#units + 1] = function_unit(b, defines)
                elseif defines == nil and not (sn.tag == 'Local' and #sn.values == 0) then
                    others[#others + 1] = s
                end
            end
            if #others > 0 then
                builder.start_unit(b)
                local body = {}
                for _, s in ipairs(others) do
                    statement(b, s, body)
                end
                regions = regions + 1
                units[#units + 1] = builder.add(b, { tag = 'Unit', name = ('main$%d'):format(regions), vars = b.vars, body = body }, id)
            end
        end
    end
    return { core = b.core, units = units, obligations = b.obligations, assumptions = b.assumptions }
end

return M
