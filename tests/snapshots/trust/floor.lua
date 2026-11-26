-- Integer division uses no spec, yet the run assumes that nothing outside verification replaces
-- `math.floor`.
---@clavius begin
local half = math.floor(9 / 2)
---@clavius end
