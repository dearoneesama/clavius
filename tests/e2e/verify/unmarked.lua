-- A file without markers isn't checked, so it may use all of Lua.
local t = { 1, 2 }
local s = 0
for _, v in ipairs(t) do
    s = s + v / 2
end
assert(s == 1.5)
