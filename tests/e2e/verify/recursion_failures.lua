-- Recursive calls that may not decrease the measure.
local pong

---@clavius begin

---@param n integer
---@decrease n
local function same(n)
    same(n) --! decrease
end

-- the measure must be non-negative where the call recurses
---@param n integer
---@pre n > -100 and n < 100
---@decrease n
local function below_zero(n)
    if n == 0 then
        return
    end
    below_zero(n - 1) --! decrease pre
end

-- the measure on entry counts, not the parameter's value at the call
---@param n integer
---@pre n >= 0 and n < 100
---@decrease n
local function bump(n)
    if n == 0 then
        return
    end
    n = n + 1
    bump(n - 1) --! decrease
end

---@param n integer
---@pre n >= 0 and n < 100
---@decrease n
local function ping(n)
    pong(n) --! decrease
end

---@param n integer
---@pre n >= 0 and n < 100
---@decrease n
function pong(n)
    ping(n) --! decrease
end

-- an earlier expression of the measure may not grow, even when a later one decreases
---@param m integer
---@param n integer
---@pre m >= 0 and m < 100 and n >= 0 and n < 100
---@decrease n, m
local function earlier(m, n)
    if m == 0 or n == 99 then
        return
    end
    earlier(m - 1, n + 1) --! decrease
end

---@clavius end
