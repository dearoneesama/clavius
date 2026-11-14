-- `elseif` arms nest in the else branch. A condition's checks come before its branch.
---@clavius begin
local x = 1
if x > 0 then
    x = x - 1
elseif x + 1 > 0 then
    do
        local y = x
        x = y
    end
else
    x = 0
end
if x == 0 then
    x = 1
end
---@clavius end
