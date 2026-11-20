-- A measure of several expressions decreases in the lexicographic order: at some position the
-- expression was non-negative and is now smaller, and every expression before it is unchanged.
---@clavius begin
local i = 0
local j = 0
---@invariant 0 <= i and i <= 3 and 0 <= j and j <= 3
---@decrease 3 - i, 3 - j
while i < 3 do
    if j < 3 then
        j = j + 1
    else
        i = i + 1
        j = 0
    end
end
-- three expressions, with constants around the one that decreases
local k = 0
---@decrease 1, 3 - k, 0
while k < 3 do
    k = k + 1
end
---@clavius end
