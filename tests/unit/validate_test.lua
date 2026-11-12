local arena = require 'clavius.ir.arena'
local dir = require 'pl.dir'
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
            (assumption 1 :kind invariant :node 0)
        ]=]
        assert.are.same({
            { code = 'E-internal-assume', tag = 'Assume', args = { '2' } },
            { code = 'E-internal-assume', tag = 'Assume', args = { '1' } },
        }, diags(text))
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
        local stmt = arena.add_core(c, { tag = 'Assign', target = 'x', value = src }, sp)
        local unit = arena.add_core(c, { tag = 'Unit', name = 'u', vars = {}, body = { stmt } }, sp)
        assert.are.same({
            { code = 'E-internal-node', tag = 'Literal', args = { 'Literal', 'term' } },
            { code = 'E-internal-node', tag = 'Assign', args = { 'Assign', 'unit' } },
        }, run({ core = c, units = { unit, stmt }, obligations = {}, assumptions = {} }))
    end)
end)
