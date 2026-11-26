---@meta host

-- Host functions that a game engine provides, declared for extern.lua.

---@extern
---@no_callback
---@param hp integer
---@param dmg integer
---@pre 0 <= hp and 0 <= dmg
---@post 0 <= result and result <= hp
---@return integer
function host.damage(hp, dmg) end

---@extern
---@may_raise
---@param n integer
function host.log(n) end

---@extern
---@return integer
---@post 0 <= result and result < 60
function host_frame() end

-- a contract may divide, as spec code does exactly
---@extern
---@param n integer
---@pre n % 2 == 0
---@post result == math.floor(n / 2)
---@return integer
function host.half(n) end

-- a boolean result has no type fact, so the call assumes nothing; it is still trusted
---@extern
---@return boolean
function host.ready() end
