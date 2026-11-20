-- the shipped `math.min` takes exactly two arguments
---@clavius begin
local x = math.min(1, 2, 3) --! E-unsupported-feature
---@clavius end
