-- `math.floor` is supported only as integer division, `math.floor(a / b)`; floats come with M18
---@clavius begin
local x = math.floor(5) --! E-unsupported-call
---@clavius end
