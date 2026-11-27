-- A `forall` call as a statement of proof code
---@clavius begin
--[[@spec
---@param i Int
---@return boolean
local function p(i)
    return i == i
end
]]
--[[@proof
    forall(function(i) return p(i) end) --! E-unsupported-feature
]]
---@clavius end
