-- How spec functions, lemmas and the ghost code that uses them lower.
---@clavius begin

-- a FunDecl of the fuel and `n`, with axioms that its guard constant turns on: one more unit of
-- fuel unfolds it once, its value is the same at every fuel, and it is a `Nat`. its own unit checks
-- the body without them: the narrowing to `Nat` and the measure, assuming `tri(n - 1)` is a `Nat`
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

-- a local is a Let in the definition
---@param n Nat
---@return Int
local function double(n)
    local d = n + n
    return d
end
]]

-- its unit assumes the `---@pre`, since only proof code calls it, and that call checks it
--[[@lemma
---@param n Nat
---@pre n > 0
---@post tri(n) == tri(n - 1) + n
local function step(n) end
]]

-- ghost code has exact arithmetic and a ghost loop no `for_bound`, and the lemma call checks that
-- `m` fits its `Nat` parameter
---@reveal_with_fuel tri, 2
---@param m integer
---@pre m >= 1 and m <= 10
local function f(m)
    ---@ghost local g = m + 1
    ---@proof step(m)
    --[[@proof
        for i = 1, g do
        end
    ]]
    ---@assert tri(1) == 1
end
---@clavius end
