-- The elaborate pass: lowers marked code to core units with their obligations. Each verified function
-- becomes one unit, and so do the other top-level statements of each region.

local arena = require 'clavius.ir.arena'
local builder = require 'clavius.elaborate.builder'
local expr = require 'clavius.elaborate.expr'

local M = {}

-- the sort of fuel: how often an axiom may unfold a spec function
local FUEL = '$Fuel'

--- Forward declaration.
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
        local ty = b.info.types[w.root]
        if builder.has_type_fact(ty) then
            local value = builder.add(b, { tag = 'Var', name = name }, id)
            builder.assume(b, out, 'type_fact', assert(builder.type_fact(b, ty, value, id)), id)
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
    -- past ±2^53, `i + step` would round back to `i` and the loop would never end; ghost code has no doubles
    if not b.ghost then
        builder.check(b, runs, 'for_bound', builder.is_int53(b, last, id), id)
    end
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
    local defines = n.tag == 'ClvSpec' or n.tag == 'ClvLemma' or (n.tag == 'Local' and #n.values == 0)
    if b.res.defined[id] ~= nil or defines then -- luacheck: ignore 542
        -- a function definition is a unit of its own, and a forward declaration declares only functions
    elseif n.tag == 'ClvProof' or n.tag == 'ClvGhost' or n.tag == 'ClvAssert' or n.tag == 'ClvAssume' then
        local ghost = b.ghost
        b.ghost = true
        if n.tag == 'ClvProof' or n.tag == 'ClvGhost' then
            for _, s in ipairs(n.statements) do
                statement(b, s, out)
            end
        elseif n.tag == 'ClvAssert' then
            builder.check(b, out, 'assert', expr.lower(b, n.cond, out), id)
        else -- 'ClvAssume'
            builder.assume(b, out, 'assumed', expr.lower(b, n.cond, out), id)
        end
        b.ghost = ghost
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
            if b.ghost then
                builder.narrow(b, out, b.info.types[b.res.decl[n.targets[i]]], b.info.types[v], terms[i], v)
            end
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
    elseif n.tag == 'Call' and b.info.ops[id] ~= nil and b.info.ops[id].op == 'call' then
        expr.call(b, id, out)
    elseif n.tag == 'Call' then
        local callee = b.src.nodes[n.func] --[[@as SrcId]]
        if callee.name == 'assert' then
            builder.check(b, out, 'assert', expr.lower(b, n.args[1], out), id)
        elseif callee.name == 'assume' then
            builder.assume(b, out, 'assumed', expr.lower(b, n.args[1], out), id)
        else
            -- `error` must be unreachable
            builder.check(b, out, 'unreachable', builder.add(b, { tag = 'Bool', value = false }, id), id)
        end
    elseif n.tag == 'Return' then
        local fn = assert(b.fn)
        local v = n.values[1]
        if v ~= nil then
            local value = expr.lower(b, v, out)
            builder.narrow(b, out, b.info.types[fn.result], b.info.types[v], value, v)
            -- a spec function's unit only checks its body, and the axioms say what it returns
            if fn.kind ~= 'spec' then
                builder.emit(b, out, { tag = 'Assign', target = builder.name_of(b, assert(fn.result)), value = value }, id)
            end
        end
        check_posts(b, out, id)
        builder.emit(b, out, { tag = 'Exit', label = 'body' }, id)
    else
        error(('elaborate: unhandled statement %s'):format(n.tag))
    end
end

--- Returns how often a unit may unfold each spec function that the `---@reveal_with_fuel`s of `nodes`
--- name: its region and perhaps its function, whose own directive wins.
--- @param b Builder
--- @param nodes (SrcClvRegion|SrcFunction)[] outermost first
--- @return table<NodeId, integer>
local function unit_fuel(b, nodes)
    local fuel = {}
    for _, n in ipairs(nodes) do
        for _, d in ipairs(arena.directives(b.src, n, 'ClvRevealWithFuel')) do
            fuel[b.res.fuel[d]] = (b.src.nodes[d] --[[@as SrcClvRevealWithFuel]]).fuel
        end
    end
    return fuel
end

--- Lowers a verified function, lemma or spec function to a unit named like its Binder. Its body runs in a
--- Block labeled `body`, which `return` exits.
---
--- An exec function's callers are trusted to pass well-typed arguments that meet its `---@pre`s, since
--- some may be outside verification; verified ones check the `---@pre`s. Only proof code calls a lemma,
--- and it checks both. A spec function's unit checks its body without the definitions of its cycle. A
--- unit is nonlinear when its function or the region it is in is `---@proof_by nonlinear_arith`.
--- @param b Builder
--- @param binder NodeId the Binder that the function's definition defines
--- @mut b
--- @return NodeId unit
local function function_unit(b, binder)
    local fn_id = b.res.functions[binder]
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    local kind = b.res.kinds[fn_id]
    local region = b.index.region[fn_id]
    local around = region ~= 0 and {
        b.src.nodes[region] --[[@as SrcClvRegion]],
        fn,
    } or { fn }
    builder.start_unit(b)
    b.fuel = unit_fuel(b, around)
    local body = {}
    builder.definitions(b, body, kind == 'spec' and fn_id or nil, fn_id)
    --- @type Justification
    local entry_kind = 'precondition'
    if kind == 'exec' then
        entry_kind = 'trusted'
    elseif kind == 'spec' then
        -- its axioms cover only arguments of its parameters' types
        entry_kind = 'type_fact'
    end
    local decl = kind == 'exec' and fn_id or nil
    for _, p in ipairs(fn.params) do
        local ty = b.info.types[p]
        builder.var(b, builder.name_of(b, p), builder.sort(ty), p)
        if builder.has_type_fact(ty) then
            local value = builder.add(b, { tag = 'Var', name = builder.name_of(b, p) }, p)
            builder.assume(b, body, entry_kind, assert(builder.type_fact(b, ty, value, p)), p, decl)
        end
    end
    local result = arena.directives(b.src, fn, 'ClvReturn')[1]
    if result ~= nil and kind ~= 'spec' then
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
        builder.assume(b, body, entry_kind, expr.clause(b, cond, {}), pre, decl)
    end
    b.fn = { id = fn_id, kind = kind, result = result, posts = arena.directives(b.src, fn, 'ClvPost'), entry = entry }
    b.ghost = kind ~= 'exec'
    local inner = {}
    statement(b, fn.body, inner)
    -- checks after control has reached end; every path through a spec function returns, which resolve checks already
    if result ~= nil and kind ~= 'spec' then
        -- Lua would return nothing here. don't let it happen in verified code
        builder.check(b, inner, 'missing_return', builder.add(b, { tag = 'Bool', value = false }, fn_id), fn_id)
    elseif kind ~= 'spec' then
        -- add post conds for the implicit return
        check_posts(b, inner, fn_id)
    end
    b.fn, b.ghost, b.fuel = nil, false, {}
    builder.emit(b, body, { tag = 'Block', label = 'body', body = inner }, fn_id)
    local nonlinear = false
    for _, n in ipairs(around) do
        nonlinear = nonlinear or arena.has_directive(b.src, n, 'ClvProofBy')
    end
    local arith = nonlinear and 'nonlinear' or 'linear'
    return builder.add(b, { tag = 'Unit', name = builder.name_of(b, binder), arith = arith, vars = b.vars, body = body }, fn_id)
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

--- What is left of a spec function's body to lower: a statement list from `index` on, and then what
--- follows the block that the list is in.
--- @class SpecRest
--- @field statements NodeId[]
--- @field index integer
--- @field next SpecRest|nil

--- Lowers what is left of a spec function's body to the term for its value. An `if` is an Ite whose arms
--- each go on with the statements after it, and a `local` binds its names in a Let around the rest.
--- @param b Builder
--- @param rest SpecRest
--- @mut b
--- @return NodeId term
local function spec_term(b, rest)
    while rest.index > #rest.statements do
        -- every path returns, which resolve checks
        rest = assert(rest.next, 'elaborate: a spec function may end without a value')
    end
    local id = rest.statements[rest.index]
    local n = b.src.nodes[id]
    --- @type SpecRest
    local after = { statements = rest.statements, index = rest.index + 1, next = rest.next }
    if n.tag == 'Return' then
        return expr.clause(b, n.values[1], {})
    elseif n.tag == 'Local' then
        -- the names are fresh, so a value can't refer to the names bound before it
        local values = {}
        for i, v in ipairs(n.values) do
            values[i] = expr.clause(b, v, {})
        end
        local value = spec_term(b, after)
        for i = #n.names, 1, -1 do
            value = builder.add(b, { tag = 'Let', name = builder.name_of(b, n.names[i]), value = values[i], body = value }, id)
        end
        return value
    elseif n.tag == 'Block' then
        return spec_term(b, { statements = n.statements, index = 1, next = after })
    elseif n.tag == 'If' then
        local value
        if n.else_block ~= nil then
            local else_block = b.src.nodes[n.else_block] --[[@as SrcBlock]]
            value = spec_term(b, { statements = else_block.statements, index = 1, next = after })
        else
            value = spec_term(b, after)
        end
        for i = #n.arms, 1, -1 do
            local arm = b.src.nodes[n.arms[i]] --[[@as SrcIfArm]]
            local cond = expr.clause(b, arm.cond, {})
            local body = b.src.nodes[arm.body] --[[@as SrcBlock]]
            local if_true = spec_term(b, { statements = body.statements, index = 1, next = after })
            value = builder.add(b, { tag = 'Ite', cond = cond, if_true = if_true, if_false = value }, n.arms[i])
        end
        return value
    end
    error(('elaborate: unhandled spec function statement %s'):format(n.tag))
end

--- Declares the sort of fuel and its two functions: `$zero`, and `$succ`, which adds one unfolding.
--- @param b Builder
--- @param origin NodeId
--- @mut b
local function declare_fuel(b, origin)
    local fuel = builder.add(b, { tag = 'VarDecl', name = '$fuel', sort = FUEL }, origin)
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'SortDecl', name = FUEL }, origin)
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'FunDecl', name = '$zero', params = {}, sort = FUEL }, origin)
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'FunDecl', name = '$succ', params = { fuel }, sort = FUEL }, origin)
end

--- Returns the variables that an axiom about a spec function binds, its fuel when it is recursive and
--- its parameters, and the term for each parameter.
--- @param b Builder
--- @param spec BuilderSpec
--- @mut b
--- @return NodeId[] vars
--- @return NodeId[] params
local function bound(b, spec)
    local fn = b.src.nodes[spec.id] --[[@as SrcFunction]]
    local vars = {}
    if spec.recursive then
        vars[1] = builder.add(b, { tag = 'VarDecl', name = '$fuel', sort = FUEL }, spec.id)
    end
    local params = {}
    for _, p in ipairs(fn.params) do
        local name = builder.name_of(b, p)
        vars[#vars + 1] = builder.add(b, { tag = 'VarDecl', name = name, sort = builder.sort(b.info.types[p]) }, p)
        params[#params + 1] = builder.add(b, { tag = 'Var', name = name }, p)
    end
    return vars, params
end

--- Returns a spec function's FunDecl applied to `params`, after `fuel` when it is recursive.
--- @param b Builder
--- @param spec BuilderSpec
--- @param fuel NodeId|nil
--- @param params NodeId[]
--- @mut b
--- @return NodeId
local function apply(b, spec, fuel, params)
    local args = { fuel }
    for _, p in ipairs(params) do
        args[#args + 1] = p
    end
    return builder.add(b, { tag = 'App', fn = spec.name, args = args }, spec.id)
end

--- Adds the axiom `guard => (forall vars :: {trigger} body)` about a spec function.
--- @param b Builder
--- @param spec BuilderSpec
--- @param vars NodeId[]
--- @param trigger NodeId
--- @param body NodeId
--- @mut b
local function axiom(b, spec, vars, trigger, body)
    local triggers = { builder.add(b, { tag = 'Trigger', terms = { trigger } }, spec.id) }
    local forall = builder.add(b, { tag = 'Forall', vars = vars, triggers = triggers, body = body }, spec.id)
    local guard = builder.add(b, { tag = 'App', fn = spec.guard, args = {} }, spec.id)
    local cond = builder.add(b, { tag = 'BinOp', op = '=>', lhs = guard, rhs = forall }, spec.id)
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'Axiom', cond = cond }, spec.id)
end

--- Declares a spec function: a FunDecl of its parameters, after the fuel when it is recursive, and a
--- constant that guards its axioms.
--- @param b Builder
--- @param binder NodeId
--- @mut b
local function declare_spec(b, binder)
    local fn_id = b.res.functions[binder]
    local fn = b.src.nodes[fn_id] --[[@as SrcFunction]]
    local name = b.res.names[binder]
    --- @type BuilderSpec
    local spec = { id = fn_id, name = name, guard = ('$ok$%s'):format(name), recursive = b.termination.cycle[fn_id] ~= nil }
    local vars = bound(b, spec)
    local result = arena.directives(b.src, fn, 'ClvReturn')[1]
    local sort = builder.sort(b.info.types[result])
    -- spec's declaration
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'FunDecl', name = name, params = vars, sort = sort }, fn_id)
    -- it's guard constant
    b.decls[#b.decls + 1] = builder.add(b, { tag = 'FunDecl', name = spec.guard, params = {}, sort = 'bool' }, fn_id)
    b.specs[#b.specs + 1] = spec
    b.spec_of[fn_id] = spec
end

--- Adds the axioms that define a spec function. For a recursive one, one more unit of fuel unfolds it
--- once, and its value is then its body's; calls in its cycle in the body take the smaller fuel, so
--- unfolding stops, and it has the same value at every fuel. Any other one unfolds wherever it is used.
--- @param b Builder
--- @param spec BuilderSpec
--- @mut b
local function define_spec(b, spec)
    local fn = b.src.nodes[spec.id] --[[@as SrcFunction]]
    -- layer axiom: f(succ(fuel), x) == f(fuel, x)
    if spec.recursive then
        local vars, params = bound(b, spec)
        local fuel = builder.add(b, { tag = 'Var', name = '$fuel' }, spec.id)
        local more = apply(b, spec, builder.add(b, { tag = 'App', fn = '$succ', args = { fuel } }, spec.id), params)
        axiom(b, spec, vars, more, builder.add(b, { tag = 'BinOp', op = '==', lhs = more, rhs = apply(b, spec, fuel, params) }, spec.id))
    end

    -- definition axiom: f(succ(fuel), x) == body, whose calls in the cycle take fuel, or f(x) == body
    local vars, params = bound(b, spec)
    local succ = nil
    if spec.recursive then
        succ = builder.add(b, { tag = 'App', fn = '$succ', args = { builder.add(b, { tag = 'Var', name = '$fuel' }, spec.id) } }, spec.id)
    end
    local more = apply(b, spec, succ, params)
    b.axiom = { fn = spec.id, fuel = '$fuel' }
    local body = b.src.nodes[fn.body] --[[@as SrcBlock]]
    local value = spec_term(b, { statements = body.statements, index = 1, next = nil })
    b.axiom = nil
    local defined = builder.add(b, { tag = 'BinOp', op = '==', lhs = more, rhs = value }, spec.id)
    -- only for arguments of the parameters' types
    for i = #fn.params, 1, -1 do
        local fact = builder.type_fact(b, b.info.types[fn.params[i]], params[i], fn.params[i])
        if fact ~= nil then
            defined = builder.add(b, { tag = 'BinOp', op = '=>', lhs = fact, rhs = defined }, spec.id)
        end
    end
    axiom(b, spec, vars, more, defined)

    -- type-fact axiom: f(fuel, x) has the result's type
    local result = arena.directives(b.src, fn, 'ClvReturn')[1]
    local fact_vars, fact_params = bound(b, spec)
    local fuel = spec.recursive and builder.add(b, { tag = 'Var', name = '$fuel' }, spec.id) or nil
    local value_at = apply(b, spec, fuel, fact_params)
    local fact = builder.type_fact(b, b.info.types[result], value_at, result)
    if fact ~= nil then
        axiom(b, spec, fact_vars, value_at, fact)
    end
end

--- Returns the ClvSpec and ClvLemma blocks of a file in source order: at the top level and in regions.
--- @param src SrcArena
--- @param root NodeId
--- @return (SrcClvSpec|SrcClvLemma)[]
local function blocks(src, root)
    local out = {}
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        local inner = n.tag == 'ClvRegion' and n.statements or { id }
        for _, s in ipairs(inner) do
            local sn = src.nodes[s]
            if sn.tag == 'ClvSpec' or sn.tag == 'ClvLemma' then
                out[#out + 1] = sn
            end
        end
    end
    return out
end

--- Adds to `units` the units of what a top-level statement defines: a verified function, or the functions
--- of a `--[[@spec` or `--[[@lemma` block. Returns whether it is such a definition.
--- @param b Builder
--- @param id NodeId the statement
--- @param in_region boolean
--- @param units NodeId[]
--- @mut b
--- @mut units
--- @return boolean
local function definition_units(b, id, in_region, units)
    local n = b.src.nodes[id]
    local binder = b.res.defined[id]
    if binder ~= nil and is_verified(b, binder, in_region) then
        units[#units + 1] = function_unit(b, binder)
        return true
    elseif n.tag == 'ClvSpec' or n.tag == 'ClvLemma' then
        for _, s in ipairs(n.statements) do
            if b.res.defined[s] ~= nil then
                units[#units + 1] = function_unit(b, b.res.defined[s])
            end
        end
        return true
    end
    return false
end

--- Lowers the marked code of a typed file in source order. Each verified function's, lemma's and spec
--- function's unit is named like its Binder, and the units of the regions' other statements `main$1`,
--- `main$2` and so on. The declarations come first: the Funs and axioms of the spec functions.
--- @param src SrcArena
--- @param root NodeId
--- @param index NodeIndex
--- @param res Resolution
--- @param info TypeInfo
--- @param effects Effects
--- @param termination Termination
--- @return CoreProgram
function M.run(src, root, index, res, info, effects, termination)
    local b = builder.new(src, index, res, info, effects, termination)
    local fueled = false
    for _, block in ipairs(blocks(src, root)) do
        for _, s in ipairs(block.tag == 'ClvSpec' and block.statements or {}) do
            local binder = res.defined[s]
            if binder ~= nil then
                if not fueled and termination.cycle[res.functions[binder]] ~= nil then
                    declare_fuel(b, s)
                    fueled = true
                end
                declare_spec(b, binder)
            end
        end
    end
    for _, spec in ipairs(b.specs) do
        define_spec(b, spec)
    end
    local units = {}
    local regions = 0
    local top = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(top.statements) do
        local n = src.nodes[id]
        if n.tag == 'ClvRegion' then
            local others = {}
            for _, s in ipairs(n.statements) do
                local sn = src.nodes[s]
                local defined = definition_units(b, s, true, units)
                -- an unverified function and a forward declaration lower to nothing
                if not defined and res.defined[s] == nil and not (sn.tag == 'Local' and #sn.values == 0) then
                    others[#others + 1] = s
                end
            end
            if #others > 0 then
                builder.start_unit(b)
                b.fuel = unit_fuel(b, {
                    n --[[@as SrcClvRegion]],
                })
                local body = {}
                builder.definitions(b, body, nil, id)
                for _, s in ipairs(others) do
                    statement(b, s, body)
                end
                b.fuel = {}
                regions = regions + 1
                local arith = arena.has_directive(src, n --[[@as SrcClvRegion]], 'ClvProofBy') and 'nonlinear' or 'linear'
                local unit = { tag = 'Unit', name = ('main$%d'):format(regions), arith = arith, vars = b.vars, body = body }
                units[#units + 1] = builder.add(b, unit, id)
            end
        else
            definition_units(b, id, false, units)
        end
    end
    return { core = b.core, decls = b.decls, units = units, obligations = b.obligations, assumptions = b.assumptions }
end

return M
