-- A call checks the callee's `---@pre`s on its arguments, then assumes its value's type and the
-- callee's `---@post`s: proved for a verified callee, trusted for an `---@unsafe` one. An `---@unsafe`
-- function in a region is no unit of its own, and its body is unmarked code.
---@clavius
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function inc(n)
    return n + 1
end

---@unsafe
---@param flag boolean
---@post flag
local function trusted(flag) end

-- a boolean value and no `---@post`: the call assumes `true`, so the trust report lists the callee
---@unsafe
---@return boolean
local function ready()
    return true
end

---@clavius begin

---@unsafe
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function bump(n)
    pcall(print, n)
    return n + 1
end

local x = inc(inc(1))
trusted(x > 1)
local y = bump(x)
local z = ready()
---@clavius end
