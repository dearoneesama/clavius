-- A product of two variables is an opaque term unless its unit may use nonlinear arithmetic, by
-- `---@proof_by(nonlinear_arith)` or with `clavius verify --nonlinear-arith`.
---@clavius begin

---@proof_by(nonlinear_arith)
---@param w integer
---@param h integer
---@pre 0 <= w and w <= 4096 and 0 <= h and h <= 4096
---@return integer
local function area(w, h)
    return w * h
end

-- the product is still one term, equal to itself
---@param w integer
---@param h integer
---@pre 0 <= w and w <= 4096 and 0 <= h and h <= 4096
---@return integer
local function opaque_area(w, h)
    local a = w * h --! range
    assert(a == w * h)
    return a
end

---@clavius end
