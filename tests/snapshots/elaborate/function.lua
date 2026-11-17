-- A function is a unit of its own. It assumes its parameters' types and its `---@pre`s on entry, and
-- checks its `---@post`s at each return against the parameters' entry values. A function with a
-- `---@return` must not reach its end; one without checks its `---@post`s there too.
---@clavius
---@param n integer
---@param on boolean
---@pre n > 0
---@post result >= n
---@return integer
local function f(n, on)
    if on then
        n = n + 1
        return n
    elseif n > 10 then
        return n * 2
    else
        do
            if n == 1 then
                return 1
            end
        end
    end
    return n
end

---@clavius
---@param n integer
---@pre n > 0
---@post n > 0
local function g(n)
    if n > 5 then
        return
    end
    n = n - 1
end

-- a call in a function checks the callee's `---@pre`s and assumes its `---@post`s, as anywhere else
---@clavius
---@param n integer
---@pre n > 0 and n < 10
---@post result >= n
---@return integer
local function h(n)
    if n > 5 then
       return f(n, false)
    end
        return f(n, true) + f(n, false)
end
