-- Directives above a function that is marked or in a region become its directive nodes, and a
-- `---@proof_by` right above a region's `begin` becomes the region's. Elsewhere they are left to LuaLS.

---@param n int53 the count
---@return boolean
local function unmarked(n)
    return n > 0
end

---@clavius
---@param n int53
---@param flag? boolean
---@pre n > 0 and n < 10
---@post result == n + 1
---@return int53
local function inc(n, flag)
    return n + 1
end

---@unsafe
---@param s string
---@return int53 size, string? err
local function size(s)
    return #s
end

---@proof_by(nonlinear_arith)
---@clavius begin
---@param xs Seq<int53>
---@decrease #xs
---@deprecated
local count = function(xs)
    return #xs
end
---@clavius end
