-- Contracts that may break: at a return, at the end of a function, and at calls to verified and
-- `---@unsafe` functions, from a region or from another function.

---@clavius
---@param x integer
---@post result > x
---@return integer
local function wrong(x)
    return x --! post
end

---@clavius
---@param a int53
---@param b int53
---@param c int53
---@post result >= a and result >= b and result >= c
---@return int53
local function max3_buggy(a, b, c)
    if a > b and a > c then
        return a
    elseif b < c then
        return b --! post
    end
    return c --! post
end

-- without a `---@return`, the `---@post`s are checked where the body ends
---@clavius
---@param n integer
---@post n < 0
local function settle(n) end --! post

---@clavius
---@param x integer
---@return integer
local function partial(x) --! missing_return
    if x > 0 then
        return 1
    end
end

---@clavius
---@param n integer
---@pre n >= 0 and n < 100
---@return integer
local function inc(n)
    return n + 1
end

---@clavius
---@param n integer
---@return integer
local function unchecked(n)
    return inc(n) --! pre
end

---@unsafe
---@param n integer
---@pre n >= 0
local function log(n) end

---@clavius begin
local c = inc(-1) --! pre
---@clavius end

-- a region of its own, since a check that can't hold makes the code after it unreachable
---@clavius begin
log(-1) --! pre
---@clavius end
