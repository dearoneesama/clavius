-- Every kind of node that parsing produces. The string and this comment are not ASCII: 'é你好'.
local s, n, t, f, z = 'é你好', 0x1F, true, false, nil
local tbl = { 1, 2.5, k = "v", ["x y"] = 1LL, [n] = {} }
local function fact(k)
    if k <= 1 then
        return 1
    elseif k == 2 then
        return 2
    else
        return k * fact(k - 1)
    end
end
function tbl.add(a, b, ...)
    return a + b, ...
end
function tbl:len()
    return #self
end
tbl.x, tbl[1] = -n, not t
print(tbl:len(), s:sub(1, 2), (fact(3)), s .. 'x', 2 ^ 3 % 2 / 1, t and f or z, 1 ~= 2, 1 < 2 and 1 <= 2 and 1 > 2 and 1 >= 2)
do
    local i = 0
    while i < 3 do
        i = i + 1
        if i == 2 then
            break
        end
    end
    repeat
        local j = i
    until j > 0
end
for i = 1, 3 do
    print(i)
end
for i = 3, 1, -1 do
    goto continue
    ::continue::
end
for k, v in pairs(tbl) do
    print(k, v)
end
print(tbl.add(1, 2, 3), tostring "s", type { 1 })
---@clavius begin
local m = 1 - 2
---@clavius end
return tbl
