-- The interfaces stage: resolves and types the `---@meta` files of a run into the Interface that its Lua
-- modules call. A `---@meta` file holds the trusted specs of library or host functions.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local resolve = require 'clavius.passes.resolve'
local support = require 'clavius.ir.support'
local types = require 'clavius.passes.types'

--- A shipped `---@meta` file of the standard library, or one of the project's with `---@extern` host
--- functions.
--- @alias MetaKind 'stdlib' | 'extern'

--- A parsed `---@meta` file of the run.
--- @class MetaRoot
--- @field root NodeId its root Block
--- @field kind MetaKind

--- What the `---@meta` files of a run declare, for the files that call into them.
--- @class Interface
--- @field functions table<string, NodeId> the Function node of each declared name, such as `math.min`
--- @field kinds table<NodeId, MetaKind> the kind of file that declares each Function
--- @field res Resolution the resolution of the `---@meta` files: their parameters and contracts
--- @field info TypeInfo the types of their parameters, values and contract clauses

local M = {}

--- If a top-level statement defines a function by a global name, as `function math.min(x, y) end` does,
--- returns the name's base and path and the Function node.
--- @param src SrcArena
--- @param id NodeId
--- @return string|nil base
--- @return string|nil path
--- @return NodeId|nil fn
local function definition(src, id)
    local n = src.nodes[id]
    if n.tag ~= 'Set' or #n.targets ~= 1 or #n.values ~= 1 or src.nodes[n.values[1]].tag ~= 'Function' then
        return nil, nil, nil
    end
    local base, path = support.global_path(src, n.targets[1])
    if path == nil then
        return nil, nil, nil
    end
    return base, path, n.values[1]
end

--- Adds the functions that a `---@meta` file declares to `iface`, and returns their Function nodes.
--- @param src SrcArena
--- @param m MetaRoot
--- @param iface Interface
--- @param diags Diag[]
--- @mut iface
--- @mut diags
--- @return NodeId[] fns
local function declare(src, m, iface, diags)
    local fns = {}
    local block = src.nodes[m.root] --[[@as SrcBlock]]
    for _, id in ipairs(block.statements) do
        local n = src.nodes[id]
        local base, name, fn = definition(src, id)
        if n.tag == 'LocalFunction' then
            fn = n.func
        end
        -- a `---@meta` file is never verified, so nothing in it may be marked
        local marked = fn ~= nil and arena.has_directive(src, src.nodes[fn] --[[@as SrcFunction]], 'ClvMarker')
        if n.tag == 'ClvRegion' or marked then
            diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'marked-meta' })
        elseif name ~= nil and m.kind == 'extern' and support.global_use(assert(base), name) ~= 'global' then
            -- a host function can't stand in for a library function, a banned one or `assert`
            diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'library-name' })
        elseif name ~= nil and iface.functions[name] ~= nil then
            diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'repeated-declaration' })
        elseif name ~= nil then
            --- @cast fn NodeId
            iface.functions[name] = fn
            iface.kinds[fn] = m.kind
            fns[#fns + 1] = fn
        end
    end
    return fns
end

--- Builds the Interface of a run's `---@meta` files. Each name may be declared once in the run.
--- @param src SrcArena
--- @param metas MetaRoot[]
--- @return Interface iface
--- @return Diag[] diags
function M.run(src, metas)
    --- @type Interface
    local iface = { functions = {}, kinds = {}, res = resolve.new_resolution(), info = { types = {}, ops = {} } }
    local diags = {}
    for _, m in ipairs(metas) do
        local before = #diags
        local fns = declare(src, m, iface, diags)
        if #diags == before then
            local res_diags = resolve.meta(src, m.root, m.kind, fns, iface.res)
            for _, d in ipairs(res_diags) do
                diags[#diags + 1] = d
            end
            if #res_diags == 0 then
                for _, d in ipairs(types.meta(src, iface.res, fns, iface.info)) do
                    diags[#diags + 1] = d
                end
            end
        end
    end
    return iface, diags
end

return M
