-- Integer division is encoded, not called through a spec, yet it relies on glue leaving `math.floor`
-- alone, so the trust report says so even though the run uses no stdlib spec.
---@clavius begin
local half = math.floor(9 / 2)
assert(half == 4)
---@clavius end
