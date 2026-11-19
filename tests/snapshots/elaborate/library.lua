-- A call of a library function lowers its shipped spec like an `---@unsafe` callee's contract: the
-- arguments meet its `---@pre`s, and its value's type and `---@post`s are trusted, naming the spec.
---@clavius begin
local x = math.max(math.abs(-3), 2)
---@clavius end
