---@ghost local g = 0
--! E-misplaced-directive
local function f()
    --[[@proof assert(true) ]] --! E-misplaced-directive
    ---@assert true
    --! E-misplaced-directive
end
return f
