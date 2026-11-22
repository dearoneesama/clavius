-- A loop checks its invariants on entry, then runs in a Block that `break` exits. Its head havocs what it
-- writes and assumes their types and the invariants, and an iteration that iterates again checks the
-- invariants and the measure and ends. A numeric `for` runs under its guard, with its counter's range
-- as a generated invariant. A step that isn't a literal is checked to be nonzero, and the guard, the
-- condition and the range split on its sign.
---@clavius begin

---@param n integer
---@pre n >= 0 and n < 100
---@post result == n
---@return integer
local function f(n)
    local i = 0
    local s = 0
    ---@invariant i <= n
    ---@decrease n - i
    while i < n do
        if s > 50 then
            break
        end
        i = i + 1
    end
    ---@decrease n - i
    repeat
        local j = i + 1
        i = j
    until j >= n
    ---@invariant s >= 0
    for k = n, 1, -2 do
        s = s + k
    end
    return i
end

---@param n integer
---@param d integer
---@pre n >= 0 and n < 100 and d >= -3 and d <= 3
local function g(n, d)
    for k = 1, n, d do
    end
end

---@clavius end
