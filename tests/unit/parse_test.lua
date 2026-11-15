local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local index = require 'clavius.ir.index'
local markers = require 'support.markers'
local parse = require 'clavius.syntax.parse'
local source_nodes = require 'clavius.ir.source_nodes'
local utils = require 'pl.utils'

--- Returns each diagnostic as `code arg` with the text its span covers.
--- @param text string
--- @return string[][]
local function diags_of(text)
    local p, diags = parse.run(text, 1)
    local out = {}
    for i, d in ipairs(diags) do
        local s = d.span or p.src.spans[d.node]
        out[i] = { d.code, d.args[1], text:sub(s.start, s.finish) }
    end
    return out
end

-- a snippet and the form's name for each form that luacheck accepts and the LuaJIT 2.1 grammar rejects
local REJECTED = {
    { 'x = 1 // 2', 'lua53-operator' },
    { 'x = 1 & 2', 'lua53-operator' },
    { 'x = 1 | 2', 'lua53-operator' },
    { 'x = 1 ~ 2', 'lua53-operator' },
    { 'x = 1 << 2', 'lua53-operator' },
    { 'x = 1 >> 2', 'lua53-operator' },
    { 'x = ~1', 'lua53-operator' },
    { 'local x = 1 x += 2', 'compound-assignment' },
    { 'local x <const> = 1', 'local-attribute' },
    { 'local a, b <close> = 1, 2', 'local-attribute' },
    { 'local x <frob> = 1', 'local-attribute' },
    { 'local a = 3x = 5', 'malformed-number' },
    { 'x = 1or 2', 'malformed-number' },
    { 'x = 0xffor 2', 'malformed-number' },
    { '; local x = 1', 'empty-statement' },
    { 'local x = 1;;', 'empty-statement' },
    { 'do ; end', 'empty-statement' },
    { 'while true do break; local x = 1 end', 'break-not-last' },
    { 'break', 'break-outside-loop' },
    { 'while true do local function f() break end end', 'break-outside-loop' },
    { 'local function f() return ... end', 'vararg-outside-vararg-function' },
    { 'local function f(...) return function() return ... end end', 'vararg-outside-vararg-function' },
}

-- snippets near the rejected forms that both accept
local ACCEPTED = {
    'local x = 1; local y = 2;',
    'return;',
    'while true do break end',
    'repeat break until true',
    'for i = 1, 2 do if i then break end end',
    'local x = ...',
    'local function f(...) return ... end',
    'local x = 1 < 2',
    'local a, b = 1 < 2, 3',
    'goto l; ::l::',
    'a = 1 or 2',
    'a = 0xff',
    'a = 1e5',
    'a = 1LL',
}

describe('syntax.luacheck', function()
    it('gives byte offsets after non-ASCII text', function()
        local text = "local s = 'é你好' -- ünïcode\nlocal y = 1"
        local p = parse.run(text, 1)
        local binders = {}
        for i, id in ipairs(index.build(p.src).by_tag.Binder) do
            binders[i] = text:sub(p.src.spans[id].start, p.src.spans[id].finish)
        end
        assert.are.same({ 's', 'y' }, binders)
    end)

    it('reports what luacheck rejects at its position', function()
        assert.are.same({ { 'E-syntax', "expected condition near 'then'", 'then' } }, diags_of 'if then end')
    end)

    it('reports each form that luacheck accepts and LuaJIT rejects', function()
        for _, c in ipairs(REJECTED) do
            local diags = diags_of(c[1])
            assert.are.equal(1, #diags, c[1])
            assert.are.same({ 'E-syntax', c[2] }, { diags[1][1], diags[1][2] }, c[1])
        end
    end)

    -- Recent LuaJIT 2.1 releases backport syntax from LuaJIT 3.0, such as empty statements, compound
    -- assignment and bit operators, so whether this LuaJIT loads a rejected form depends on its release.
    -- What Clavius accepts must load on every release.
    it('accepts only snippets that LuaJIT loads', function()
        local cases = { assert(utils.readfile('tests/snapshots/parse/all_kinds.lua', true)) }
        for _, c in ipairs(ACCEPTED) do
            cases[#cases + 1] = c
        end
        for _, text in ipairs(cases) do
            local _, diags = parse.run(text, 1)
            assert.are.same({}, diags, text)
            assert.is_function(loadstring(text), text)
        end
    end)

    it('rejects some syntax that LuaJIT accepts', function()
        for _, text in ipairs { 'local x = 0b101', 'local café = 1' } do
            assert.is_function(loadstring(text))
            assert.are.equal('E-syntax', diags_of(text)[1][1])
        end
    end)

    it('converts a method definition with an explicit self', function()
        local p = parse.run('function t:m(a) return self end', 1)
        local f = p.src.nodes[#p.src.nodes - 2] --[[@as SrcFunction]]
        assert.are.equal('Function', f.tag)
        assert.are.same({ 'self', 'a' }, { p.src.nodes[f.params[1]].name, p.src.nodes[f.params[2]].name })
    end)
end)

describe('syntax.comments', function()
    --- @param text string
    --- @return Comment
    local function comment(text)
        return { text = text, span = arena.span(1, 1, 0) }
    end

    it('reads directives in both spellings', function()
        local found = comments.directives {
            comment '-@clavius begin',
            comment '- @param x integer the count  ',
            comment '-@proof_by(bit_vector)',
            comment ' plain comment',
            comment '--@clavius begin',
            comment '-',
        }
        assert.are.same({
            { 'clavius', 'begin' },
            { 'param', 'x integer the count' },
            { 'proof_by', '(bit_vector)' },
        }, {
            { found[1].tag, found[1].args },
            { found[2].tag, found[2].args },
            { found[3].tag, found[3].args },
        })
        assert.are.equal(3, #found)
    end)

    it('reads annotation blocks', function()
        local found = comments.blocks { comment '@spec\nlocal x', comment '@proof x', comment '@specs', comment ' @lemma' }
        assert.are.same({ 'spec', 'proof' }, { found[1].kind, found[2].kind })
        assert.are.equal(2, #found)
    end)
end)

describe('syntax.splice', function()
    it('groups the statements between markers into regions', function()
        local p = parse.run(
            'local a = 1\n---@clavius begin\nlocal b = 2\nlocal c = 3 ---@clavius end\nlocal d = 4\n---@clavius begin\n---@clavius end\n',
            1
        )
        local root = p.src.nodes[p.root] --[[@as SrcBlock]]
        local tags, sizes = {}, {}
        for i, id in ipairs(root.statements) do
            local n = p.src.nodes[id]
            tags[i] = n.tag
            if n.tag == 'ClvRegion' then
                sizes[#sizes + 1] = #n.statements
            end
        end
        assert.are.same({ 'Local', 'ClvRegion', 'Local', 'ClvRegion' }, tags)
        assert.are.same({ 2, 0 }, sizes)
    end)

    it('reports misplaced markers', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius end
            --! E-misplaced-directive
            ---@clavius begin
            ---@clavius begin
            --! E-misplaced-directive
            local x = 1
            ---@clavius end
            do
                ---@clavius begin
                --! E-misplaced-directive
            end
            local function f()
                ---@clavius end
                --! E-misplaced-directive
            end
            local y = 1 +
                ---@clavius begin
                --! E-misplaced-directive
                2
            ---@clavius begin
            --! E-misplaced-directive
            ]=]
        )
    end)

    it('reports unsupported annotations', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@param x integer
            ---@clavius
            --! E-unsupported-feature
            local function f(x) end
            --[[@proof x ]]
            --[[@spec local function s() end ]] --! E-unsupported-feature
            ---@clavius begin
            ---@require x > 0
            --! E-unsupported-directive
            --- @type integer
            --! E-unsupported-directive
            local y = 1
            if y > 0 then
                --[[@proof assert(y > 0) ]] --! E-unsupported-feature
            end
            ---@clavius end
            ---@clavius frob
            --! E-syntax
            ]=]
        )
    end)
end)

describe('ir.index', function()
    it('lists nodes by kind and gives parents and regions', function()
        local p = parse.run('local a = 1\n---@clavius begin\nlocal b = a\n---@clavius end', 1)
        local idx = index.build(p.src)
        local ids = idx.by_tag.Binder
        assert.are.equal(2, #ids)
        local region = idx.by_tag.ClvRegion[1]
        assert.are.same({ 0, region }, { idx.region[ids[1]], idx.region[ids[2]] })
        assert.are.equal(p.root, idx.parent[region])
        assert.are.equal(0, idx.parent[p.root])
        assert.are.equal('Local', p.src.nodes[idx.parent[ids[2]]].tag)
    end)

    it('agrees with the children of every node', function()
        local text = assert(utils.readfile('tests/snapshots/parse/all_kinds.lua', true))
        local p = parse.run(text, 1)
        local idx = index.build(p.src)
        local listed = 0
        for tag, ids in pairs(idx.by_tag) do
            for i, id in ipairs(ids) do
                assert.are.equal(tag, p.src.nodes[id].tag)
                assert.is_true(i == 1 or ids[i - 1] < id)
            end
            listed = listed + #ids
        end
        assert.are.equal(#p.src.nodes, listed)
        local roots = 0
        for id, n in ipairs(p.src.nodes) do
            for _, kid in ipairs(source_nodes.children(n)) do
                assert.are.equal(id, idx.parent[kid])
            end
            if idx.parent[id] == 0 then
                roots = roots + 1
            end
        end
        assert.are.equal(1, roots)
        assert.are.equal(0, idx.parent[p.root])
    end)

    it('gives each node the region it is in at any depth', function()
        local p = parse.run(
            [=[
            local a = 1
            ---@clavius begin
            local b = 2
            if b > 1 then
                b = b + a
            end
            ---@clavius end
            local c = a
            ---@clavius begin
            local d = 4
            ---@clavius end
            ]=],
            1
        )
        local idx = index.build(p.src)
        local r1, r2 = unpack(idx.by_tag.ClvRegion)
        -- the regions themselves sit under the root Block, outside every region
        assert.are.same({ 0, 0 }, { idx.region[r1], idx.region[r2] })
        local binders = {}
        for i, id in ipairs(idx.by_tag.Binder) do
            binders[i] = {
                (p.src.nodes[id] --[[@as SrcBinder]]).name,
                idx.region[id],
            }
        end
        assert.is_nil(idx.by_tag.While)
        assert.are.same({ { 'a', 0 }, { 'b', r1 }, { 'c', 0 }, { 'd', r2 } }, binders)
        local ids = {}
        for i, id in ipairs(idx.by_tag.Id) do
            ids[i] = {
                (p.src.nodes[id] --[[@as SrcId]]).name,
                idx.region[id],
            }
        end
        -- `b` in `b > 1`, then `b` in target of `b = b + a`, then `b` in `b + a`, then `a` in `b + a`, then `a` in `local c = a`
        assert.are.same({ { 'b', r1 }, { 'b', r1 }, { 'b', r1 }, { 'a', r1 }, { 'a', 0 } }, ids)
        -- c, d are not Ids
    end)
end)
