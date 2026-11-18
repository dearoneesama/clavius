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

-- `break` leaves without the invariant, which the code after the loop doesn't see there
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

assert(count(3) == 3)
assert(down() == 11)
assert(steps() == 9)
assert(empty() == 0)
assert(once(4) == 4)
assert(first_square(10) <= 10)

---@clavius end
