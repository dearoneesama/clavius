-- A library alias, a top-level local of unmarked code initialized with a library function and never
-- assigned, is called like the function it names, and `floor(a / b)` is still integer division
-- (gap review, item 16). The program verifies and runs on LuaJIT.
local floor = math.floor
local min, max = math.min, math.max

---@clavius
---@param a integer
---@param b integer
---@pre 0 <= a and b > 0
---@post 0 <= result and result <= a
---@return integer
local function share(a, b)
    return max(0, min(a, floor(a / b)))
end

---@clavius begin
assert(floor(-7 / 2) == -4)
local s = share(9, 2)
assert(0 <= s and s <= 9)
---@clavius end
