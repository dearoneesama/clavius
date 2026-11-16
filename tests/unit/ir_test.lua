local arena = require 'clavius.ir.arena'
local core_nodes = require 'clavius.ir.core_nodes'
local diag = require 'clavius.ir.diag'
local source_nodes = require 'clavius.ir.source_nodes'

describe('ir.arena', function()
    it('gives ids in order and keeps spans parallel', function()
        local a = arena.new_src()
        local s1 = arena.span(1, 1, 1)
        local s2 = arena.span(1, 3, 5)
        local x = arena.add_src(a, { tag = 'Id', name = 'x' }, s1)
        local blk = arena.add_src(a, { tag = 'Block', statements = { x } }, s2)
        assert.are.same({ 1, 2 }, { x, blk })
        assert.are.equal(s2, a.spans[blk])
        assert.are.equal(2, #a.nodes)
    end)

    it('rejects a child whose id is not smaller than its parent', function()
        local a = arena.new_src()
        local sp = arena.span(1, 1, 0)
        assert.has_error(function()
            arena.add_src(a, { tag = 'Block', statements = { 1 } }, sp)
        end)
        local c = arena.new_core()
        assert.has_error(function()
            arena.add_core(c, { tag = 'Not', arg = 1 }, sp)
        end)
    end)

    it('lets core nodes share a child', function()
        local c = arena.new_core()
        local sp = arena.span(1, 1, 0)
        local v = arena.add_core(c, { tag = 'Var', name = 'x$1' }, sp)
        local t = arena.add_core(c, { tag = 'BinOp', op = '+', lhs = v, rhs = v }, sp)
        arena.add_core(c, { tag = 'Check', obligation = 1, cond = t }, sp)
        arena.add_core(c, { tag = 'Assign', target = 'y$2', value = t }, sp)
        assert.are.equal(4, #c.nodes)
        assert.are.same({ v, v }, core_nodes.children(c.nodes[t]))
    end)

    it('allows empty spans and rejects inverted ones', function()
        assert.are.same({ file = 1, start = 4, finish = 3 }, arena.span(1, 4, 3))
        assert.has_error(function()
            arena.span(1, 4, 2)
        end)
    end)

    it('converts offsets to lines and columns', function()
        local text = 'ab\n\ncd\n'
        local starts = arena.line_starts(text)
        assert.are.same({ 1, 4, 5, 8 }, starts)
        local cases = { { 1, 1, 1 }, { 3, 1, 3 }, { 4, 2, 1 }, { 5, 3, 1 }, { 6, 3, 2 }, { 8, 4, 1 } }
        for _, c in ipairs(cases) do
            assert.are.same({ c[2], c[3] }, { arena.line_col(text, starts, c[1]) })
        end
    end)

    it('counts columns in code points', function()
        local text = "x\n'é你' y"
        -- `y` is byte 11, after a 2-byte and a 3-byte character
        assert.are.same({ 2, 6 }, { arena.line_col(text, arena.line_starts(text), 11) })
    end)
end)

describe('ir.diag', function()
    it('places diagnostics at a node or at a span', function()
        local sp = arena.span(1, 2, 5)
        local d = diag.at_span('E-syntax', sp, { 'unexpected symbol' })
        assert.are.same({ 0, sp }, { d.node, d.span })
        assert.are.same({ 2 }, { diag.at_node('E-internal-node', 2, {}).node })
        assert.is_nil(diag.at_node('E-internal-node', 2, {}).span)
    end)
end)

describe('generated children', function()
    it('lists children in field order, which is evaluation order', function()
        assert.are.same({ 5, 6, 1, 2 }, source_nodes.children { tag = 'Local', values = { 5, 6 }, names = { 1, 2 } })
        assert.are.same({ 3, 4, 9 }, source_nodes.children { tag = 'If', arms = { 3, 4 }, else_block = 9 })
        assert.are.same({ 3 }, source_nodes.children { tag = 'If', arms = { 3 }, else_block = nil })
        assert.are.same({ 1, 2 }, source_nodes.children { tag = 'IfArm', cond = 1, body = 2 })
        assert.are.same({ 7, 8, 9 }, core_nodes.children { tag = 'Branch', cond = 7, then_body = { 8 }, else_body = { 9 } })
        assert.are.same({ 7, 8 }, core_nodes.children { tag = 'BinOp', op = '+', lhs = 7, rhs = 8 })
    end)

    it('gives leaves no children', function()
        assert.are.same({}, source_nodes.children { tag = 'Id', name = 'x' })
        assert.are.same({}, core_nodes.children { tag = 'Int', text = '1' })
    end)
end)
