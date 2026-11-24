-- An `---@assume` is a fact that nothing proves. The code after it relies on it, and the trust report
-- lists it.
---@clavius begin

-- the `---@pre` allows 0, but the code after the assumption may rely on `n > 0`
---@param n integer
---@pre 0 <= n and n <= 100
---@post result > 0
---@return integer
local function positive(n)
    ---@assume n > 0
    return n
end

-- the code before it can't rely on it
---@param n integer
---@pre 0 <= n and n <= 100
local function too_early(n)
    ---@assert n > 0 --! assert
    ---@assume n > 0
end

-- in one branch, it drops that branch's paths, so the code after the `if` sees only `n <= 50`
---@param n integer
---@pre 0 <= n and n <= 100
---@post result <= 50
---@return integer
local function pruned(n)
    if n > 50 then
        ---@assume false
    end
    return n
end

-- a caller gets the `---@post`, which rests on the assumption
assert(positive(3) > 0)

---@clavius end
