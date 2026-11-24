-- Finds what a failure message can suggest beyond the failure itself.

local core_nodes = require 'clavius.ir.core_nodes'

local M = {}

--- Returns the obligations checked in the linear units that multiply two terms, neither of them a
--- constant. The solver treats such a product as an opaque term there.
--- @param core CoreArena
--- @param units NodeId[] Unit nodes
--- @return table<integer, boolean> by obligation id
function M.opaque_products(core, units)
    --- @type table<integer, boolean>
    local out = {}
    for _, u in ipairs(units) do
        local unit = core.nodes[u] --[[@as CoreUnit]]
        if unit.arith == 'linear' then
            --- @type integer[]
            local checks = {}
            local product = false
            local pending = { u }
            while #pending > 0 do
                local n = core.nodes[table.remove(pending)]
                if n.tag == 'Check' then
                    checks[#checks + 1] = (n --[[@as CoreCheck]]).obligation
                elseif n.tag == 'BinOp' and n.op == '*' then
                    local op = n --[[@as CoreBinOp]]
                    -- a constant factor keeps the product linear
                    product = product or (core.nodes[op.lhs].tag ~= 'Int' and core.nodes[op.rhs].tag ~= 'Int')
                end
                for _, kid in ipairs(core_nodes.children(n)) do
                    pending[#pending + 1] = kid
                end
            end
            for _, id in ipairs(checks) do
                out[id] = product
            end
        end
    end
    return out
end

return M
