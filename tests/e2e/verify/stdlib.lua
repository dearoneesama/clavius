-- Calls of the shipped specs for math.min, math.max and math.abs. The program verifies and runs on
-- LuaJIT.
---@clavius begin
local big = 9007199254740992
assert(math.min(3, -4) == -4 and math.max(3, -4) == 3)
assert(math.min(-big, big) == -big and math.max(-big, big) == big)
assert(math.abs(-big) == big and math.abs(big) == big and math.abs(0) == 0)
local m = math.min(1, 2)
math.max(m, 3)
---@clavius end

---@clavius
---@param lo integer
---@param hi integer
---@param x integer
---@pre lo <= hi
---@post lo <= result and result <= hi
---@return integer
local function clamp(lo, hi, x)
    return math.max(lo, math.min(hi, x))
end

---@clavius
---@param a integer
---@param b integer
---@post result >= 0
---@return integer
local function distance(a, b)
    -- a - b may leave ±2^53, so it is bounded first
    local d = math.max(-4503599627370496, math.min(4503599627370496, a)) - math.max(-4503599627370496, math.min(4503599627370496, b))
    return math.abs(d)
end

---@clavius begin
-- the contracts promise bounds only
local c = clamp(0, 10, 11)
assert(0 <= c and c <= 10 and distance(-3, 4) >= 0)
---@clavius end
