local dir = require 'pl.dir'
local dump = require 'clavius.sexpr.dump'
local read = require 'clavius.sexpr.read'
local utils = require 'pl.utils'
local write = require 'clavius.sexpr.write'

--- @param text string
--- @return CoreProgram
local function read_core(text)
    local prog, err = dump.read_core(text, 1)
    assert(prog, err and read.format_error(err))
    return prog
end

--- Returns `line:col: message` for the error that reading `text` gives.
--- @param text string
--- @return string
local function read_error(text)
    local prog, err = dump.read_core(text, 1)
    assert.is_nil(prog)
    return read.format_error(assert(err))
end

describe('sexpr.dump', function()
    it('reads nodes children first with their fields and spans', function()
        local text = '(Unit u [(VarDecl p bool)] [(Check 1 (Not (Var p)))])\n(obligation 1 :kind assert :node 7)'
        local prog = read_core(text)
        local c = prog.core
        assert.are.same({
            { tag = 'VarDecl', name = 'p', sort = 'bool' },
            { tag = 'Var', name = 'p' },
            { tag = 'Not', arg = 2 },
            { tag = 'Check', obligation = 1, cond = 3 },
            { tag = 'Unit', name = 'u', vars = { 1 }, body = { 4 } },
        }, c.nodes)
        assert.are.same({ 5 }, prog.units)
        assert.are.same({ { kind = 'assert', node = 7 } }, prog.obligations)
        assert.are.same({ file = 1, start = 1, finish = 53 }, c.spans[5])
        assert.are.equal('(Not (Var p))', text:sub(c.spans[3].start, c.spans[3].finish))
    end)

    it('reads strings, booleans, negative integers and records in any order', function()
        local prog = read_core [=[
            (assumption 1 :kind branch :node 2)
            (Unit "a b" [] [(Assign x (Ite (Bool false) (Int -3) (Int 4)))])
            (assumption 2 :node 0 :kind type_fact)
            (assumption 3 :kind trusted :decl 9 :node 4)
            (obligation 1 :kind pre :node 3 :clause 1)
        ]=]
        assert.are.same({ 'a b', false, '-3' }, { prog.core.nodes[6].name, prog.core.nodes[1].value, prog.core.nodes[2].text })
        assert.are.same({
            { kind = 'branch', node = 2 },
            { kind = 'type_fact', node = 0 },
            { kind = 'trusted', node = 4, decl = 9 },
        }, prog.assumptions)
        assert.are.same({ { kind = 'pre', node = 3, clause = 1 } }, prog.obligations)
        local again = read_core(write.write_all(dump.write_core(prog)))
        assert.are.same({ prog.obligations, prog.assumptions }, { again.obligations, again.assumptions })
    end)

    it('round-trips every fixture', function()
        local inputs = dir.getallfiles('tests/snapshots/boogie', '*.core.sexp')
        assert.is_true(#inputs > 0)
        for _, input in ipairs(inputs) do
            local prog = read_core(assert(utils.readfile(input, true)))
            local again = read_core(write.write_all(dump.write_core(prog)))
            assert.are.same(prog.core.nodes, again.core.nodes)
            assert.are.same({ prog.units, prog.obligations, prog.assumptions }, { again.units, again.obligations, again.assumptions })
        end
    end)

    it('writes strings that are not symbols quoted', function()
        local prog = read_core '(Unit "a b" [] [(Havoc x)])'
        assert.are.equal('(Unit "a b" [] [(Havoc x)])\n', write.write_all(dump.write_core(prog)))
    end)

    it('reports shape errors with line and column', function()
        local cases = {
            { '(Unit u [] [(Frob 1)])', '1:14: unknown core kind Frob' },
            { '(Unit u [] [(Havoc)])', '1:13: Havoc takes 1 fields, found 0' },
            { '(Unit u [] [(Check x (Bool true))])', '1:20: expected an integer' },
            { '(Unit u [] [(Assign x (Bool yes))])', '1:29: expected true or false' },
            { '(Unit u [] [(Assign x (BinOp ^ (Int 1) (Int 2)))])', '1:30: op must be one of + - * mod < <= > >= == != and or =>' },
            { '(Unit u [] (Havoc x))', '1:12: expected a [ … ] list for body' },
            { '(Unit u [] [x])', '1:13: expected a core node' },
            { '(Unit u [] [(Havoc [x])])', '1:20: expected a symbol for target' },
            { '(Unit u [(VarDecl x [int])] [])', '1:21: expected a symbol for sort' },
            { '(Havoc x)', '1:1: expected a declaration, Unit, obligation or assumption' },
            { 'x', '1:1: expected a declaration, Unit, obligation or assumption' },
            { '(obligation 2 :kind assert :node 0)', '1:1: expected obligation id 1: ids count up from 1' },
            { '(obligation 1 :kind assert)', '1:1: obligation needs :kind with a symbol and :node' },
            { '(assumption 1 :kind "x" :node 0)', '1:1: assumption needs :kind with a symbol and :node' },
            { '(obligation 1 :kind assert :kind range :node 0)', '1:28: duplicate :kind' },
            { '(obligation 1 :kind assert :node)', '1:28: expected :kind, :node or :clause with a value' },
            { '(Unit u [] [(Havoc x)]', '1:1: unclosed (' },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], read_error(c[1]))
        end
    end)
end)
