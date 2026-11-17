---@clavius
---@param n integer
local function f(n) end
---@clavius begin
f(1, 2) --! E-unsupported-feature
---@clavius end
