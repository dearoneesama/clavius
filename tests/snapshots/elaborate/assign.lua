-- A multiple assignment evaluates every value before it assigns any target.
---@clavius begin
local a, b = 1, 2
a = a + b
a, b = b, a
---@clavius end
