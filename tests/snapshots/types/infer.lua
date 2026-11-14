-- Literals give int53 and boolean, operators combine them, and locals take their initializer's type.
---@clavius begin
local n = 0x10
local b = n < 2 and not (n == 3)
local m = -(n * 2) + 9007199254740992
local c, d = b == true, m ~= 0
c, n = d, n - 1
if c then
    assert(c, 'message')
else
    error('unreachable', 2)
end
---@clavius end
