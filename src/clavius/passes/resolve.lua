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
--- @field functions table<NodeId, NodeId> the Function node of each `local function`'s Binder
--- @field constants table<NodeId, NodeId> the initializer of each constant: a top-level local whose initializer is a number or boolean literal, and which is never assigned
--- @field assigned table<NodeId, boolean> the Binders that an assignment anywhere in the file targets
--- @field library table<NodeId, NodeId> the Function node in a `---@meta` file that each call in marked code of a library or host function calls
--- @field idioms table<NodeId, string> the operation that each call in marked code written as a library idiom stands for, such as `int.floordiv` for `math.floor(a / b)`

--- What the `---@meta` files of a run declare, for the files that call into them.
--- @class Interface
--- @field functions table<string, NodeId> the Function node of each declared function, by the name it is called by, such as `math.min`
--- @field kinds table<NodeId, MetaKind> whether each declared function is a shipped library spec or a host function
--- @field res Resolution the resolution of the `---@meta` files: their parameters and contracts
--- @field info TypeInfo the types of their parameters, values and contract clauses

--- A function that a `---@meta` file declares: the name it is called by, and its Function node.
--- @class MetaFunction
--- @field name string
--- @field fn NodeId

--- A `---@meta` file is shipped with Clavius, with the specs of the standard library, or is the
--- project's own, with `---@extern` host functions.
--- @alias MetaKind 'stdlib' | 'extern'

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
--- @field top_functions table<NodeId, boolean> the Function nodes of top-level `local function`s
--- @field binder_of table<NodeId, NodeId> the Binder of each `local function`'s Function node
--- @field verified table<NodeId, boolean> the Function nodes whose bodies are marked code
--- @field loop_vars table<NodeId, boolean> the Binders of numeric `for` loops, which marked code may not assign
--- @field fn NodeId|nil the Binder of the `local function` whose body is being visited
--- @field in_clause boolean whether a contract clause is being visited
--- @field outer_reads PendingUse[]
--- @field calls PendingUse[]
--- @field iface Interface|nil what the run's `---@meta` files declare
--- @field meta_kind MetaKind|nil the kind of `---@meta` file being resolved, or nil for a Lua module
--- @field meta_functions table<NodeId, boolean> in a `---@meta` file, the Function nodes of its top-level function definitions
--- @field top_statements table<NodeId, boolean> the file's top-level statements, outside regions
--- @field alias_path table<NodeId, string> the library function that each candidate alias names: a top-level local of unmarked code initialized with one, such as `local floor = math.floor`
--- @field alias_calls PendingUse[] the calls in marked code through an alias, which must never be assigned

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

--- Records the library aliases that a top-level `local` of unmarked code declares, such as
--- `local floor = math.floor`: a name initialized with a shipped library function, or with
--- `math.floor`, whose idiom `floor(a / b)` then still means integer division (gap review, item 16).
--- A host function can't be aliased, since the host may install it after the module has loaded.
--- @param st ResolveState
--- @param n SrcLocal
--- @param scope integer
--- @mut st
local function record_aliases(st, n, scope)
    for i, b in ipairs(n.names) do
        local v = n.values[i]
        local tag = v and st.src.nodes[v].tag
        local path = nil
        if tag == 'Id' or tag == 'Index' then
            local _
            _, path = global_name(st, v, scope)
        end
        local fn = path and st.iface and st.iface.functions[path]
        local stdlib = fn and st.iface.kinds[fn] == 'stdlib'
        if path ~= nil and (support.IDIOMS[path] or stdlib) then
            st.alias_path[b] = path
        end
    end
end

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

--- Checks a call in marked code of a local: it must be a `local function` that is verified or
--- `---@unsafe`, other than the one being defined, and the arguments must match its parameters.
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
    if b == st.fn then
        report(st, 'E-unsupported-feature', id, { 'recursion' })
    elseif not (st.verified[fn_id] or arena.has_directive(st.src, fn, 'ClvUnsafe')) then
        report(st, 'E-unsupported-feature', id, { 'unmarked-callee' })
    elseif fn.vararg or #n.args ~= #fn.params then
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
    -- a call through a library alias is a call of the library function, as it names it
    local callee = st.src.nodes[n.func]
    local alias = unit ~= 0 and path == nil and callee.tag == 'Id' and lookup(st, scope, callee.name) or nil
    if alias ~= nil and st.alias_path[alias] ~= nil then
        path = st.alias_path[alias]
        base = path:match '^[^.]+'
        st.out.decl[n.func] = alias
        st.alias_calls[#st.alias_calls + 1] = { id = id, binder = alias }
    end
    -- `math.floor(a / b)` is an operation, so a contract may use it too
    local quotient = path ~= nil and support.IDIOMS[path] and support.floordiv_arg(st.src, n)
    if unit ~= 0 and quotient and not is_statement then
        local q = st.src.nodes[quotient] --[[@as SrcBinOp]]
        st.out.idioms[id] = support.IDIOMS[path]
        visit(st, q.lhs, scope, unit)
        visit(st, q.rhs, scope, unit)
        return
    end
    local declared = path ~= nil and st.iface and st.iface.functions[path]
    if unit ~= 0 and declared and not st.in_clause then
        local fn = st.src.nodes[declared] --[[@as SrcFunction]]
        if fn.vararg or #n.args ~= #fn.params then
            report(st, 'E-unsupported-feature', id, { 'call-args' })
        else
            st.out.library[id] = declared
        end
        for _, a in ipairs(n.args) do
            visit(st, a, scope, unit)
        end
        return
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
--- plus the value in a `---@post`.
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
    local allowed = st.meta_kind and support.META_DIRECTIVES or support.FUNCTION_DIRECTIVES
    local unsafe = arena.has_directive(st.src, fn, 'ClvUnsafe')
    if st.meta_kind == 'extern' and not arena.has_directive(st.src, fn, 'ClvExtern') then
        report(st, 'E-misplaced-directive', id, { 'missing-extern' })
    end
    for _, d in ipairs(fn.directives) do
        local dn = st.src.nodes[d]
        if support.TRUST_FLAGS[dn.tag] and not st.meta_kind then
            -- the flags describe trusted code, so they sit only on an `---@unsafe` function here
            if not unsafe then
                report(st, 'E-misplaced-directive', d, { 'untrusted-flag' })
            end
        elseif not allowed[dn.tag] then
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
end

--- Resolves a loop's directives in `scope`. A loop has one measure, of one expression.
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
            elseif unit ~= 0 and #dn.measures > 1 then
                report(st, 'E-unsupported-feature', d, { 'decrease-list' })
            end
            measured = true
            for _, m in ipairs(dn.measures) do
                visit_clause(st, m, scope, unit)
            end
        end
    end
end

--- Returns whether a numeric `for` has a step that marked code may use: none, or a nonzero integer
--- literal, perhaps negated.
--- @param src SrcArena
--- @param step NodeId|nil
--- @return boolean
local function literal_step(src, step)
    if step == nil then
        return true
    end
    local n = src.nodes[step]
    if n.tag == 'UnOp' and n.op == 'unm' then
        n = src.nodes[n.arg]
    end
    return n.tag == 'Literal' and n.kind == 'number' and tonumber(n.text) ~= 0
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
    -- a function in a `---@meta` file is a contract with no body to verify, like an `---@unsafe` one
    local root = (unit ~= 0 or unsafe or st.meta_functions[id]) and id or 0
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
        elseif n.tag == 'Local' and #n.values ~= #n.names then
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
        elseif n.tag == 'Fornum' and not literal_step(st.src, n.step) then
            report(st, 'E-unsupported-feature', id, { 'for-step' })
        end
    end

    local child_scope = scope
    local child_unit = unit
    if n.tag == 'Local' and unit == 0 and st.top_statements[id] then
        record_aliases(st, n --[[@as SrcLocal]], scope)
    end
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

--- Makes the state for resolving one file.
--- @param src SrcArena
--- @param iface Interface|nil
--- @param meta_kind MetaKind|nil
--- @return ResolveState
local function new_state(src, iface, meta_kind)
    return {
        src = src,
        out = { decl = {}, names = {}, functions = {}, constants = {}, assigned = {}, library = {}, idioms = {} },
        diags = {},
        scope_parent = {},
        scope_names = {},
        unit_of = {},
        binders = 0,
        top_functions = {},
        binder_of = {},
        verified = {},
        loop_vars = {},
        fn = nil,
        in_clause = false,
        outer_reads = {},
        calls = {},
        iface = iface,
        meta_kind = meta_kind,
        meta_functions = {},
        top_statements = {},
        alias_path = {},
        alias_calls = {},
    }
end

--- If a top-level statement defines a global function, as `function math.min(x, y) end` does, returns
--- the function's name and its Function node.
--- @param st ResolveState
--- @param id NodeId
--- @return string|nil name
--- @return NodeId|nil fn
local function global_definition(st, id)
    local n = st.src.nodes[id]
    if n.tag ~= 'Set' or #n.targets ~= 1 or #n.values ~= 1 or st.src.nodes[n.values[1]].tag ~= 'Function' then
        return nil, nil
    end
    local _, path = global_name(st, n.targets[1], 0)
    if path == nil then
        return nil, nil
    end
    return path, n.values[1]
end

--- Resolves a `---@meta` file: the parameters and contracts of the functions it declares. Returns the
--- resolution, the declared functions in file order, and the diagnostics. A `---@meta` file has no
--- marked code.
--- @param src SrcArena
--- @param root NodeId
--- @param kind MetaKind
--- @return Resolution res
--- @return MetaFunction[] declared
--- @return Diag[] diags
function M.meta(src, root, kind)
    local st = new_state(src, nil, kind)
    --- @type table<string, NodeId>
    local functions = {}
    --- @type MetaFunction[]
    local declared = {}
    local block = src.nodes[root] --[[@as SrcBlock]]
    for _, id in ipairs(block.statements) do
        local n = src.nodes[id]
        local name, fn = global_definition(st, id)
        if n.tag == 'LocalFunction' then
            fn = n.func
        end
        -- a `---@meta` file is never verified, so nothing in it may be marked
        local marked = fn ~= nil and arena.has_directive(src, src.nodes[fn] --[[@as SrcFunction]], 'ClvMarker')
        if n.tag == 'ClvRegion' or marked then
            report(st, 'E-misplaced-directive', id, { 'marked-meta' })
        elseif name ~= nil and functions[name] ~= nil then
            report(st, 'E-misplaced-directive', id, { 'repeated-declaration' })
        elseif name ~= nil then
            --- @cast fn NodeId
            functions[name] = fn
            declared[#declared + 1] = { name = name, fn = fn }
            st.meta_functions[fn] = true
        end
    end
    if #st.diags > 0 then
        return st.out, declared, st.diags
    end
    visit(st, root, 0, 0)
    return st.out, declared, st.diags
end

--- Resolves a parsed file. The names that the run's `---@meta` files declare are callable from its
--- marked code.
--- @param src SrcArena
--- @param root NodeId
--- @param iface Interface|nil
--- @return Resolution res
--- @return Diag[] diags
function M.run(src, root, iface)
    local st = new_state(src, iface, nil)
    -- the run's resolution covers the `---@meta` files too, since a call lowers its callee's contract
    if iface ~= nil then
        for id = 1, #src.nodes do
            st.out.decl[id] = iface.res.decl[id]
            st.out.names[id] = iface.res.names[id]
        end
    end
    -- the Binders of top-level locals with a literal initializer, and the initializers
    local candidates, values = {}, {}
    for _, id in
        ipairs((src.nodes[root] --[[@as SrcBlock]]).statements)
    do
        st.top_statements[id] = true
    end
    for _, id in ipairs(top_level(src, root)) do
        local n = src.nodes[id]
        if n.tag == 'LocalFunction' then
            st.top_functions[n.func] = true
        elseif n.tag == 'Local' then
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
    -- unmarked code can't swap out a function that verified code relies on
    for _, c in ipairs(st.calls) do
        if st.out.assigned[c.binder] then
            report(st, 'E-unsupported-feature', c.id, { 'reassigned-function' })
        end
    end
    for _, c in ipairs(st.alias_calls) do
        if st.out.assigned[c.binder] then
            report(st, 'E-unsupported-feature', c.id, { 'reassigned-alias' })
        end
    end
    return st.out, st.diags
end

return M
