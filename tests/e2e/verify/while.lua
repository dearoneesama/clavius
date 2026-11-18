-- A `while` loop checks its invariants on entry and after each iteration, and its measure on each
-- iteration that iterates again. The code after it sees the invariants and the negated condition.
---@clavius begin

---@param n integer
---@pre n >= 0 and n < 1000
---@post result == n
---@return integer
local function count(n)
    local i = 0
    ---@invariant 0 <= i and i <= n
    ---@decrease n - i
    while i < n do
        i = i + 1
    end
    return i
end

---@param n integer
---@pre n >= 0 and n < 1000
---@post result == 2 * n
---@return integer
local function double(n)
    local i = 0
    local sum = 0
    ---@invariant 0 <= i and i <= n
    ---@invariant sum == 2 * i
    ---@decrease n - i
    while i < n do
        sum = sum + 2
        i = i + 1
    end
    return sum
end

-- a parameter that the loop counts down; `---@post` still means its value on entry
---@param n integer
---@pre n >= 0 and n < 1000
---@post result == 0 and n >= 0
---@return integer
local function drain(n)
    ---@invariant n >= 0
    ---@decrease n
    while n > 0 do
        n = n - 1
    end
    return n
end

-- the last step may overshoot the measure's bound
---@param n integer
---@pre n >= 0 and n < 1000
---@post result >= n
---@return integer
local function evens(n)
    local i = 0
    ---@invariant i >= 0
    ---@decrease n - i
    while i < n do
        i = i + 2
    end
    return i
end

-- `break` leaves with the state it has; the invariant isn't checked there
---@param n integer
---@pre n >= 0 and n < 1000
---@post result <= n
---@return integer
local function root(n)
    local i = 0
    ---@invariant 0 <= i and i <= n
    ---@decrease n - i
    while i < n do
        if i * i >= n then
            break
        end
        i = i + 1
    end
    return i
end

-- a loop havocs only the locals it writes, so facts about the others carry through it
---@param n integer
---@param k integer
---@pre n >= 0 and n < 1000 and k > 5
---@post result >= n
---@return integer
local function frame(n, k)
    local fixed = 7
    local i = 0
    ---@decrease n - i
    while i < n do
        i = i + 1
    end
    assert(fixed == 7)
    assert(k > 5)
    assert(i >= n)
    return i
end

-- a loop that only `break` ends, and calls in a loop
---@param tries integer
---@pre tries > 0 and tries < 100
---@post result == 0
---@return integer
local function retry(tries)
    ---@invariant tries > 0 and tries < 100
    ---@decrease tries
    while true do
        tries = count(tries - 1)
        if tries <= 0 then
            break
        end
    end
    return tries
end

assert(count(5) == 5)
assert(double(4) == 8)
assert(drain(3) == 0)
assert(evens(5) >= 5)
assert(root(10) <= 10)
assert(frame(3, 6) >= 3)
assert(retry(3) == 0)

-- loops at the top level of a region, one inside the other
local k = 0
local total = 0
---@invariant total == 3 * k
---@decrease 5 - k
while k < 5 do
    local j = 0
    ---@invariant 0 <= j and j <= 3
    ---@invariant total == 3 * k + j
    ---@decrease 3 - j
    while j < 3 do
        total = total + 1
        j = j + 1
    end
    k = k + 1
end
assert(k >= 5)
assert(total == 3 * k)

---@clavius end
