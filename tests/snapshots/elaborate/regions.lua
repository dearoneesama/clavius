-- Each region with statements is one unit. Unmarked code between regions is not verified. A
-- `---@proof_by nonlinear_arith` right above a region's `begin` makes its unit nonlinear, and the
-- units of the functions it defines.
local before = 1

---@clavius begin
local x = 1
---@clavius end

print(before + x)

---@clavius begin
---@clavius end

---@clavius begin
local main = 2
assert(main == 2)
---@clavius end

---@proof_by nonlinear_arith
---@clavius begin
---@param n integer
---@return integer
local function square(n)
    return n * n
end
--[[@lemma
---@param n integer
---@return boolean
local function square_spec(n)
    return n * n == n * n
end
]]
local y = x * main
---@clavius end
