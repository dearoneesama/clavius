-- Ghost code lowers like exec code, but its arithmetic is exact, so it has no range checks, and a ghost
-- `for` loop has no `for_bound`. An `---@assert` is a Check of its condition.
---@clavius begin
local x = 2
local y = x * x
---@ghost local g = x * x
--[[@proof
    local s = 0
    ---@invariant s >= 0
    for i = 1, g do
        s = s + i
    end
]]
---@assert g == 4
---@clavius end
