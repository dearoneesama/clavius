-- Integer division, `math.floor(a / b)`, and `%` with Lua's floored semantics. The program verifies, and
-- running it on LuaJIT checks every assertion again, so Clavius's encoding and LuaJIT agree on these.
---@clavius begin
-- floored, not truncated, and not Euclidean: they differ when the signs do
assert(math.floor(7 / 3) == 2 and 7 % 3 == 1)
assert(math.floor(-7 / 3) == -3 and -7 % 3 == 2)
assert(math.floor(7 / -3) == -3 and 7 % -3 == -2)
assert(math.floor(-7 / -3) == 2 and -7 % -3 == -1)
assert(math.floor(6 / -3) == -2 and 6 % -3 == 0)
assert(math.floor(0 / -5) == 0 and 0 % -5 == 0)
-- the edges of int53
local big = 9007199254740992
assert(math.floor(big / 1) == big and math.floor(-big / -1) == big)
assert(math.floor(big / 3) == 3002399751580330 and math.floor(-big / 3) == -3002399751580331)
assert(math.floor((big - 1) / 2) == 4503599627370495)
assert(big % 3 == 2 and (big - 1) % 7 == 3)
assert(-big % big == 0 and (big - 1) % -big == -1)
-- parentheses around the quotient keep the form
assert(math.floor((big) / ((3))) == 3002399751580330)
---@clavius end

---@clavius
---@param x integer
---@param n integer
---@pre 0 <= x and 0 < n
---@post 0 <= result and result < n
---@return integer
local function wrap(x, n)
    return x % n
end

---@clavius
---@param a integer
---@param b integer
---@pre b ~= 0
---@return integer
local function quotient(a, b)
    return math.floor(a / b)
end

-- `%` and integer division are exact in contracts, which are spec code
---@clavius
---@param a integer
---@param b integer
---@pre b > 0
---@post result * b + a % b == a
---@post math.floor(a / b) == result
---@return integer
local function div(a, b)
    return math.floor(a / b)
end

---@clavius begin
-- a ring index, counting down from 1 wraps to n
---@param i integer
---@param n integer
---@pre 1 <= i and i <= n
---@post 1 <= result and result <= n
---@return integer
local function prev(i, n)
    return (i - 2) % n + 1
end
-- callers know only what the contract says
local p = prev(1, 5)
assert(1 <= p and p <= 5)
---@clavius end

---@clavius begin
local w = wrap(7, 3)
assert(0 <= w and w < 3)
local q = quotient(-9, 4)
-- div's contract pins its value down
assert(div(-9, 4) == -3)
---@clavius end
