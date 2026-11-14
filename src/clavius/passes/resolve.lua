-- The resolve pass. It finds the declaration behind every name in the file, gives every local a
-- unique name such as `x$3`, and rejects whatever a region uses beyond what `clavius.ir.support` lists.

local diag = require 'clavius.ir.diag'
local source_nodes = require 'clavius.ir.source_nodes'
local support = require 'clavius.ir.support'

--- @class Resolution
--- @field decl table<NodeId, NodeId> the Binder each Id refers to; an Id with no entry names a global
--- @field names table<NodeId, string> the unique name of each Binder

--- @class ResolveState
--- @field src SrcArena
--- @field out Resolution
--- @field diags Diag[]
--- @field scope_parent integer[] the enclosing scope of each scope, or 0
--- @field scope_names table<string, NodeId>[] the locals declared so far in each scope
--- @field binder_region table<NodeId, NodeId> the ClvRegion of each Binder declared in one
--- @field binders integer Binders so far

local M = {}

--- @param st ResolveState
--- @param code DiagCode
--- @param id NodeId
--- @param args string[]
--- @mut st
local function report(st, code, id, args)
    st.diags[#st.diags + 1] = diag.at_node(code, id, args)
end

--- @param st ResolveState
--- @param parent integer
--- @mut st
--- @return integer scope
local function open(st, parent)
    local s = #st.scope_parent + 1
    st.scope_parent[s] = parent
    st.scope_names[s] = {}
    return s
end

--- Returns the Binder that `name` refers to in `scope`, or nil for a global.
--- @param st ResolveState
--- @param scope integer
--- @param name string
--- @return NodeId|nil
local function lookup(st, scope, name)
    local s = scope
    while s ~= 0 do
        local b = st.scope_names[s][name]
        if b ~= nil then
            return b
        end
        s = st.scope_parent[s]
    end
    return nil
end

--- If `id` names a global or a field of one, such as `print` or `math.floor`, returns the global and
--- the name as written.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @return string|nil base
--- @return string|nil path
local function global_name(st, id, scope)
    local n = st.src.nodes[id]
    -- print
    if n.tag == 'Id' and lookup(st, scope, n.name) == nil then
        return n.name, n.name
    -- math.floor
    elseif n.tag == 'Index' then
        local obj, key = st.src.nodes[n.obj], st.src.nodes[n.key]
        if obj.tag == 'Id' and key.tag == 'Literal' and key.kind == 'string' and lookup(st, scope, obj.name) == nil then
            return obj.name, ('%s.%s'):format(obj.name, key.text)
        end
    end
    return nil, nil
end

--- Reports a use of a global in a region other than a call to `assert` or `error`.
--- @param st ResolveState
--- @param id NodeId
--- @param base string
--- @param path string
--- @mut st
local function report_global(st, id, base, path)
    local use = support.global_use(base, path)
    if use == 'supported' then
        report(st, 'E-unsupported-feature', id, { 'call-value' })
    elseif use == 'banned' then
        report(st, 'E-banned-call', id, { path })
    elseif use == 'library' then
        report(st, 'E-unsupported-call', id, { path })
    else
        report(st, 'E-banned-global', id, { base })
    end
end

--- Records the declaration of an Id. In a region, it must be a local of the same region.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param region NodeId
--- @mut st
local function use(st, id, scope, region)
    local n = st.src.nodes[id] --[[@as SrcId]]
    local b = lookup(st, scope, n.name)
    if b ~= nil then
        st.out.decl[id] = b
        if region ~= 0 and st.binder_region[b] ~= region then
            report(st, 'E-unsupported-feature', id, { 'outer-local' })
        end
    elseif region ~= 0 then
        report_global(st, id, n.name, n.name)
    end
end

local visit

--- Checks the arguments of a statement call to `assert` or `error`.
--- @param st ResolveState
--- @param id NodeId
--- @param n SrcCall
--- @param name string
--- @mut st
local function check_builtin_args(st, id, n, name)
    if name == 'assert' then
        local msg = n.args[2] and st.src.nodes[n.args[2]]
        if #n.args == 0 or #n.args > 2 or (msg and msg.tag ~= 'Literal') then
            report(st, 'E-unsupported-feature', id, { 'assert-args' })
        end
        return
    end
    for _, a in ipairs(n.args) do
        if st.src.nodes[a].tag ~= 'Literal' then
            report(st, 'E-unsupported-feature', id, { 'error-args' })
            return
        end
    end
end

--- Visits a call. A region may only call `assert` and `error`, and only as statements.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param region NodeId
--- @param is_statement boolean
--- @mut st
--- @decrease id
local function visit_call(st, id, scope, region, is_statement)
    local n = st.src.nodes[id] --[[@as SrcCall]]
    local base, path = nil, nil
    if n.method == nil then
        base, path = global_name(st, n.func, scope)
    end
    if region ~= 0 then
        if path == nil then
            report(st, 'E-unsupported-feature', id, { 'call' })
        elseif support.global_use(assert(base), path) == 'supported' and is_statement then
            check_builtin_args(st, id, n, path)
        elseif support.global_use(assert(base), path) == 'supported' then
            report(st, 'E-unsupported-feature', id, { 'call-value' })
        else
            report_global(st, n.func, assert(base), path)
        end
    end
    -- a global callee has nothing to resolve, and other callees are already reported
    if path == nil then
        visit(st, n.func, scope, 0)
    end
    for _, a in ipairs(n.args) do
        visit(st, a, scope, region)
    end
end

--- Visits an assignment. Its targets must be distinct locals of the region.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param region NodeId
--- @mut st
--- @decrease id
local function visit_set(st, id, scope, region)
    local n = st.src.nodes[id] --[[@as SrcSet]]
    if region ~= 0 and #n.targets ~= #n.values then
        report(st, 'E-unsupported-feature', id, { 'assign-values' })
    end
    for i, t in ipairs(n.targets) do
        local target = st.src.nodes[t]
        if target.tag == 'Id' and lookup(st, scope, target.name) == nil then
            if region ~= 0 then
                report(st, 'E-banned-global', t, { target.name })
            end
        else
            visit(st, t, scope, region)
        end
        -- LuaJIT assigns right to left, and Lua leaves the order undefined
        local decl = st.out.decl[t]
        local j = 1
        while region ~= 0 and decl ~= nil and j < i do
            if st.out.decl[n.targets[j]] == decl then
                report(st, 'E-unsupported-feature', t, { 'repeated-target' })
                break
            end
            j = j + 1
        end
    end
    for _, v in ipairs(n.values) do
        visit(st, v, scope, region)
    end
end

--- Visits the statements of a list. A call among them is a statement call.
--- @param st ResolveState
--- @param statements NodeId[]
--- @param scope integer
--- @param region NodeId
--- @mut st
local function visit_statements(st, statements, scope, region)
    for _, statement in ipairs(statements) do
        if st.src.nodes[statement].tag == 'Call' then
            visit_call(st, statement, scope, region, true)
        else
            visit(st, statement, scope, region)
        end
    end
end

--- Visits a node with `scope` as its scope. `region` is the ClvRegion that the node is in, or 0 when the
--- node is outside every region or inside a construct that has already been reported.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param region NodeId
--- @mut st
--- @decrease id
function visit(st, id, scope, region)
    local n = st.src.nodes[id]
    local tag = n.tag
    -- what a region may use
    if region ~= 0 then
        local base, path = nil, nil
        if tag == 'Index' then
            base, path = global_name(st, id, scope)
        end
        if path ~= nil then
            report_global(st, id, assert(base), path)
            return
        elseif support.BANNED_KINDS[tag] then
            report(st, 'E-banned-goto', id, {})
            region = 0
        elseif not support.KINDS[tag] then
            report(st, 'E-unsupported-feature', id, { tag })
            region = 0
        elseif n.tag == 'BinOp' and not support.BINOPS[n.op] then
            report(st, 'E-unsupported-feature', id, { n.op })
            region = 0
        elseif n.tag == 'UnOp' and not support.UNOPS[n.op] then
            report(st, 'E-unsupported-feature', id, { n.op })
            region = 0
        elseif n.tag == 'Local' and #n.values ~= #n.names then
            report(st, 'E-unsupported-feature', id, { 'local-values' })
        end
    end

    local child_scope, child_region = scope, region
    if n.tag == 'Block' or n.tag == 'Function' or n.tag == 'Fornum' or n.tag == 'Forin' then
        child_scope = open(st, scope)
    elseif n.tag == 'ClvRegion' then
        child_region = id
    elseif n.tag == 'Binder' then
        st.binders = st.binders + 1
        st.out.names[id] = ('%s$%d'):format(n.name, st.binders)
        st.scope_names[scope][n.name] = id
        if region ~= 0 then
            st.binder_region[id] = region
        end
    elseif n.tag == 'Id' then
        use(st, id, scope, region)
    elseif n.tag == 'Call' then
        visit_call(st, id, scope, region, false)
        return
    elseif n.tag == 'Set' then
        visit_set(st, id, scope, region)
        return
    elseif n.tag == 'Repeat' then
        -- the condition sees the body's locals
        local body = st.src.nodes[n.body] --[[@as SrcBlock]]
        local s = open(st, scope)
        visit_statements(st, body.statements, s, region)
        visit(st, n.cond, s, region)
        return
    end

    if n.tag == 'Block' or n.tag == 'ClvRegion' then
        visit_statements(st, n.statements, child_scope, child_region)
        return
    end
    for _, kid in ipairs(source_nodes.children(n)) do
        visit(st, kid, child_scope, child_region)
    end
end

--- Resolves a parsed file.
--- @param src SrcArena
--- @param root NodeId
--- @return Resolution res
--- @return Diag[] diags
function M.run(src, root)
    --- @type ResolveState
    local st = {
        src = src,
        out = { decl = {}, names = {} },
        diags = {},
        scope_parent = {},
        scope_names = {},
        binder_region = {},
        binders = 0,
    }
    visit(st, root, 0, 0)
    return st.out, st.diags
end

return M
