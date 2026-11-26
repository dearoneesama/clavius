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

--- Adds the functions that a `---@meta` file declares to `functions` and `kinds`, and their Function nodes
--- to `fns`.
--- @param src SrcArena
--- @param m MetaRoot
--- @param functions table<string, NodeId>
--- @param kinds table<NodeId, MetaKind>
--- @param fns NodeId[]
--- @param diags Diag[]
--- @mut functions
--- @mut kinds
--- @mut fns
--- @mut diags
local function declare(src, m, functions, kinds, fns, diags)
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
        elseif name ~= nil and functions[name] ~= nil then
            diags[#diags + 1] = diag.at_node('E-misplaced-directive', id, { 'repeated-declaration' })
        elseif name ~= nil then
            --- @cast fn NodeId
            functions[name] = fn
            kinds[fn] = m.kind
            fns[#fns + 1] = fn
        end
    end
end

--- Builds the Interface of a run's `---@meta` files. Each name may be declared once in the run. Each step
--- runs on every file, and the build stops at the first step that reports a diagnostic.
--- @param src SrcArena
--- @param metas MetaRoot[]
--- @return Interface|nil iface nil when there is a diagnostic
--- @return Diag[] diags
function M.run(src, metas)
    local functions = {}
    local kinds = {}
    local fns = {}
    local diags = {}
    for _, m in ipairs(metas) do
        declare(src, m, functions, kinds, fns, diags)
    end
    if #diags > 0 then
        return nil, diags
    end
    local res, res_diags = resolve.meta(src, metas, fns)
    if #res_diags > 0 then
        return nil, res_diags
    end
    local info, type_diags = types.meta(src, res, fns)
    if #type_diags > 0 then
        return nil, type_diags
    end
    return { functions = functions, kinds = kinds, res = res, info = info }, {}
end

return M
