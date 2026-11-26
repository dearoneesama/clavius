-- What a library alias can't be.
local floor = math.floor
local abs = math.abs
local bad = math.min
bad = math.max
local host_f = host.f

---@clavius begin
local x = floor(5) --! E-unsupported-call
local y = bad(1, 2) --! E-unsupported-feature
local g = abs --! E-unsupported-feature
local z = host_f(1) --! E-unsupported-feature
---@clavius end
