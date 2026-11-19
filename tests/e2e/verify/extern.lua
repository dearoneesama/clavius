-- Verified code calls host functions that a `---@meta` file declares with `---@extern`, and trusts their
-- contracts. extern.meta.lua is its `--meta` file. The host provides the functions at runtime; here,
-- unmarked glue does.
host = {
    damage = function(hp, dmg)
        return math.max(0, hp - dmg)
    end,
    log = function(_) end,
    half = function(n)
        return n / 2
    end,
    ready = function()
        return true
    end,
}
function host_frame()
    return 0
end

---@clavius
---@param hp integer
---@pre 0 <= hp and hp <= 1000
---@post 0 <= result and result <= hp
---@return integer
local function hit(hp)
    local after = host.damage(hp, 7 + host_frame())
    host.log(after)
    return after
end

---@clavius begin
local h = hit(100)
assert(h <= 100)
assert(host.half(6) == 3)
local ready = host.ready()
---@clavius end
