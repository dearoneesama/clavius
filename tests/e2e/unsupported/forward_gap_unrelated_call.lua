-- `other` can't reach `g`, but only definitions may sit between `local g` and its definition
---@clavius begin
---@param n integer
local function other(n)
    assert(n == n)
end
local g
---@param n integer
local function f(n)
    g(n) --! E-unsupported-feature
end
other(1)
---@param n integer
function g(n) end
---@clavius end
