-- `error` must be unreachable.
---@clavius begin
local x = 3
if x < 0 then
    error('negative')
end
---@clavius end
---@clavius begin
local y = 3
if y > 0 then
    error('positive', 2) --! unreachable
end
---@clavius end
