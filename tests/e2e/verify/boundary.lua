-- Unmarked callers are trusted to meet a verified function's `---@pre` and parameter types.

---@clavius
---@param n integer
---@pre n ~= 0
---@post result == 1 or result == -1
---@return integer
local function sign(n)
    if n > 0 then
        return 1
    end
    return -1
end

local s = sign(3) + sign(-2)
