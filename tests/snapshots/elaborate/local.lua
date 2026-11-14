-- Each local is a variable of the unit. A shadowing local is a new variable.
---@clavius begin
local x = 1
local a, b = x, true
local x = x + 1
---@clavius end
