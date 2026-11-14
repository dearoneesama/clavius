-- The right operand of `and` and `or`, with its checks, runs only when it is needed.
---@clavius begin
local big = 9007199254740992
local p = big < 0 and big + 1 > 0
local q = big > 0 or big + 1 > 0
assert(not p and q)
---@clavius end
---@clavius begin
local big = 9007199254740992
local r = big > 0 and big + 1 > 0 --! range
---@clavius end
