--[[@spec
---@param n Nat
---@return Int
local function twice(n)
    local m = n + n --! E-unsupported-feature
    return n + n
end
]]
