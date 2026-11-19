-- `%` and `math.floor(a / b)` have Lua's floored semantics, built from the core's Euclidean `div` and
-- `mod`: the two differ when the divisor is negative and the remainder isn't 0. Both check the
-- divisor, and `%` also that LuaJIT computes it exactly. In a contract they are exact and unchecked.
---@clavius
---@param a integer
---@param b integer
---@pre b > 0
---@post result == math.floor(a / b) + a % b
---@return integer
local function f(a, b)
    return math.floor(a / b) + a % b
end
