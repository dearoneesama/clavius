-- Comparisons on int53, and equality on int53 and boolean.
---@clavius begin
local x = 1
local p = x < 2 and x <= 2 and x > 0 and x >= 0
local q = x == 1 and x ~= 2 and p == true and p ~= false
---@clavius end
