-- A `repeat` loop runs its body before it tests the condition, which sees the body's locals. Its
-- invariants and its measure hold at the top of each iteration, where the body's locals don't exist.
---@clavius begin

---@param n integer
---@pre n >= 1 and n < 1000
---@post result == n
---@return integer
local function count(n)
    local i = 0
    ---@invariant 0 <= i and i < n
    ---@decrease n - i
    repeat
        local next = i + 1
        i = next
    until next >= n
    return i
end

-- `break` in a `repeat` leaves past its condition
---@param n integer
---@pre n >= 1 and n < 1000
---@post result <= n
---@return integer
local function half(n)
    local i = 0
    ---@invariant 0 <= i and i < n
    ---@decrease n - i
    repeat
        if 2 * i >= n then
            break
        end
        i = i + 1
    until i >= n
    return i
end

-- a measure of three expressions: each branch decreases a different one, and the ones after it may grow
---@post result == 2
---@return integer
local function odometer()
    local a = 0
    local b = 0
    local c = 0
    ---@invariant 0 <= a and a < 2 and 0 <= b and b <= 2 and 0 <= c and c <= 2
    ---@decrease 2 - a, 2 - b, 2 - c
    repeat
        if c < 2 then
            c = c + 1
        elseif b < 2 then
            b = b + 1
            c = 0
        else
            a = a + 1
            b = 0
            c = 0
        end
    until a == 2
    return a
end

assert(count(4) == 4)
assert(half(9) <= 9)
assert(odometer() == 2)

---@clavius end
