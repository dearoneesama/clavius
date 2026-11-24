-- Each region with statements is one unit. Unmarked code between regions is not verified. A
-- `---@proof_by nonlinear_arith` right above a region's `begin` makes its unit nonlinear.
local before = 1
---@clavius begin
local x = 1
---@clavius end
print(before + x)
---@clavius begin
---@clavius end
---@clavius begin
local main = 2
assert(main == 2)
---@clavius end
---@proof_by nonlinear_arith
---@clavius begin
local y = x * main
---@clavius end
