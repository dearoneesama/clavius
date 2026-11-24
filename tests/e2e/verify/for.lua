-- A numeric `for` evaluates its bounds once and runs only when its start is within its limit. Its
-- counter then goes from the start to the limit plus the step by whole steps, which the solver knows
-- without an invariant.
---@clavius begin

---@param n integer
---@pre n >= 0 and n < 1000
---@post result == n
---@return integer
local function count(n)
    local c = 0
    ---@invariant c == i - 1
    for i = 1, n do
        c = c + 1
    end
    return c
end

---@post result == 11
---@return integer
local function down()
    local c = 0
    ---@invariant c == 10 - i
    for i = 10, 0, -1 do
        c = c + 1
    end
    return c
end

-- whole steps: 1, 3, 5, 7, 9 and 10, 7, 4, 1
---@post result == 9
---@return integer
local function steps()
    local c = 0
    ---@invariant 2 * c == i - 1
    for i = 1, 9, 2 do
        c = c + 1
    end
    ---@invariant 3 * (c - 5) == 10 - i
    for i = 10, 1, -3 do
        c = c + 1
    end
    return c
end

-- parentheses and minus signs keep a literal step's sign known: the counter is only 9, 7, 5, 3 and 1
---@post result == 0
---@return integer
local function odd()
    local c = 0
    ---@invariant c == 0
    for i = 9, 1, -(-(-2)) do
        if i == 4 then
            c = 1
        end
    end
    return c
end

-- an empty loop checks no invariant
---@post result == 0
---@return integer
local function empty()
    local c = 0
    ---@invariant c == 1
    for i = 10, 0 do
        c = c + 1
    end
    ---@invariant c == 1
    for i = 0, 10, -1 do
        c = c + 1
    end
    return c
end

-- the limit is read once, before the body changes it
---@param n integer
---@pre n >= 0 and n < 1000
---@post result == n
---@return integer
local function once(n)
    local c = 0
    local limit = n
    ---@invariant c == i - 1
    ---@invariant limit == n - c
    for i = 1, limit do
        c = c + 1
        limit = limit - 1
    end
    return c
end

-- a variable step is checked to be nonzero, and the loop runs in its direction
---@param n integer
---@param s integer
---@pre n >= 0 and n < 1000 and s >= 1 and s <= 10
---@post result >= 0 and result <= n
---@return integer
local function by_step(n, s)
    local c = 0
    ---@invariant 0 <= c and c <= i - 1 and (c == 0 or c <= i - s)
    for i = 1, n, s do
        c = c + 1
    end
    return c
end

---@param s integer
---@pre s >= -10 and s <= -1
---@post result >= 1
---@return integer
local function down_by(s)
    local c = 0
    ---@invariant 0 <= c and c <= 10 - i and (i == 10 or c >= 1)
    for i = 10, 1, s do
        c = c + 1
    end
    return c
end

-- `break` leaves without the invariant, which the code after the loop doesn't see there. `i * i` is
-- a product of two variables, whose range needs nonlinear arithmetic
---@proof_by nonlinear_arith
---@param n integer
---@pre n >= 0 and n < 1000
---@post result >= 0 and result <= n
---@return integer
local function first_square(n)
    local found = 0
    ---@invariant found == 0
    for i = 0, n do
        if i * i >= n then
            found = i
            break
        end
    end
    return found
end

-- a measure list on a numeric `for` is checked like any other, though the counter already ends the loop
---@param n integer
---@pre n >= 0 and n < 1000
---@post result == n
---@return integer
local function measured(n)
    local c = 0
    ---@invariant c == i - 1
    ---@decrease n - i, c
    for i = 1, n do
        c = c + 1
    end
    return c
end

-- step's contract shows it isn't 0
---@post result == 2
---@return integer
local function all_are_calls()
    local r = measured(1)
    ---@invariant r == i
    for i = measured(1), measured(1), measured(1) do
        r = r + measured(i)
    end
    return measured(r)
end

assert(count(3) == 3)
assert(measured(3) == 3)
assert(down() == 11)
assert(steps() == 9)
assert(odd() == 0)
assert(empty() == 0)
assert(once(4) == 4)
assert(by_step(10, 3) <= 10)
assert(down_by(-3) >= 1)
assert(first_square(10) <= 10)
assert(all_are_calls() == 2)

---@clavius end
