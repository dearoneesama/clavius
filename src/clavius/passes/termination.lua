-- The termination pass: every `while` and `repeat` loop in marked code needs a `---@decrease`, whose
-- measure the loop's encoding checks on each iteration.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'

local M = {}

--- Reports the loops in marked code that have no measure.
--- @param src SrcArena
--- @param idx NodeIndex
--- @return Diag[] diags
function M.run(src, idx)
    local diags = {}
    for _, tag in ipairs { 'While', 'Repeat' } do
        for _, id in ipairs(idx.by_tag[tag] or {}) do
            local loop = src.nodes[id] --[[@as SrcWhile|SrcRepeat]]
            if idx.unit[id] ~= 0 and not arena.has_directive(src, loop, 'ClvDecrease') then
                diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'missing-decrease' })
            end
        end
    end
    return diags
end

return M
