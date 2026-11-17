-- An `---@unsafe` function is trusted to meet its contract, so its callers can rely on it.

---@unsafe
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function bump(n)
    -- unmarked code, which may use all of Lua
    local t = { n }
    return t[1] + 1
end

---@clavius begin
local a = bump(5)
assert(a > 5)
---@clavius end
