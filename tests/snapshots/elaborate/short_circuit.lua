-- The right operand of `and` and `or` runs only when needed, so its checks go in a branch.
---@clavius begin
local x = 1
local p = x > 0 and x < 2 -- no checks
local q = x > 0 and x + 1 > 0
local r = x > 0 or x - 1 > 0
local s = not (p or q) -- no checks
---@clavius end
