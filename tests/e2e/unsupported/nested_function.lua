---@clavius begin
local function f()
    local function g() end --! E-unsupported-feature
end
---@clavius end
