-- Ghost code in comments becomes nodes: spec and lemma blocks wherever they sit, and in marked code
-- proof blocks and `---@proof`, `---@ghost` and `---@assert` lines. Elsewhere they stay comments.

--[[@spec
---@param n Nat
---@return Nat
local function same(n)
    return n
end
]]

---@ghost local unmarked = 0

---@clavius begin

local x = 1
---@ghost local seen = 0
---@ghost seen = seen + x
---@assert seen == 1

--[==[@proof
    local y = x
    if y > 0 then
    end
]==]

--[[@lemma
local f, g
---@param n Nat
function f(n) end
---@param n Nat
function g(n) end
]]

---@proof f(x)

---@clavius end
