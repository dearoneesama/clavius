-- `assert` checks its condition. `error` must be unreachable.
---@clavius begin
local x = 1
assert(x == 1)
assert(x + 1 == 2, 'message')
if x > 1 then
    error('message', 2)
end
error()
---@clavius end
