-- Every +, - and * gets a range check, in evaluation order. Negation needs none.
---@clavius begin
local x = 0x7F
local y = -x * (x - 2) + -3
local z = -(y + 1)
---@clavius end
