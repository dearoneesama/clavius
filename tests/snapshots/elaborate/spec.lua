-- Spec and lemma blocks outside a region, the forms a spec function's body takes, and a lemma with an
-- `integer` parameter.

-- an `if` with an `else` is an `Ite`, and a `do` block is what it holds
--[[@spec
---@param n Int
---@return Int
local function sign(n)
    if n > 0 then
        return 1
    else
        do
            return 0
        end
    end
end
]]

-- a `local` is a `Let` around the rest of its block, and each `elseif` is one more `Ite`
--[[@spec
---@param n Int
---@return Int
local function clamp(n)
    local lo = 0
    if n < lo then
        return lo
    elseif n > 10 then
        local hi = 10
        return hi
    else
        local m = n
        return m
    end
end
]]

-- a call with an `Int` checks that it fits the `integer`
--[[@lemma
---@param k integer
---@post sign(k) >= 0
local function nonneg(k) end
]]

---@clavius begin
---@ghost local g = 2
---@proof nonneg(g)
---@clavius end
