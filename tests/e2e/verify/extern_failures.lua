-- A host function's `---@pre` is checked at each call, and only its `---@post` is known of its value.
---@clavius begin
local a = host.damage(-1, 0) --! pre
---@clavius end
---@clavius begin
local b = host.damage(10, 3)
assert(b == 7) --! assert
---@clavius end
