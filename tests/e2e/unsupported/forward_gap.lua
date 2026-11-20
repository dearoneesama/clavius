local g
---@clavius
---@param n integer
local function f(n)
    g(n) --! E-unsupported-feature
end
f(1)
---@clavius
---@param n integer
function g(n) end
