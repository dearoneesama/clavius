---@unsafe
local function hook() end
---@clavius begin
hook() --! E-unsupported-feature
---@clavius end
hook = function() end
