-- An `elseif` condition runs only when the arms before it don't.
---@clavius begin
local x = 5
local kind = 0
if x < 0 then
    kind = 1
elseif x == 0 then
    kind = 2
elseif x < 10 then
    kind = 3
else
    kind = 4
end
assert(kind == 3)
---@clavius end
---@clavius begin
local big = 9007199254740992
if big > 0 then
    big = big - 1
elseif big + 1 > 0 then
    big = 0
end
assert(big == 9007199254740991)
---@clavius end
---@clavius begin
local n = 1
if n > 0 then
    n = n + 1
end
assert(n == 1) --! assert
---@clavius end
