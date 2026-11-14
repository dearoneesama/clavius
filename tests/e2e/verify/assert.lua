-- `assert` must hold, and the code after it may rely on it.
---@clavius begin
local x = 3
assert(x > 2)
assert(x == 3, 'x is 3')
---@clavius end
---@clavius begin
local y = 3
assert(y > 3, 'y is small') --! assert
assert(y > 4) -- holds given the assert above
---@clavius end
