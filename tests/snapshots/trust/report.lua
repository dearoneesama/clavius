-- An `---@unsafe` function or a host function that verified code calls is trusted to meet its contract,
-- and so is every caller outside verification of a verified function with parameters or a `---@pre`.
-- A trusted function is listed with its flags, and `%` trusts nothing, since it is an operator.
---@clavius begin

---@unsafe
---@no_callback
---@may_raise
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function bump(n)
    return n + 1
end

---@unsafe
local function unused() end

-- no `---@post` and a boolean value: the call assumes nothing of it, yet trusts it
---@unsafe
---@return boolean
local function ready()
    return true
end

---@param a integer
---@param b integer
---@post result >= a and result >= b
---@return integer
local function max(a, b)
    if a > b then
        return a
    end
    return b
end

local function idle() end

local x = bump(max(1, 2))
local ok = ready()
host.log(host.scale(x % 3) + frame())

---@clavius end
