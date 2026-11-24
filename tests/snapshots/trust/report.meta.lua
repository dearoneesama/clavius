---@meta host

-- Host functions that report.lua calls.

---@extern
---@no_callback
---@param n integer
---@pre n >= 0
---@return integer
function host.scale(n) end

---@extern
---@may_raise
---@param n integer
function host.log(n) end

---@extern
---@return integer
function frame() end
