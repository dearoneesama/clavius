-- Quantifiers in each place spec code goes, with the trigger each gets.
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

---@param i Int
---@return boolean
local function p(i)
    return i > 0
end

-- in a spec function's body, the quantifier is part of its definition axiom
---@param n Int
---@return boolean
local function p_upto(n)
    return forall(function(i) return implies(0 <= i and i < n, p(i)) end)
end
]]

-- a local of the body is a Let in the body, and its value in the trigger
---@param n integer
---@pre n >= 0 and n <= 100
---@pre forall(function(i, j) local d = tri(i) return implies(i <= j, d <= tri(j)) end)
---@post exists(function(i) return tri(i) == tri(n) end)
local function at(n)
    local k = 0
    ---@invariant 0 <= k and k <= n
    ---@invariant forall(function(i) return implies(0 <= i and i < k, p(i)) end)
    ---@decrease n - k
    while k < n do
        ---@assume p(k)
        k = k + 1
    end
    -- the check of `tri`'s argument runs only where `implies` needs its value
    --[[@proof
        local m = k - 5
        assert(implies(m >= 0, tri(m) >= 0))
        assert(forall(function(i)
            return forall(function(j)
                return implies(p(i) and i < j, p(j))
            end)
        end))
        -- a marked term is the trigger, and the mark is the term itself
        assert(forall(function(i) return implies(p(i), trigger(tri(i)) >= 0) end))
    ]]
end
---@clavius end
