---@clavius begin
local x = 1
local y = 1
---@decrease x, y
--! E-unsupported-feature
while x < 2 do x = x + 1 end
---@clavius end
