-- The flags of trusted code belong on an `---@unsafe` function, not on a verified one.
---@clavius
---@no_callback
--! E-misplaced-directive
local function f() end
