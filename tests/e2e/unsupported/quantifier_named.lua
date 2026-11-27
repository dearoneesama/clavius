-- A quantifier over a spec function passed by name
---@clavius begin
--[[@spec
---@param i Int
---@return boolean
local function p(i)
    return i == i
end
]]
---@assert forall(p) --! E-unsupported-feature
---@clavius end
