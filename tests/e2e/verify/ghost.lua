-- Spec functions define values that contracts and proof code use, lemmas prove facts about them, and
-- ghost code keeps what a proof needs. All of it is in comments, so LuaJIT never runs it.
---@clavius begin

--[[@spec
---@param n Nat
---@return Nat
---@decrease n
local function tri(n)
    if n == 0 then
        return 0
    end
    return tri(n - 1) + n
end

-- locals in a spec function's body, the second using the first
---@param n Nat
---@return Int
local function tri_twice(n)
    local t = tri(n)
    local d = t + t
    return d
end

---@param n Nat
---@return Nat
---@decrease n
local function pow2(n)
    if n == 0 then
        return 1
    end
    return 2 * pow2(n - 1)
end
]]

--[[@lemma
---@param n Nat
---@post tri(n + 1) == tri(n) + n + 1
local function lemma_tri_step(n) end

---@param n Nat
---@post tri_twice(n) == 2 * tri(n)
local function lemma_twice(n) end

-- by induction: the call is the hypothesis for n - 1
---@param n Nat
---@post tri(n) >= n
---@decrease n
local function lemma_tri_ge(n)
    if n > 0 then
        lemma_tri_ge(n - 1)
    end
end
]]

---@param n integer
---@pre n >= 0 and n <= 1000
---@post result == tri(n)
---@return integer
local function sum_to(n)
    local s = 0
    -- a ghost block declares into the function body; the loop doesn't write `start`, so it keeps its value
    --[[@ghost
        local seen = 0
        local start = s
    ]]
    ---@invariant s == tri(i - 1) and seen == i - 1 and 0 <= s and s <= 1000 * (i - 1)
    for i = 1, n do
        ---@proof lemma_tri_step(i - 1)
        s = s + i
        ---@ghost seen = seen + 1
    end
    ---@assert seen == n and start == 0
    return s
end

-- tri(3) unfolds four times, down to tri(0)
---@reveal_with_fuel tri, 4
---@post result == 6
---@return integer
local function six()
    return sum_to(3)
end

-- each spec function takes its own fuel
---@reveal_with_fuel tri, 4
---@reveal_with_fuel pow2, 3
---@post result == tri(3) + pow2(2)
---@return integer
local function ten()
    return 10
end

-- fuel for a spec function that isn't recursive is ignored, since it unfolds at every use
---@reveal_with_fuel tri_twice, 2
---@post result == tri_twice(0)
---@return integer
local function zero()
    return 0
end

-- a ghost loop in a proof block, and a lemma whose fact the body uses
---@param n integer
---@pre n >= 1 and n <= 100
---@post result >= n
---@return integer
local function at_least(n)
    --[[@proof
        local k = 0
        ---@invariant 0 <= k and k <= n
        ---@decrease n - k
        while k < n do
            k = k + 1
        end
        assert(k == n)
        lemma_tri_ge(n)
    ]]
    return sum_to(n)
end

assert(six() == 6)
assert(at_least(4) >= 4)

---@clavius end

-- a tag above a region's `begin` gives fuel to the unit of its statements and to its functions
---@reveal_with_fuel tri, 4
---@clavius begin

---@post result == tri(3)
---@return integer
local function six_again()
    return 6
end

---@assert tri(3) == 6

---@clavius end

-- a function's own tag wins over its region's
---@reveal_with_fuel tri, 2
---@clavius begin

---@reveal_with_fuel tri, 4
---@post result == tri(3)
---@return integer
local function six_more()
    return 6
end

---@clavius end
