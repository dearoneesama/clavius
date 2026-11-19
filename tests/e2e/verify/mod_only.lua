-- `%` is an operator, not a library call, so a run that uses it and nothing else trusts nothing.
---@clavius begin
local r = 9 % 4
assert(r == 1)
---@clavius end
