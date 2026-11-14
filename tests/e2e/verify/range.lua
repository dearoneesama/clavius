-- Every +, - and * stays within ±2^53, bounds included. Each region is checked on its own.
---@clavius begin
local big = 9007199254740992
local a = big - 1 + 1
local b = -big + 0
local c = 4503599627370496 * 2
local d = -4503599627370496 * 2
assert(a == big and b == -big and c == big and d == -big)
---@clavius end
---@clavius begin
local big = 9007199254740992
local e = big + 1 --! range
---@clavius end
---@clavius begin
local f = -9007199254740992 - 1 --! range
---@clavius end
---@clavius begin
local g = 4503599627370497 * 2 --! range
---@clavius end
