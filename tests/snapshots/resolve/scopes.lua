-- Each local gets a unique name, and each name refers to the nearest local before it.
local x = 1
local x = x + 1
do
    local x = x
    local y = x
end
local function f(n)
    return f(n - 1) + x
end
local g = function(n)
    return g
end
for i = x, 10 do
    local i = i
end
for k, v in pairs({}) do
    print(k, v, f, g)
end
repeat
    local r = 1
until r
---@clavius begin
local a = 1
do
    local a = a + 1
end
a = a + 1
---@clavius end
print(a, y)
