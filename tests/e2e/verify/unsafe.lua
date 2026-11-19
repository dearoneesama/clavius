-- An `---@unsafe` function is trusted to meet its contract, so its callers can rely on it. Its flags
-- are listed in the trust report.

---@unsafe
---@no_callback
---@may_raise
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function bump(n)
    -- unmarked code, which may use all of Lua
    local t = { n }
    return t[1] + 1
end

-- no `---@post` and a boolean value: the call assumes nothing of it, yet trusts it
---@unsafe
---@return boolean
local function ready()
    return true
end

---@clavius begin
local a = bump(5)
assert(a > 5)
local ok = ready()
---@clavius end
