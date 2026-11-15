local boogie_output = require 'clavius.backend.boogie.output'
local boogie_print = require 'clavius.backend.boogie.print'
local dir = require 'pl.dir'
local dump = require 'clavius.sexpr.dump'
local snapshot = require 'support.snapshot'
local read = require 'clavius.sexpr.read'
local stringx = require 'pl.stringx'
local utils = require 'pl.utils'

--- @param text string
--- @return CoreProgram
local function read_core(text)
    local prog, err = dump.read_core(text, 1)
    assert(prog, err and read.format_error(err))
    return prog
end

describe('boogie.print', function()
    -- tests/snapshots/boogie/<NAME>.core.sexp is printed into <NAME>.bpl
    local inputs = dir.getallfiles('tests/snapshots/boogie', '*.core.sexp')
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        it(input, function()
            local prog = read_core(assert(utils.readfile(input, true)))
            snapshot.check((input:gsub('%.core%.sexp$', '.bpl')), boogie_print.program(prog.core, prog.units, nil))
        end)
    end

    it('prints the resource limit and splits the units it is asked to', function()
        local prog = read_core '(Unit a [] []) (Unit b [] [(Havoc x)])'
        assert.are.equal(
            table.concat({
                'procedure {:rlimit 5} a()',
                '{',
                '}',
                '',
                'procedure {:rlimit 5} {:vcs_split_on_every_assert} b()',
                '{',
                '  havoc x;',
                '}',
                '',
            }, '\n'),
            boogie_print.program(prog.core, prog.units, { rlimit = 5, split = { b = true } })
        )
    end)

    it('prints nothing for no units', function()
        assert.are.equal('', boogie_print.program(read_core('').core, {}, nil))
    end)
end)

describe('boogie.output', function()
    it('reads the labels of failing asserts', function()
        local result = boogie_output.parse(stringx.dedent [=[
            O2
            Execution trace:
                f.bpl(11,3): anon0
            O5
            Execution trace:
                f.bpl(11,3): anon0
                f.bpl(13,59): anon3_Else

            Boogie program verifier finished with 1 verified, 2 errors
        ]=])
        assert.are.same({ failed = { 2, 5 }, out_of_resource = {} }, result)
    end)

    it('reads the procedures that ran out of resources', function()
        local result = boogie_output.parse(stringx.dedent [=[
            f.bpl(1,30): Verification out of resource (cubes)
            O4
            Execution trace:
                f.bpl(8,3): anon0

            Boogie program verifier finished with 0 verified, 1 error, 1 out of resource
        ]=])
        assert.are.same({ failed = { 4 }, out_of_resource = { 'cubes' } }, result)
    end)

    it('ignores prover noise around a verdict', function()
        local result = boogie_output.parse(stringx.dedent [=[
            Prover error: Invalid PING response from the prover: (error "line 58 column 7: push canceled")

            O1
            Execution trace:
                f.bpl(2,3): anon0

            Boogie program verifier finished with 0 verified, 1 error
        ]=])
        assert.are.same({ failed = { 1 }, out_of_resource = {} }, result)
    end)

    it('reads labels after a position and lines without one', function()
        local text = stringx.dedent [=[
            f.bpl(9,3): Error: O2
            Execution trace:
                f.bpl(8,3): anon0
            Verification out of resource (cubes)

            Boogie program verifier finished with 0 verified, 1 error, 1 out of resource
        ]=]
        for _, t in ipairs { text, stringx.replace(text, '\n', '\r\n') } do
            assert.are.same({ failed = { 2 }, out_of_resource = { 'cubes' } }, boogie_output.parse(t))
        end
    end)

    it('ignores lines that only end like a label', function()
        local result = boogie_output.parse(stringx.dedent [=[
            Prover error: no model for PO7

            Boogie program verifier finished with 1 verified, 0 errors
        ]=])
        assert.are.same({ failed = {}, out_of_resource = {} }, result)
    end)

    it('reports output without a verdict', function()
        local cases = {
            { 'sh: 1: boogie: not found\n', 'Boogie gave no verdict' },
            { 'f.bpl(3,2): Error: undeclared identifier: y\n1 name resolution errors detected in f.bpl\n', 'Boogie could not check the program' },
            {
                'f.bpl(3,23): Error: invalid argument types (int and bool) to binary operator +\n1 type checking errors detected in f.bpl\n',
                'Boogie could not check the program',
            },
            { 'f.bpl(2,1): error: ")" expected\n1 parse errors detected in f.bpl\n', 'Boogie could not check the program' },
            { 'Fatal Error: ProverException: Cannot find specified prover: /nowhere/z3\n', 'Boogie could not check the program' },
            -- outcomes that may hide failing asserts
            { 'Boogie program verifier finished with 0 verified, 0 errors, 1 time out\n', 'Boogie reported 1 time out' },
        }
        for _, c in ipairs(cases) do
            assert.are.same({ nil, c[2] }, { boogie_output.parse(c[1]) })
        end
    end)
end)
