-- A call that stays in its caller's cycle of recursive calls checks that the callee's measure at the
-- arguments is below the caller's on entry, lexicographically. An assigned parameter keeps its entry
-- value in a snapshot. A call from outside the cycle, or from a region's statements, checks no measure.
local odd
---@clavius begin
---@param n integer
---@pre n >= 0
---@decrease n, 1
---@return boolean
local function even(n)
    if n == 0 then
        return true
    end
    return odd(n)
end

---@param n integer
---@pre n > 0
---@decrease n, 0
---@return boolean
function odd(n)
    n = n - 1
    return not even(n)
end

-- a function that calls itself twice checks the measure at each call
---@param n integer
---@pre n >= 0
---@decrease n
---@return integer
local function fib(n)
    if n < 2 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

---@param n integer
---@pre n >= 0
---@return boolean
local function check(n)
    return even(n)
end

local x = check(4)
---@clavius end
