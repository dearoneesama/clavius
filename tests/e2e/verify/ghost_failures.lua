-- Ghost code obligations that may fail.
---@clavius begin

--[[@spec
-- a `Nat` value that may be negative
---@param n Nat
---@return Nat
local function pred(n)
    return n - 1 --! nat
end

-- a measure that doesn't decrease leaves the definition circular
---@param n Nat
---@return Int
---@decrease n
local function circular(n)
    return circular(n) + 1 --! decrease
end

---@param n Nat
---@return Int
local function double(n)
    return n + n
end
]]

--[[@lemma
---@param n Nat
---@pre n > 2
---@post double(n) > 4
local function lemma_big(n) end

-- the body doesn't prove it
---@param n Nat
---@post double(n) > n
local function lemma_wrong(n) end --! post
]]

-- each failure in a function of its own, since the code after a failed check assumes it
---@param m integer
---@pre m >= 0 and m < 100
local function unmet(m)
    ---@proof lemma_big(m) --! pre
end

---@param m integer
---@pre m >= 0 and m < 100
local function negative(m)
    ---@proof lemma_big(m - 3) --! nat pre
end

---@param m integer
---@pre m >= 0 and m < 100
local function asserts(m)
    ---@assert double(m) == 2 * m
    ---@assert double(m) > m --! assert
end

-- an argument outside the parameter's type in a contract is unspecified, so this can't be proved
---@param n integer
---@pre n >= 0 and n < 100
---@post result == double(n - 1) + 2
---@return integer
local function shifted(n)
    return n + n --! post
end

-- a loop havocs the ghost locals it writes, and keeps only what the invariants say
---@param n integer
---@pre n >= 0 and n < 100
local function forgets(n)
    ---@ghost local seen = 0
    for i = 1, n do
        ---@ghost seen = seen + 1
    end
    ---@assert seen == n --! assert
end

---@clavius end
