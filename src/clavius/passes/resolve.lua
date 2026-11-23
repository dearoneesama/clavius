-- The resolve pass. It finds the declaration behind every name in the file, gives every local a
-- unique name such as `x$3`, and rejects whatever marked code uses beyond what `clavius.ir.support`
-- lists.

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local source_nodes = require 'clavius.ir.source_nodes'
local support = require 'clavius.ir.support'

--- @class Resolution
--- @field decl table<NodeId, NodeId> what each Id refers to: a Binder, or in a `---@post` the ClvReturn of the function's value; an Id with no entry names a global
--- @field names table<NodeId, string> the unique name of each Binder and ClvReturn
--- @field functions table<NodeId, NodeId> the Function node of each function definition's Binder
--- @field defined table<NodeId, NodeId> the Binder that each top-level function definition defines
--- @field constants table<NodeId, NodeId> the initializer of each constant: a top-level local whose initializer is a number or boolean literal, and which is never assigned
--- @field assigned table<NodeId, boolean> the Binders that an assignment anywhere in the file targets

--- A read in marked code of a local declared outside its unit, or a call that marked code makes. Both
--- are checked once the whole file is resolved.
--- @class PendingUse
--- @field id NodeId the Id, or the Call
--- @field binder NodeId

--- @class ResolveState
--- @field src SrcArena
--- @field out Resolution
--- @field diags Diag[]
--- @field scope_parent integer[] the enclosing scope of each scope, or 0
--- @field scope_names table<string, NodeId>[] the locals declared so far in each scope
--- @field unit_of table<NodeId, NodeId> the unit root, a ClvRegion or a Function, that declared each local of marked code
--- @field binders integer locals so far
--- @field top_functions table<NodeId, boolean> the Function nodes of top-level function definitions
--- @field binder_of table<NodeId, NodeId> the Binder of each function definition's Function node
--- @field forward table<NodeId, boolean> the `local`s without values that declare only functions
--- @field gapped table<NodeId, boolean> forward-declared functions that may be called while still nil
--- @field verified table<NodeId, boolean> the Function nodes whose bodies are marked code
--- @field loop_vars table<NodeId, boolean> the Binders of numeric `for` loops, which marked code may not assign
--- @field fn NodeId|nil the Binder of the function definition whose body is being visited
--- @field in_clause boolean whether a contract clause is being visited
--- @field outer_reads PendingUse[]
--- @field calls PendingUse[]

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

--- Gives a declaration its unique name and binds `name` to it in `scope`.
--- @param st ResolveState
--- @param id NodeId a Binder or a ClvReturn
--- @param name string
--- @param scope integer
--- @param unit NodeId the unit root, or 0 outside marked code
--- @mut st
local function declare(st, id, name, scope, unit)
    st.binders = st.binders + 1
    st.out.names[id] = ('%s$%d'):format(name, st.binders)
    st.scope_names[scope][name] = id
    if unit ~= 0 then
        st.unit_of[id] = unit
    end
end

--- Returns the declaration that `name` refers to in `scope`, or nil for a global.
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
        local obj = st.src.nodes[n.obj]
        local key = st.src.nodes[n.key]
        if obj.tag == 'Id' and key.tag == 'Literal' and key.kind == 'string' and lookup(st, scope, obj.name) == nil then
            return obj.name, ('%s.%s'):format(obj.name, key.text)
        end
    end
    return nil, nil
end

--- Reports a use of a global in marked code other than a call to `assert` or `error`.
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

--- Records the declaration of an Id. In marked code, a local of another unit may be read only if it is
--- a constant, which is known once the whole file is resolved, and a function only by calling it.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param unit NodeId
--- @mut st
local function use(st, id, scope, unit)
    local n = st.src.nodes[id] --[[@as SrcId]]
    local b = lookup(st, scope, n.name)
    if b ~= nil then
        st.out.decl[id] = b
        if unit ~= 0 and st.out.functions[b] then
            report(st, 'E-unsupported-feature', id, { 'function-value' })
        elseif unit ~= 0 and st.unit_of[b] ~= unit then
            st.outer_reads[#st.outer_reads + 1] = { id = id, binder = b }
        end
    elseif unit ~= 0 then
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

--- Checks a call in marked code of a local: it must be a function definition whose parameters the
--- arguments match. Whether the callee is verified or `---@unsafe` is checked once the whole file is
--- resolved, since a forward-declared callee may be defined below.
--- @param st ResolveState
--- @param id NodeId
--- @param n SrcCall
--- @param scope integer
--- @mut st
local function check_local_call(st, id, n, scope)
    local callee = st.src.nodes[n.func]
    local b = callee.tag == 'Id' and n.method == nil and lookup(st, scope, callee.name) or nil
    local fn_id = b and st.out.functions[b]
    if not fn_id then
        report(st, 'E-unsupported-feature', id, { 'call' })
        return
    end
    --- @cast b NodeId
    local fn = st.src.nodes[fn_id] --[[@as SrcFunction]]
    if fn.vararg or #n.args ~= #fn.params then
        report(st, 'E-unsupported-feature', id, { 'call-args' })
    else
        st.calls[#st.calls + 1] = { id = id, binder = b }
    end
end

--- Visits a call. Marked code may call `assert` and `error` as statements, and verified and `---@unsafe`
--- local functions anywhere but in a contract.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param unit NodeId
--- @param is_statement boolean
--- @mut st
--- @decrease id
local function visit_call(st, id, scope, unit, is_statement)
    local n = st.src.nodes[id] --[[@as SrcCall]]
    local base, path = nil, nil
    if n.method == nil then
        base, path = global_name(st, n.func, scope)
    end
    if unit ~= 0 and st.in_clause then
        report(st, 'E-unsupported-feature', id, { 'call-in-contract' })
        unit = 0
    elseif unit ~= 0 then
        if path == nil then
            check_local_call(st, id, n, scope)
        elseif support.global_use(assert(base), path) == 'supported' and is_statement then
            check_builtin_args(st, id, n, path)
        elseif support.global_use(assert(base), path) == 'supported' then
            report(st, 'E-unsupported-feature', id, { 'call-value' })
        else
            report_global(st, n.func, assert(base), path)
        end
    end
    -- a global callee has nothing to resolve, and a local one is read only by calling it
    if path == nil then
        visit(st, n.func, scope, 0)
    end
    for _, a in ipairs(n.args) do
        visit(st, a, scope, unit)
    end
end

--- Visits an assignment. In marked code, its targets must be distinct locals.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param unit NodeId
--- @mut st
--- @decrease id
local function visit_set(st, id, scope, unit)
    local n = st.src.nodes[id] --[[@as SrcSet]]
    if unit ~= 0 and #n.targets ~= #n.values then
        report(st, 'E-unsupported-feature', id, { 'assign-values' })
    end
    for i, t in ipairs(n.targets) do
        local target = st.src.nodes[t]
        if target.tag == 'Id' and lookup(st, scope, target.name) == nil then
            if unit ~= 0 then
                report(st, 'E-banned-global', t, { target.name })
            end
        else
            visit(st, t, scope, unit)
        end
        local decl = st.out.decl[t]
        if target.tag == 'Id' and decl ~= nil then
            st.out.assigned[decl] = true
        end
        if unit ~= 0 and decl ~= nil and st.loop_vars[decl] then
            report(st, 'E-unsupported-feature', t, { 'loop-variable-write' })
        end
        -- LuaJIT assigns right to left, and Lua leaves the order undefined
        local j = 1
        while unit ~= 0 and decl ~= nil and j < i do
            if st.out.decl[n.targets[j]] == decl then
                report(st, 'E-unsupported-feature', t, { 'repeated-target' })
                break
            end
            j = j + 1
        end
    end
    for _, v in ipairs(n.values) do
        visit(st, v, scope, unit)
    end
end

--- Visits the statements of a list. A call among them is a statement call.
--- @param st ResolveState
--- @param statements NodeId[]
--- @param scope integer
--- @param unit NodeId
--- @mut st
local function visit_statements(st, statements, scope, unit)
    for _, statement in ipairs(statements) do
        if st.src.nodes[statement].tag == 'Call' then
            visit_call(st, statement, scope, unit, true)
        else
            visit(st, statement, scope, unit)
        end
    end
end

--- Visits a contract clause in spec code, where calls aren't allowed.
--- @param st ResolveState
--- @param cond NodeId
--- @param scope integer
--- @param unit NodeId
--- @mut st
local function visit_clause(st, cond, scope, unit)
    st.in_clause = true
    visit(st, cond, scope, unit)
    st.in_clause = false
end

--- Checks a function's directives and resolves its contract. A `---@param` must name a parameter once, a
--- `---@return` declares the name that `---@post` calls the value by, and a clause sees the parameters,
--- plus the value in a `---@post`. A measure sees what a `---@pre` sees.
--- @param st ResolveState
--- @param id NodeId the Function
--- @param scope integer the scope of the parameters
--- @mut st
local function visit_directives(st, id, scope)
    local fn = st.src.nodes[id] --[[@as SrcFunction]]
    local params = {}
    for _, p in ipairs(fn.params) do
        params[
            (st.src.nodes[p] --[[@as SrcBinder]]).name
        ] = true
    end
    local typed, returns, clauses = {}, {}, {}
    local measures = {}
    for _, d in ipairs(fn.directives) do
        local dn = st.src.nodes[d]
        if not support.FUNCTION_DIRECTIVES[dn.tag] then
            report(st, 'E-unsupported-directive', d, { support.DIRECTIVE_TAGS[dn.tag] })
        elseif dn.tag == 'ClvParam' and not params[dn.name] then
            report(st, 'E-misplaced-directive', d, { 'no-such-param' })
        elseif dn.tag == 'ClvParam' and typed[dn.name] then
            report(st, 'E-misplaced-directive', d, { 'repeated-param' })
        elseif dn.tag == 'ClvParam' then
            typed[dn.name] = true
        elseif dn.tag == 'ClvReturn' then
            returns[#returns + 1] = d
        elseif dn.tag == 'ClvPre' or dn.tag == 'ClvPost' then
            clauses[#clauses + 1] = d
        elseif dn.tag == 'ClvDecrease' and arena.has_directive(st.src, fn, 'ClvUnsafe') then
            report(st, 'E-misplaced-directive', d, { 'unsafe-decrease' })
        elseif dn.tag == 'ClvDecrease' and #measures > 0 then
            report(st, 'E-misplaced-directive', d, { 'repeated-decrease' })
        elseif dn.tag == 'ClvDecrease' then
            measures = dn.measures
        elseif dn.tag == 'ClvUnsafe' and arena.has_directive(st.src, fn, 'ClvMarker') then
            report(st, 'E-misplaced-directive', d, { 'marked-unsafe' })
        end
    end
    if #returns > 1 then
        report(st, 'E-unsupported-feature', returns[2], { 'multiple-returns' })
    end
    local post_scope = open(st, scope)
    local r = returns[1]
    if r ~= nil then
        local name = (st.src.nodes[r] --[[@as SrcClvReturn]]).name or 'result'
        if params[name] then
            report(st, 'E-misplaced-directive', r, { 'return-name-clash' })
        end
        declare(st, r, name, post_scope, id)
    end
    for _, d in ipairs(clauses) do
        local clause = st.src.nodes[d] --[[@as SrcClvPre|SrcClvPost]]
        visit_clause(st, clause.cond, clause.tag == 'ClvPost' and post_scope or scope, id)
    end
    for _, m in ipairs(measures) do
        visit_clause(st, m, scope, id)
    end
end

--- Resolves a loop's directives in `scope`. A loop has at most one measure.
--- @param st ResolveState
--- @param loop SrcWhile|SrcRepeat|SrcFornum
--- @param scope integer
--- @param unit NodeId
--- @mut st
local function visit_loop_directives(st, loop, scope, unit)
    local measured = false
    for _, d in ipairs(loop.directives) do
        local dn = st.src.nodes[d]
        if unit ~= 0 and not support.LOOP_DIRECTIVES[dn.tag] then
            report(st, 'E-unsupported-directive', d, { support.DIRECTIVE_TAGS[dn.tag] })
        elseif dn.tag == 'ClvInvariant' then
            visit_clause(st, dn.cond, scope, unit)
        elseif dn.tag == 'ClvDecrease' then
            if unit ~= 0 and measured then
                report(st, 'E-misplaced-directive', d, { 'repeated-decrease' })
            end
            measured = true
            for _, m in ipairs(dn.measures) do
                visit_clause(st, m, scope, unit)
            end
        end
    end
end

--- Visits a function. In marked code, or when it is `---@unsafe`, the function is a unit root for its
--- contract. Its body is marked code unless it is `---@unsafe`.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param unit NodeId 0 when the function is unmarked code or has been reported
--- @param binder NodeId|nil the Binder of the `local function` that defines it
--- @mut st
--- @decrease id
local function visit_function(st, id, scope, unit, binder)
    local fn = st.src.nodes[id] --[[@as SrcFunction]]
    local unsafe = arena.has_directive(st.src, fn, 'ClvUnsafe')
    local root = (unit ~= 0 or unsafe) and id or 0
    local s = open(st, scope)
    for _, p in ipairs(fn.params) do
        local name = (st.src.nodes[p] --[[@as SrcBinder]]).name
        declare(st, p, name, s, root)
    end
    if root ~= 0 then
        visit_directives(st, id, s)
    end
    local body_unit = (unit ~= 0 and not unsafe) and id or 0
    st.verified[id] = body_unit ~= 0
    local outer = st.fn
    st.fn = binder
    visit(st, fn.body, s, body_unit)
    st.fn = outer
end

--- Visits a node with `scope` as its scope. `unit` is the root of the unit whose rules apply to the
--- node: its ClvRegion, or the marked Function it is in. It is 0 when the node is unmarked code or
--- inside a construct that has already been reported.
--- @param st ResolveState
--- @param id NodeId
--- @param scope integer
--- @param unit NodeId
--- @mut st
--- @decrease id
function visit(st, id, scope, unit)
    local n = st.src.nodes[id]
    local tag = n.tag
    if
        unit == 0
        and n.tag == 'Function'
        and arena.has_directive(st.src, n --[[@as SrcFunction]], 'ClvMarker')
    then
        unit = id
    elseif unit == 0 and (tag == 'ClvSpec' or tag == 'ClvLemma') then
        -- spec and lemma blocks are checked wherever they sit
        unit = id
    end
    -- what marked code may use
    if unit ~= 0 then
        local base, path = nil, nil
        if tag == 'Index' then
            base, path = global_name(st, id, scope)
        end
        if path ~= nil then
            report_global(st, id, assert(base), path)
            return
        elseif support.BANNED_KINDS[tag] then
            report(st, 'E-banned-goto', id, {})
            unit = 0
        elseif not support.KINDS[tag] then
            report(st, 'E-unsupported-feature', id, { tag })
            unit = 0
        elseif n.tag == 'BinOp' and not support.BINOPS[n.op] then
            report(st, 'E-unsupported-feature', id, { n.op })
            unit = 0
        elseif n.tag == 'UnOp' and not support.UNOPS[n.op] then
            report(st, 'E-unsupported-feature', id, { n.op })
            unit = 0
        elseif n.tag == 'Local' and #n.values ~= #n.names and not st.forward[id] then
            report(st, 'E-unsupported-feature', id, { 'local-values' })
        elseif n.tag == 'Function' and not st.top_functions[id] then
            report(st, 'E-unsupported-feature', id, { 'function-value' })
            unit = 0
        elseif n.tag == 'Return' and st.fn == nil then
            report(st, 'E-unsupported-feature', id, { 'return-outside-function' })
            unit = 0
        elseif n.tag == 'Return' and #n.values > 1 then
            report(st, 'E-unsupported-feature', id, { 'multiple-returns' })
            unit = 0
        end
    end

    local child_scope = scope
    local child_unit = unit
    if n.tag == 'Block' or n.tag == 'Forin' then
        child_scope = open(st, scope)
    elseif n.tag == 'ClvRegion' then
        child_unit = id
    elseif n.tag == 'Binder' then
        declare(st, id, n.name, scope, unit)
    elseif n.tag == 'Id' then
        use(st, id, scope, unit)
    elseif n.tag == 'Call' then
        visit_call(st, id, scope, unit, false)
        return
    elseif n.tag == 'Set' and st.out.defined[id] ~= nil then
        -- the definition of a forward-declared function, which is no assignment that marked code sees
        st.out.decl[n.targets[1]] = st.out.defined[id]
        visit(st, n.values[1], scope, unit)
        return
    elseif n.tag == 'Set' then
        visit_set(st, id, scope, unit)
        return
    elseif n.tag == 'Function' then
        visit_function(st, id, scope, unit, st.binder_of[id])
        return
    elseif n.tag == 'LocalFunction' then
        -- the function can see its own name
        visit(st, n.binder, scope, unit)
        st.out.functions[n.binder] = n.func
        st.binder_of[n.func] = n.binder
        visit(st, n.func, scope, unit)
        return
    elseif n.tag == 'While' then
        visit_loop_directives(st, n, scope, unit)
        visit(st, n.cond, scope, unit)
        visit(st, n.body, scope, unit)
        return
    elseif n.tag == 'Repeat' then
        -- the directives see only what is outside the loop, and the condition sees the body's locals
        visit_loop_directives(st, n, scope, unit)
        local body = st.src.nodes[n.body] --[[@as SrcBlock]]
        local s = open(st, scope)
        visit_statements(st, body.statements, s, unit)
        visit(st, n.cond, s, unit)
        return
    elseif n.tag == 'Fornum' then
        -- the bounds don't see the loop variable (e.g. for i=i,i), and the directives do
        visit(st, n.start, scope, unit)
        visit(st, n.limit, scope, unit)
        if n.step ~= nil then
            visit(st, n.step, scope, unit)
        end
        local s = open(st, scope)
        visit(st, n.var, s, unit)
        st.loop_vars[n.var] = true
        visit_loop_directives(st, n, s, unit)
        visit(st, n.body, s, unit)
        return
    end

    if n.tag == 'Block' or n.tag == 'ClvRegion' then
        visit_statements(st, n.statements, child_scope, child_unit)
        return
    end
    for _, kid in ipairs(source_nodes.children(n)) do
        visit(st, kid, child_scope, child_unit)
    end
end

--- Returns whether `id` is a number or boolean literal, perhaps negated, as a constant's initializer is.
--- @param src SrcArena
--- @param id NodeId
--- @return boolean
local function is_literal(src, id)
    local n = src.nodes[id]
    if n.tag == 'UnOp' and n.op == 'unm' then
        n = src.nodes[n.arg]
        return n.tag == 'Literal' and n.kind == 'number'
    end
    return n.tag == 'Literal' and (n.kind == 'number' or n.kind == 'true' or n.kind == 'false')
end

--- Returns the top-level statements of a file: those of the root Block and of its regions.
--- @param src SrcArena
--- @param root NodeId
--- @return NodeId[]
local function top_level(src, root)
    local out = {}
    local block = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(block.statements) do
        local n = src.nodes[id]
        if n.tag == 'ClvRegion' then
            for _, s in ipairs(n.statements) do
                out[#out + 1] = s
            end
        else
            out[#out + 1] = id
        end
    end
    return out
end

--- Finds the top-level function definitions. Besides `local function f`, mutual recursion needs a
--- function declared by a top-level `local g` without values and defined by the first top-level
--- `function g(…)` or `g = function(…)` that assigns that local. Its definition is gapped when code
--- that may run sits between the two: anything but a function definition or a `local` without values.
--- That code could call a function that calls `g` while `g` is still nil.
--- @param st ResolveState
--- @param statements NodeId[] the top-level statements
--- @mut st
local function find_definitions(st, statements)
    local src = st.src
    --- @type table<string, NodeId>
    local latest = {} -- name -> the Binder of its latest top-level declaration
    --- @type table<NodeId, integer>
    local declared_at = {} -- the position of the `local` without values that declares a Binder
    for i, id in ipairs(statements) do
        local n = src.nodes[id]
        if n.tag == 'LocalFunction' then
            local name = (src.nodes[n.binder] --[[@as SrcBinder]]).name
            latest[name] = n.binder
            st.out.defined[id] = n.binder
            st.top_functions[n.func] = true
        elseif n.tag == 'Local' then
            for _, b in ipairs(n.names) do
                local name = (src.nodes[b] --[[@as SrcBinder]]).name
                latest[name] = b
                if #n.values == 0 then
                    declared_at[b] = i
                end
            end
        elseif n.tag == 'Set' and #n.targets == 1 and #n.values == 1 and src.nodes[n.values[1]].tag == 'Function' then
            local target = src.nodes[n.targets[1]]
            local b = target.tag == 'Id' and latest[target.name] or nil
            if b ~= nil and declared_at[b] ~= nil and st.out.functions[b] == nil then
                st.out.functions[b] = n.values[1]
                st.out.defined[id] = b
                st.binder_of[n.values[1]] = b
                st.top_functions[n.values[1]] = true
                -- the window may hold only what runs no code: function definitions and `local`s without
                -- values. it's a syntactic rule, so a constant or a call that can't reach `g` is
                -- rejected too. telling those apart would need the callees that `types` finds
                for k = declared_at[b] + 1, i - 1 do
                    local between = src.nodes[statements[k]]
                    if st.out.defined[statements[k]] == nil and not (between.tag == 'Local' and #between.values == 0) then
                        st.gapped[b] = true
                    end
                end
            end
        end
    end
    for _, id in ipairs(statements) do
        local n = src.nodes[id]
        if n.tag == 'Local' and #n.values == 0 then
            local all = true
            for _, b in ipairs(n.names) do
                all = all and st.out.functions[b] ~= nil
            end
            st.forward[id] = all
        end
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
        out = { decl = {}, names = {}, functions = {}, defined = {}, constants = {}, assigned = {} },
        diags = {},
        scope_parent = {},
        scope_names = {},
        unit_of = {},
        binders = 0,
        top_functions = {},
        binder_of = {},
        forward = {},
        gapped = {},
        verified = {},
        loop_vars = {},
        fn = nil,
        in_clause = false,
        outer_reads = {},
        calls = {},
    }
    local statements = top_level(src, root)
    find_definitions(st, statements)
    -- the Binders of top-level locals with a literal initializer, and the initializers
    local candidates, values = {}, {}
    for _, id in ipairs(statements) do
        local n = src.nodes[id]
        if n.tag == 'Local' then
            for i, b in ipairs(n.names) do
                if n.values[i] ~= nil and is_literal(src, n.values[i]) then
                    candidates[#candidates + 1] = b
                    values[#values + 1] = n.values[i]
                end
            end
        end
    end
    visit(st, root, 0, 0)
    for i, b in ipairs(candidates) do
        if not st.out.assigned[b] then
            st.out.constants[b] = values[i]
        end
    end
    for _, r in ipairs(st.outer_reads) do
        if st.out.constants[r.binder] == nil then
            report(st, 'E-unsupported-feature', r.id, { 'outer-local' })
        end
    end
    for _, c in ipairs(st.calls) do
        local fn_id = st.out.functions[c.binder]
        local fn = src.nodes[fn_id] --[[@as SrcFunction]]
        if not (st.verified[fn_id] or arena.has_directive(src, fn, 'ClvUnsafe')) then
            report(st, 'E-unsupported-feature', c.id, { 'unmarked-callee' })
        -- unmarked code can't swap out a function that verified code relies on
        elseif st.out.assigned[c.binder] then
            report(st, 'E-unsupported-feature', c.id, { 'reassigned-function' })
        elseif st.gapped[c.binder] then
            report(st, 'E-unsupported-feature', c.id, { 'forward-gap' })
        end
    end
    return st.out, st.diags
end

return M
