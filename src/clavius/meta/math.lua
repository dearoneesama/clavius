---@meta math

-- Trusted specs for the `math` functions that verified code may call. Clavius reads this file as text
-- and never runs it, since running it would replace the real functions with empty ones.
--
-- A spec is trusted without proof, so a wrong one makes Clavius unsound with no sign of it. Each
-- `---@pre` rules out every error that the function raises on arguments of its declared types, and each
-- `---@post` holds for every input that meets the `---@pre`s (design §10). `tests/unit/stdlib_test.lua`
-- calls each function on LuaJIT at the edges of its preconditions and checks both.
--
-- Only `int53` arguments are supported for now. Floats come with M18, and so does `math.floor` on its
-- own; `math.floor(a / b)` is integer division, which Clavius encodes itself (design §6).

--- The smaller of two integers. Lua's `math.min` takes one or more numbers; the spec takes exactly two
--- until varargs (M16). On two numbers it raises no error.
---@param x integer
---@param y integer
---@return integer
---@post result <= x and result <= y
---@post result == x or result == y
function math.min(x, y) end

--- The larger of two integers, as `math.min`.
---@param x integer
---@param y integer
---@return integer
---@post result >= x and result >= y
---@post result == x or result == y
function math.max(x, y) end

--- The absolute value of an integer. It raises no error on a number, and `math.abs(-2^53)` is `2^53`,
--- which is still an `int53`.
---@param x integer
---@return integer
---@post result >= 0
---@post result == x or result == -x
function math.abs(x) end
