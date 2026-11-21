-- Recursive functions with `---@decrease`. A call that stays in its caller's cycle must decrease the
-- measure, and may then rely on the callee's `---@post`. Mutual recursion declares the later function
-- with a `local` first.
local is_odd
local visit

---@clavius begin

---@param n integer
---@pre n >= 0 and n <= 1000
---@post result >= n and result <= 1000 * n
---@return integer
---@decrease n
local function sum_to(n)
    if n == 0 then
        return 0
    end
    return n + sum_to(n - 1)
end

-- a parameter assigned before the call; the measure on entry is the one that counts
---@param n integer
---@pre n >= 0 and n < 1000
---@post result == 0
---@return integer
---@decrease n
local function drain(n)
    if n == 0 then
        return 0
    end
    n = n - 1
    return drain(n)
end

---@param n integer
---@pre n >= 0 and n < 1000
---@decrease n
---@return boolean
local function is_even(n)
    if n == 0 then
        return true
    end
    return is_odd(n - 1)
end

---@param n integer
---@pre n >= 0 and n < 1000
---@decrease n
---@return boolean
function is_odd(n)
    if n == 0 then
        return false
    end
    return is_even(n - 1)
end

-- a lexicographic measure: the second expression may grow when the first decreases
---@param m integer
---@param n integer
---@pre m >= 0 and m < 100 and n >= 0 and n < 100
---@post result == 0
---@return integer
---@decrease m, n
local function walk(m, n)
    if m == 0 then
        return 0
    end
    if n == 0 then
        return walk(m - 1, 10)
    end
    return walk(m, n - 1)
end

-- a call out of the cycle checks no measure: `tick`'s would fail, since 1000 isn't below `n`
---@param n integer
---@decrease 1000
local function tick(n) end

---@param n integer
---@pre n >= 0 and n < 1000
---@decrease n
local function ticks(n)
    if n == 0 then
        return
    end
    tick(n)
    ticks(n - 1)
end

-- a call from outside the cycle, and a measure on a function in no cycle, which nothing checks
---@param n integer
---@pre n >= 0 and n < 1000
---@return boolean
---@decrease n
local function both(n)
    return is_even(n) or is_odd(n)
end

-- the cycle through an `---@unsafe` body falls under its promise to terminate
---@unsafe
---@param n integer
---@pre n >= 0 and n < 1000
local function each(n)
    if n > 0 then
        visit(n - 1)
    end
end

---@param n integer
---@pre n >= 0 and n < 1000
function visit(n)
    each(n)
end

assert(drain(5) == 0)
assert(walk(3, 2) == 0)
ticks(3)
visit(3)

---@clavius end

-- values that the contracts don't state, checked when the program runs
assert(sum_to(4) == 10)
assert(is_even(10))
assert(not is_odd(10))
assert(both(7))
