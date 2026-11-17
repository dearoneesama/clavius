-- An `---@unsafe` function that verified code calls is trusted to meet its contract, and so is every
-- caller outside verification of a verified function with parameters or a `---@pre`.
---@clavius begin

---@unsafe
---@param n integer
---@pre n >= 0
---@post result > n
---@return integer
local function bump(n)
    return n + 1
end

---@unsafe
local function unused() end

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

---@clavius end
