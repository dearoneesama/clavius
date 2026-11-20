local arena = require 'clavius.ir.arena'
local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local dump = require 'clavius.sexpr.dump'
local read = require 'clavius.sexpr.read'
local utils = require 'pl.utils'
local validate = require 'clavius.validate'

--- A diagnostic for test comparison
--- @class DiagSummary
--- @field code DiagCode
--- @field tag string
--- @field args string[]

--- @param prog CoreProgram
--- @return DiagSummary[]
local function run(prog)
    local out = {}
    for i, d in ipairs(validate.run(prog.core, prog.units, prog.obligations, prog.assumptions)) do
        out[i] = { code = d.code, tag = prog.core.nodes[d.node].tag, args = d.args }
    end
    return out
end

--- Validates the core program in `text`.
--- @param text string
--- @return DiagSummary[]
local function diags(text)
    local prog, err = dump.read_core(text, 1)
    assert(prog, err and read.format_error(err))
    return run(prog)
end

describe('validate', function()
    it('accepts every fixture', function()
        local inputs = dir.getallfiles('tests/snapshots/boogie', '*.core.sexp')
        assert.is_true(#inputs > 0)
        for _, input in ipairs(inputs) do
            assert.are.same({}, diags(assert(utils.readfile(input, true))))
        end
    end)

    it('reports a Check with no obligation of a known kind', function()
        local text = [=[
            (Unit u [] [(Branch (Bool true) [(Check 2 (Bool true))] [(Check 1 (Bool true))])])
            (obligation 1 :kind frob :node 0)
        ]=]
        assert.are.same({
            { code = 'E-internal-check', tag = 'Check', args = { '2' } },
            { code = 'E-internal-check', tag = 'Check', args = { '1' } },
        }, diags(text))
    end)

    it('reports an Assume with no allowed justification', function()
        local text = [=[
            (Unit u [] [(Choice [(Assume 2 (Bool true))] [(Block b [(Assume 1 (Bool true))])])])
            (assumption 1 :kind makeup :node 0)
        ]=]
        assert.are.same({
            { code = 'E-internal-assume', tag = 'Assume', args = { '2' } },
            { code = 'E-internal-assume', tag = 'Assume', args = { '1' } },
        }, diags(text))
    end)

    it('reports a back_edge Assume that does not end its statement list', function()
        local text = [=[
            (Unit u [] [(Branch (Bool true) [(Assume 1 (Bool false)) (Check 1 (Bool true))] [(Assume 2 (Bool false))])])
            (obligation 1 :kind assert :node 0)
            (assumption 1 :kind back_edge :node 0)
            (assumption 2 :kind back_edge :node 0)
        ]=]
        assert.are.same({ { code = 'E-internal-back-edge', tag = 'Assume', args = { '1' } } }, diags(text))
    end)

    it('reports an Exit that no Block with its label encloses', function()
        local text = [=[
            (Unit u []
              [(Block a [(Exit a) (Block b [(Exit a) (Exit b)])])
               (Exit b)
               (Block c [])
               (Branch (Bool true) [(Exit c)] [])])
        ]=]
        assert.are.same({
            { code = 'E-internal-exit', tag = 'Exit', args = { 'b' } },
            { code = 'E-internal-exit', tag = 'Exit', args = { 'c' } },
        }, diags(text))
    end)

    it('reports a Block label used twice in a unit', function()
        local text = [=[
            (Unit u [] [(Block a []) (Block b [(Block a [(Exit a)])])])
            (Unit v [] [(Block a [])])
        ]=]
        assert.are.same({
            { code = 'E-internal-label', tag = 'Block', args = { 'a' } },
        }, diags(text))
    end)

    it('reports nodes out of place', function()
        local text = [=[
            (Unit u
              [(Havoc x)]
              [(Var x)
               (Assign x (BinOp + (Exit l) (Not (VarDecl y int))))
               (Unit v [] [])])
        ]=]
        assert.are.same({
            { code = 'E-internal-node', tag = 'Havoc', args = { 'Havoc', 'variable declaration' } },
            { code = 'E-internal-node', tag = 'Var', args = { 'Var', 'statement' } },
            { code = 'E-internal-node', tag = 'Exit', args = { 'Exit', 'term' } },
            { code = 'E-internal-node', tag = 'VarDecl', args = { 'VarDecl', 'term' } },
            { code = 'E-internal-node', tag = 'Unit', args = { 'Unit', 'statement' } },
        }, diags(text))
    end)

    it('reports a non-core node and a unit that is not a Unit', function()
        local c = arena.new_core()
        local sp = arena.span(1, 1, 0)
        local src = arena.add_core(c, { tag = 'Literal', kind = 'nil', text = 'nil' } --[[@as CoreNode]], sp)
        local statement = arena.add_core(c, { tag = 'Assign', target = 'x', value = src }, sp)
        local unit = arena.add_core(c, { tag = 'Unit', name = 'u', vars = {}, body = { statement } }, sp)
        assert.are.same({
            { code = 'E-internal-node', tag = 'Literal', args = { 'Literal', 'term' } },
            { code = 'E-internal-node', tag = 'Assign', args = { 'Assign', 'unit' } },
        }, run { core = c, units = { unit, statement }, obligations = {}, assumptions = {} })
    end)

    -- the obligations that elaborate emits, by id
    local PROGRAM = [=[
        ---@clavius begin
        local x = 1
        local y = x * 2 + 1 -- 1 (range): `x * 2` stays within ±2^53; 2 (range): so does `x * 2 + 1`
        assert(y > x) -- 3 (assert): the assertion holds
        if y > 2 then error() end -- 4 (unreachable): the `error` never runs
        ---@clavius end
        local z = x - 1 -- none: this line is outside the region
    ]=]

    --- Returns `body` without the `Check` statements of the obligations in `dropped`. The lists of its
    --- branches and blocks lose theirs too.
    --- @param core CoreArena
    --- @param body NodeId[]
    --- @param dropped table<integer, boolean>
    --- @return NodeId[]
    local function without_checks(core, body, dropped)
        local out = {}
        for _, id in ipairs(body) do
            local n = core.nodes[id]
            if n.tag == 'Branch' then
                n.then_body = without_checks(core, n.then_body, dropped)
                n.else_body = without_checks(core, n.else_body, dropped)
            elseif n.tag == 'Block' then
                n.body = without_checks(core, n.body, dropped)
            end
            if not (n.tag == 'Check' and dropped[n.obligation]) then
                out[#out + 1] = id
            end
        end
        return out
    end

    --- Elaborates `program`, removes the checks of the obligations in `dropped`, and returns what validate
    --- reports: each diagnostic's code, arguments and the first line of the source text of its span.
    --- @param program string
    --- @param dropped table<integer, boolean>
    --- @param relabel integer|nil an obligation whose kind becomes `assert`
    --- @return string[][]
    local function coverage(program, dropped, relabel)
        local c = driver.run_until('elaborate', program, 1)
        local prog = assert(c.prog)
        for _, id in ipairs(prog.units) do
            local unit = prog.core.nodes[id] --[[@as CoreUnit]]
            unit.body = without_checks(prog.core, unit.body, dropped)
        end
        if relabel then
            prog.obligations[relabel].kind = 'assert'
        end
        local out = {}
        local source = { src = c.src, index = assert(c.index), callees = assert(c.info).callees, cycle = assert(c.termination).cycle }
        for i, d in ipairs(validate.run(prog.core, prog.units, prog.obligations, prog.assumptions, source)) do
            local s = assert(d.span)
            out[i] = { d.code, d.args[1], d.args[2], program:sub(s.start, s.finish):match '^[^\n]*' }
        end
        return out
    end

    it('accepts the obligations that elaborate emits', function()
        assert.are.same({}, coverage(PROGRAM, {}, nil))
    end)

    it('reports a node in a region whose obligation has no Check', function()
        assert.are.same({
            { 'E-internal-coverage', 'BinOp', 'range', 'x * 2' },
            { 'E-internal-coverage', 'Call', 'assert', 'assert(y > x)' },
            { 'E-internal-coverage', 'Call', 'unreachable', 'error()' },
        }, coverage(PROGRAM, { [1] = true, [3] = true, [4] = true }, nil))
    end)

    it('reports an obligation of the wrong kind', function()
        assert.are.same({ { 'E-internal-coverage', 'BinOp', 'range', 'x * 2 + 1' } }, coverage(PROGRAM, {}, 2))
    end)

    -- the contract obligations that elaborate emits, by id
    local CONTRACTS = [=[
        ---@clavius
        ---@param n integer
        ---@pre n > 0
        ---@post result > n
        ---@return integer
        local function inc(n)
            return n + 1 -- 1 (range); 2 (post): the value meets `---@post`
        end -- 3 (missing_return): the end isn't reached
        ---@clavius
        ---@post true
        local function idle() end -- 4 (post): at the end
        ---@clavius begin
        local y = inc(1) -- 5 (pre): the argument meets `---@pre`
        ---@clavius end
    ]=]

    it('accepts the contract obligations that elaborate emits', function()
        assert.are.same({}, coverage(CONTRACTS, {}, nil))
    end)

    it('reports a call, a return and a function end whose contract obligation has no Check', function()
        assert.are.same({
            { 'E-internal-coverage', 'Call', 'pre', 'inc(1)' },
            { 'E-internal-coverage', 'Return', 'post', 'return n + 1' },
            { 'E-internal-coverage', 'Function', 'missing_return', 'function inc(n)' },
            { 'E-internal-coverage', 'Function', 'post', 'function idle() end' },
        }, coverage(CONTRACTS, { [2] = true, [3] = true, [4] = true, [5] = true }, nil))
    end)

    -- the loop obligations that elaborate emits, by id
    local LOOPS = [=[
        ---@clavius begin
        local i = 0
        -- 1 (invariant_entry); 3 (invariant_preserved); 4 (decrease)
        ---@invariant i >= 0
        ---@decrease 3 - i
        while i < 3 do
            i = i + 1 -- 2 (range)
        end
        -- 6 (decrease)
        ---@decrease 3 - i
        repeat
            i = i + 1 -- 5 (range)
        until i >= 3
        -- 7 (for_bound); 8 (invariant_entry) and 9 (invariant_preserved) of the counter's range
        for k = 1, 2 do
        end
        ---@clavius end
    ]=]

    -- the obligations of a recursive call that elaborate emits, by id
    local RECURSION = [=[
        ---@clavius
        ---@param n integer
        ---@pre n >= 0
        ---@decrease n
        local function down(n)
            if n > 0 then
                down(n - 1) -- 1 (range); 2 (pre); 3 (decrease): the call stays in the cycle
            end
        end
        ---@clavius begin
        down(3) -- 4 (pre): a call from outside the cycle checks no measure
        ---@clavius end
    ]=]

    it('accepts the obligations of a recursive call that elaborate emits', function()
        assert.are.same({}, coverage(RECURSION, {}, nil))
    end)

    it('reports a call in a cycle whose measure has no Check', function()
        assert.are.same({ { 'E-internal-coverage', 'Call', 'decrease', 'down(n - 1)' } }, coverage(RECURSION, { [3] = true }, nil))
    end)

    it('accepts the loop obligations that elaborate emits', function()
        assert.are.same({}, coverage(LOOPS, {}, nil))
    end)

    it('reports a loop whose invariant, measure or counter obligation has no Check', function()
        assert.are.same({
            { 'E-internal-coverage', 'While', 'invariant_entry', 'while i < 3 do' },
            { 'E-internal-coverage', 'While', 'invariant_preserved', 'while i < 3 do' },
            { 'E-internal-coverage', 'While', 'decrease', 'while i < 3 do' },
            { 'E-internal-coverage', 'Repeat', 'decrease', 'repeat' },
            { 'E-internal-coverage', 'Fornum', 'for_bound', 'for k = 1, 2 do' },
            { 'E-internal-coverage', 'Fornum', 'invariant_entry', 'for k = 1, 2 do' },
            { 'E-internal-coverage', 'Fornum', 'invariant_preserved', 'for k = 1, 2 do' },
        }, coverage(LOOPS, { [1] = true, [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true }, nil))
    end)
end)
