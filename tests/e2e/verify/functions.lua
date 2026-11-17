-- Contracts that hold where each function returns and where it is called.
---@clavius begin

---@param n integer
---@pre n >= 0 and n < 100
---@post result == n + 1
---@return integer
local function inc(n)
    return n + 1
end

---@param a integer
---@param b integer
---@post best >= a and best >= b
---@return integer best
local function max2(a, b)
    if a > b then
        return a
    end
    return b
end

-- a verified function relies on its callees' contracts too, and a marker in a region is redundant
---@clavius
---@param a integer
---@param b integer
---@param c integer
---@post result >= a and result >= b and result >= c
---@return integer
local function max3(a, b, c)
    return max2(max2(a, b), c)
end

---@param n integer
---@pre n >= 0 and n < 50
---@post result == n + 2
---@return integer
local function inc2(n)
    return inc(inc(n))
end

-- a parameter in `---@post` means its value on entry, and contract arithmetic is exact
---@param n int53
---@pre n > 0 and n < 1000
---@post result == n * 2
---@return int53
local function double(n)
    n = n + n
    return n
end

---@param n int53
---@pre n > 0
---@post n > 0
local function keep(n) end

local a = inc(1)
assert(a == 2)
local b = max2(a, 7)
assert(b >= 7)
assert(max3(1, 9, 4) >= 9)
assert(inc2(3) == 5)
assert(double(3) == 6)
keep(1)
---@clavius end
