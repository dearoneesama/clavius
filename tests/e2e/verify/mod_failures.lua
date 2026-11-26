-- The checks of `%` and integer division.
---@clavius begin
local zero = 0
local x = 5 % zero --! div_zero
---@clavius end
---@clavius begin
local y = math.floor(5 / 0) --! div_zero
---@clavius end

-- `2^53 % -3` is -1 when floored, but LuaJIT computes `a - math.floor(a / b) * b` in doubles, and the
-- product -2^53 - 1 rounds, so it gives 0. Its dividend minus its remainder leaves ±2^53.
---@clavius begin
local big = 9007199254740992
local r = big % -3 --! mod_range
---@clavius end

-- with a negative x, x minus the remainder can be -2^53 - 1
---@clavius
---@param x integer
---@param n integer
---@pre 0 < n
---@return integer
local function wrap(x, n)
    return x % n --! mod_range
end

---@clavius
---@param a integer
---@param b integer
---@return integer
local function quotient(a, b)
    return math.floor(a / b) --! div_zero
end

-- a contract may divide by 0: spec operations are total, with an unspecified value outside their domain
---@clavius
---@param a integer
---@post result == a % 0
---@return integer
local function unspecified(a)
    return a --! post
end
