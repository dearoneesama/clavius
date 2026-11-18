-- A loop writes the locals that its body assigns and that are declared outside it, in the order of
-- their first writes. A local written twice is listed once. An inner loop's writes are its outer loop's
-- too, unless the local is declared in the outer loop. Loops in unmarked code have no writes.
---@clavius
---@param n integer
---@pre n >= 0 and n < 100
local function f(n)
    local sum = 0
    local count = 0
    local untouched = 1
    ---@decrease n
    while n > 0 do
        local step = 1
        if n > 5 then
            step = 2
            sum = sum + 1
        end
        ---@decrease step
        while step > 0 do
            count = count + 1
            step = step - 1
        end
        sum = sum + step
        n = n - 1
    end
    for i = 1, 3 do
        local j = i
        j = j + 1
    end
end

local y = 0
while y < 3 do
    y = y + 1
end

---@clavius begin
local x = 0
---@decrease 10 - x
repeat
    x = x + 1
until x >= 10
---@clavius end
