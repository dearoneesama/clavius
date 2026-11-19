-- a contract may not call a library function, since it is spec code
---@clavius
---@param a integer
---@pre math.min(a, 0) < 0 --! E-unsupported-feature
local function f(a) end
