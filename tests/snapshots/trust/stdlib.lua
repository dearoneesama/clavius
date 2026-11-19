-- Each shipped spec that verified code calls is listed with the Clavius version that shipped it, and the
-- run assumes that glue replaces no library function.
---@clavius begin
local x = math.max(math.min(1, 2), 0)
local y = math.min(x, 3)
---@clavius end
