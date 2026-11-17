-- Top-level locals that are literals and never assigned are constants. Marked code and contracts may
-- read them.
local LIMIT = 100
local FLOOR = -1
local ON = true

---@clavius
---@param n integer
---@pre n < LIMIT and n > FLOOR
---@post result <= LIMIT
---@return integer
local function bump(n)
    if ON then
        return n + 1
    end
    return n
end

---@clavius begin
local x = bump(LIMIT - 1)
assert(x <= LIMIT)
assert(x > LIMIT) --! assert
---@clavius end
