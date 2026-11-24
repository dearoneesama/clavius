-- Prints core programs as Boogie. The declarations come first, as types, functions and axioms. Each
-- unit becomes a procedure with no contract that is checked on its own under a Z3 resource limit, and a
-- nonlinear one turns on Z3's nonlinear arithmetic for itself. Each `Check` becomes an `assert` labeled
-- with its obligation id:
--
--   procedure {:rlimit 10000000} main()
--   {
--     var x: int;
--
--     assume x > 0;
--     assert {:msg "O1"} (x + 1) > x;
--   }

--- @class BoogiePrintOptions
--- @field rlimit integer|nil Z3 resource limit of each unit (default `DEFAULT_RLIMIT`)
--- @field split table<string, boolean>|nil names of the units to check one assert at a time

local M = {}

-- about a second of solver work
M.DEFAULT_RLIMIT = 10000000

local OPS = {
    ['+'] = '+',
    ['-'] = '-',
    ['*'] = '*',
    mod = 'mod',
    ['<'] = '<',
    ['<='] = '<=',
    ['>'] = '>',
    ['>='] = '>=',
    ['=='] = '==',
    ['!='] = '!=',
    ['and'] = '&&',
    ['or'] = '||',
    ['=>'] = '==>',
}

--- Prints variable declarations as `name: sort` joined by commas.
--- @param core CoreArena
--- @param vars NodeId[]
--- @return string
local function bindings(core, vars)
    local out = {}
    for i, v in ipairs(vars) do
        local d = core.nodes[v]
        assert(d.tag == 'VarDecl', 'boogie.print: expected a VarDecl')
        out[i] = ('%s: %s'):format(d.name, d.sort)
    end
    return table.concat(out, ', ')
end

--- Prints a term. Compound operands are parenthesized, so Boogie's precedence never matters.
--- @param core CoreArena
--- @param id NodeId
--- @return string
local function term(core, id)
    --- @param kid NodeId
    --- @return string
    local function operand(kid)
        local k = core.nodes[kid]
        local s = term(core, kid)
        if k.tag == 'BinOp' or k.tag == 'Ite' or (k.tag == 'Int' and k.text:sub(1, 1) == '-') then
            return ('(%s)'):format(s)
        end
        return s
    end
    local n = core.nodes[id]
    if n.tag == 'Var' then
        return n.name
    elseif n.tag == 'Int' then
        return n.text
    elseif n.tag == 'Bool' then
        return tostring(n.value)
    elseif n.tag == 'BinOp' then
        return ('%s %s %s'):format(operand(n.lhs), OPS[n.op], operand(n.rhs))
    elseif n.tag == 'Not' then
        return ('!%s'):format(operand(n.arg))
    elseif n.tag == 'Ite' then
        return ('if %s then %s else %s'):format(operand(n.cond), operand(n.if_true), operand(n.if_false))
    elseif n.tag == 'Let' then
        return ('(var %s := %s; %s)'):format(n.name, term(core, n.value), term(core, n.body))
    elseif n.tag == 'App' then
        local args = {}
        for i, a in ipairs(n.args) do
            args[i] = term(core, a)
        end
        return ('%s(%s)'):format(n.fn, table.concat(args, ', '))
    elseif n.tag == 'Forall' then
        local triggers = {}
        for i, t in ipairs(n.triggers) do
            local terms = {}
            for j, kid in
                ipairs((core.nodes[t] --[[@as CoreTrigger]]).terms)
            do
                terms[j] = term(core, kid)
            end
            triggers[i] = ('{ %s } '):format(table.concat(terms, ', '))
        end
        return ('(forall %s :: %s%s)'):format(bindings(core, n.vars), table.concat(triggers), term(core, n.body))
    end
    error(('boogie.print: unhandled term %s'):format(n.tag))
end

--- Appends the lines of a statement list indented by `depth` levels.
--- @param core CoreArena
--- @param ids NodeId[]
--- @param depth integer
--- @param out string[]
--- @mut out
local function statements(core, ids, depth, out)
    local pad = ('  '):rep(depth)
    --- @param s string
    local function emit(s)
        out[#out + 1] = pad .. s
    end
    for _, id in ipairs(ids) do
        local n = core.nodes[id]
        if n.tag == 'Assign' then
            emit(('%s := %s;'):format(n.target, term(core, n.value)))
        elseif n.tag == 'Havoc' then
            emit(('havoc %s;'):format(n.target))
        elseif n.tag == 'Assume' then
            emit(('assume %s;'):format(term(core, n.cond)))
        elseif n.tag == 'Check' then
            emit(('assert {:msg "O%d"} %s;'):format(n.obligation, term(core, n.cond)))
        elseif n.tag == 'Branch' or n.tag == 'Choice' then
            -- an else list that holds only another Branch or Choice prints as `else if`, and an empty
            -- one prints no `else`
            local b = n --[[@as CoreBranch|CoreChoice]]
            local prefix = ''
            while true do
                local cond = '*'
                local first = b.first
                local second = b.second
                if b.tag == 'Branch' then
                    cond = term(core, b.cond)
                    first = b.then_body
                    second = b.else_body
                end
                emit(('%sif (%s) {'):format(prefix, cond))
                statements(core, first, depth + 1, out)
                local only = #second == 1 and core.nodes[second[1]]
                if not only or (only.tag ~= 'Branch' and only.tag ~= 'Choice') then
                    if #second > 0 then
                        emit '} else {'
                        statements(core, second, depth + 1, out)
                    end
                    emit '}'
                    break
                end
                prefix = '} else '
                b = only --[[@as CoreBranch|CoreChoice]]
            end
        elseif n.tag == 'Block' then
            -- label comes after the body, so if there is a goto within stmts it will still be valid
            statements(core, n.body, depth, out)
            emit(('%s:'):format(n.label))
        elseif n.tag == 'Exit' then
            emit(('goto %s;'):format(n.label))
        else
            error(('boogie.print: unhandled statement %s'):format(n.tag))
        end
    end
end

--- Prints the declarations and units of a valid core program as one Boogie file.
--- @param core CoreArena
--- @param decls NodeId[]
--- @param units NodeId[]
--- @param opts BoogiePrintOptions|nil
--- @return string
function M.program(core, decls, units, opts)
    local rlimit = (opts and opts.rlimit) or M.DEFAULT_RLIMIT
    local split = (opts and opts.split) or {}
    local out = {}
    for _, id in ipairs(decls) do
        local d = core.nodes[id]
        if d.tag == 'SortDecl' then
            out[#out + 1] = ('type %s;'):format(d.name)
        elseif d.tag == 'FunDecl' then
            out[#out + 1] = ('function %s(%s): %s;'):format(d.name, bindings(core, d.params), d.sort)
        elseif d.tag == 'Axiom' then
            out[#out + 1] = ('axiom %s;'):format(term(core, d.cond))
        else
            error(('boogie.print: unhandled declaration %s'):format(d.tag))
        end
    end
    for i, id in ipairs(units) do
        local u = core.nodes[id]
        assert(u.tag == 'Unit', 'boogie.print: expected a Unit')
        if i > 1 or #decls > 0 then
            out[#out + 1] = ''
        end
        local attrs = ('{:rlimit %d}'):format(rlimit)
        if u.arith == 'nonlinear' then
            attrs = attrs .. ' {:smt_option "smt.arith.nl", "true"}'
        end
        if split[u.name] then
            attrs = attrs .. ' {:vcs_split_on_every_assert}'
        end
        out[#out + 1] = ('procedure %s %s()'):format(attrs, u.name)
        out[#out + 1] = '{'
        for _, v in ipairs(u.vars) do
            local d = core.nodes[v]
            assert(d.tag == 'VarDecl', 'boogie.print: expected a VarDecl')
            out[#out + 1] = ('  var %s: %s;'):format(d.name, d.sort)
        end
        if #u.vars > 0 and #u.body > 0 then
            out[#out + 1] = ''
        end
        statements(core, u.body, 1, out)
        out[#out + 1] = '}'
    end
    return table.concat(out, '\n') .. (#out > 0 and '\n' or '')
end

return M
