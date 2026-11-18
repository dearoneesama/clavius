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

assert(count(4) == 4)
assert(half(9) <= 9)

---@clavius end
