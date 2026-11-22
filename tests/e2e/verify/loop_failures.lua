-- Loop obligations that may fail.
---@clavius begin

-- does not hold after last iteration
---@param n integer
---@pre n >= 0 and n < 1000
local function wrong_invariant(n)
    local i = 0
    ---@invariant i < n
    ---@decrease n - i
    while i < n do --! invariant_entry invariant_preserved
        i = i + 1
    end
end

---@param n integer
---@pre n >= 0 and n < 1000
local function stuck(n)
    local i = 0
    ---@invariant 0 <= i and i <= n
    ---@decrease n + i
    while i < n do --! decrease
        i = i + 1
    end
end

-- the measure must stay non-negative while the loop goes again
---@param n integer
---@pre n >= 0 and n < 1000
local function below_zero(n)
    local i = n
    ---@invariant i >= -5
    ---@decrease i
    repeat --! decrease
        i = i - 1
    until i <= -5
end

-- an earlier expression of the measure may not grow, even when a later one decreases
---@param n integer
---@pre n >= 0 and n < 1000
local function earlier_grows(n)
    local i = 0
    local j = 0
    ---@invariant 0 <= j and j <= n and i == j
    ---@decrease i, n - j
    while j < n do --! decrease
        i = i + 1
        j = j + 1
    end
end

-- a `break` after breaking the invariant leaves the code after the loop without it
---@param n integer
---@pre n >= 0 and n < 1000
local function leave_broken(n)
    local flag = 0
    local i = 0
    ---@invariant flag == 0
    ---@decrease n - i
    while i < n do
        flag = 1
        break
    end
    assert(flag == 0) --! assert
end

-- a local the loop writes keeps only what the invariants say
---@param n integer
---@pre n >= 0 and n < 1000
local function unknown(n)
    local i = 0
    ---@decrease n - i
    while i < n do
        i = i + 1
    end
    assert(i == n) --! assert
end

-- an outer loop havocs what its inner loops write
---@param n integer
---@pre n >= 0 and n < 1000
local function inner_write(n)
    local x = 0
    local i = 0
    ---@decrease n - i
    while i < n do
        for j = 1, 2 do
            x = j
        end
        i = i + 1
    end
    assert(x == 0) --! assert
end

-- the counter takes every value in its range, not just the first
local function counter()
    for k = 1, 10 do
        assert(k == 1) --! assert
    end
end

-- the counter of `for i = 1, n` must be able to pass n
---@param n integer
local function far(n)
    for i = 1, n do end --! for_bound
end

-- a step that may be 0, which never ends the loop on LuaJIT or Lua 5.1 to 5.3, whatever the bounds:
--
--                    1, 3, 0       3, 1, 0       2, 2, 0
--   LuaJIT 2.1       never ends    no iteration  never ends
--   Lua 5.1 to 5.3   no iteration  never ends    never ends
--   Lua 5.4          error         error         error
---@param s integer
---@pre s >= -10 and s <= 10
local function zero_step(s)
    for i = 1, 3, s do end --! for_step
end

local function zero_literal()
    for i = 1, 3, 0 do end --! for_step
end

---@clavius end
