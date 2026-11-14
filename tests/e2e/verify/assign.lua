-- A multiple assignment evaluates every value first. A shadowing local is a new variable.
---@clavius begin
local a, b = 1, 2
a, b = b, a
assert(a == 2 and b == 1)
local main = a
do
    local main = main + 10
    a = main
end
assert(a == 12 and main == 2)
local p, q = true, false
p, q = q, p
assert(q and not p)
---@clavius end
