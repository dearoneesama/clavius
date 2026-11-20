-- Integer division uses no spec, yet the trust report lists that it relies on `math.floor` being left
-- alone.
---@clavius begin
local half = math.floor(9 / 2)
assert(half == 4)
---@clavius end
