-- What the shipped specs don't promise.
---@clavius
---@param a integer
---@param b integer
---@post result == a
---@return integer
local function smaller(a, b)
    return math.min(a, b) --! post
end

---@clavius
---@param x integer
---@post result > 0
---@return integer
local function abs(x)
    return math.abs(x) --! post
end

---@clavius begin
local big = 9007199254740992
local x = math.abs(-big) + 1 --! range
---@clavius end
