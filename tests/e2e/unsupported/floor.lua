-- `math.floor` is supported only as integer division, `math.floor(a / b)`
---@clavius begin
local x = math.floor(5) --! E-unsupported-call
---@clavius end
