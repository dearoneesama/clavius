---@meta math

-- Trusted specs for the `math` functions that verified code may call. Clavius reads this file as text
-- and never runs it.

--- The smaller of two integers.
---@param x integer
---@param y integer
---@return integer
---@post result <= x and result <= y
---@post result == x or result == y
function math.min(x, y) end

--- The larger of two integers.
---@param x integer
---@param y integer
---@return integer
---@post result >= x and result >= y
---@post result == x or result == y
function math.max(x, y) end

--- The absolute value of an integer. Even `math.abs(-2^53)` is an `int53`.
---@param x integer
---@return integer
---@post result >= 0
---@post result == x or result == -x
function math.abs(x) end
