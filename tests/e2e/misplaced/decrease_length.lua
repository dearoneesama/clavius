local g
---@clavius begin
---@param n integer
---@decrease n, 1
local function f(n) g(n) end
---@param n integer
---@decrease n
--! E-misplaced-directive
function g(n) f(n) end
---@clavius end
