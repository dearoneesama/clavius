-- The interfaces stage: `resolve` and `types` on each `---@meta` file of a run, and the Interface that
-- the run's Lua modules call into. A `---@meta` file holds trusted specs: shipped ones for the standard
-- library, or the project's `---@extern` host functions. Nothing in it is verified.

local diag = require 'clavius.ir.diag'
local resolve = require 'clavius.passes.resolve'
local types = require 'clavius.passes.types'

--- A parsed `---@meta` file of the run.
--- @class MetaRoot
--- @field root NodeId its root Block
--- @field kind MetaKind

local M = {}

--- Builds the Interface of a run's `---@meta` files, in their order. A name declared twice, in one file
--- or in two, is an error: each library or host function has one contract.
--- @param src SrcArena
--- @param metas MetaRoot[]
--- @return Interface iface
--- @return Diag[] diags
function M.run(src, metas)
    --- @type Interface
    local iface = {
        functions = {},
        kinds = {},
        res = { decl = {}, names = {}, functions = {}, constants = {}, assigned = {}, library = {}, idioms = {} },
        info = { types = {}, ops = {} },
    }
    local diags = {}
    for _, m in ipairs(metas) do
        local res, declared, res_diags = resolve.meta(src, m.root, m.kind)
        for _, d in ipairs(res_diags) do
            diags[#diags + 1] = d
        end
        local fns = {}
        for _, f in ipairs(declared) do
            if iface.functions[f.name] ~= nil then
                diags[#diags + 1] = diag.at_node('E-misplaced-directive', f.fn, { 'repeated-declaration' })
            else
                iface.functions[f.name] = f.fn
                iface.kinds[f.fn] = m.kind
                fns[#fns + 1] = f.fn
            end
        end
        if #res_diags == 0 then
            local info, type_diags = types.meta(src, res, fns)
            for _, d in ipairs(type_diags) do
                diags[#diags + 1] = d
            end
            -- node ids are the run's, so the files' tables don't overlap
            for id = 1, #src.nodes do
                if res.decl[id] ~= nil then
                    iface.res.decl[id] = res.decl[id]
                end
                if res.names[id] ~= nil then
                    iface.res.names[id] = res.names[id]
                end
                if info.types[id] ~= nil then
                    iface.info.types[id] = info.types[id]
                end
                -- a contract may use `math.floor(a / b)`, which a call lowers with the callee's contract
                if info.ops[id] ~= nil then
                    iface.info.ops[id] = info.ops[id]
                end
            end
        end
    end
    return iface, diags
end

return M
