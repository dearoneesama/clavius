local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local dump = require 'clavius.sexpr.dump'
local index = require 'clavius.ir.index'
local luacheck = require 'clavius.syntax.luacheck'
local markers = require 'support.markers'
local parse = require 'clavius.syntax.parse'
local source_nodes = require 'clavius.ir.source_nodes'
local stringx = require 'pl.stringx'
local utils = require 'pl.utils'
local write = require 'clavius.sexpr.write'

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
        -- a byte that can't be printed is quoted as an escape
        assert.are.same({ { 'E-syntax', "expected expression near '\\001'", '\1' } }, diags_of 'x = \1')
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
    local line = 0

    --- Makes a comment on the line after the last one made.
    --- @param text string
    --- @return Comment
    local function comment(text)
        line = line + 1
        return { text = text, span = arena.span(1, 1, 0), line = line }
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

    it('gives where the arguments are and the lines below a directive', function()
        local text = '---  @alias A  x \n---| 1\n--- text\n---@type A\n---| 2\n\n---| 3\n'
        local chunk = assert(luacheck.convert(arena.new_src(), text, 1))
        local found = {}
        for i, d in ipairs(comments.directives(chunk.comments)) do
            local next_lines = {}
            for j, c in ipairs(d.next_lines) do
                next_lines[j] = c.text
            end
            found[i] = { d.tag, text:sub(d.args_span.start, d.args_span.finish), next_lines }
        end
        assert.are.same({ { 'alias', 'A  x', { '-| 1', '- text' } }, { 'type', 'A', { '-| 2' } } }, found)
    end)

    it('reads the long comments that start with a tag', function()
        local found = comments.annotations { comment '@spec\nlocal x', comment '@proof_by(x)', comment ' @as T', comment '@ x', comment 'x' }
        assert.are.same({ 'spec', 'proof_by', 'as' }, { found[1].tag, found[2].tag, found[3].tag })
        assert.are.equal(3, #found)
    end)

    --- Makes a comment that spans `start` to `finish`.
    --- @param text string what luacheck gives: after `--`, and for a long comment inside its brackets
    --- @param start integer
    --- @param finish integer
    --- @return Comment
    local function at(text, start, finish)
        return { text = text, span = arena.span(1, start, finish), line = 1 }
    end

    it('finds the comments that hold ghost code, and where their code lies', function()
        local cases = {
            -- 12345678901234567890123
            -- --[==[ @proof l(1) ]==]
            { '--[==[ @proof l(1) ]==]', {}, { at(' @proof l(1) ', 1, 23) }, { { 'proof', 13, 20 } } },
            -- --[[@spec local s ]]
            { '--[[@spec local s ]]', {}, { at('@spec local s ', 1, 20) }, { { 'spec', 9, 19 } } },
            -- ---@ghost g = 0
            { '---@ghost g = 0', { at('-@ghost g = 0', 1, 15) }, {}, { { 'ghost', 9, 16 } } },
            -- ---@proof l(1)
            { '---@proof l(1)', { at('-@proof l(1)', 1, 14) }, {}, { { 'proof_line', 9, 15 } } },
            --   --- @assert x
            { '  --- @assert x', { at('- @assert x', 3, 15) }, {}, { { 'assert', 13, 16 } } },
            -- code comes first on the line, so LuaLS gives the comment to `x = 1`
            { 'x = 1 ---@ghost g = 0', { at('-@ghost g = 0', 7, 21) }, {}, {} },
            -- tags that aren't ghost code
            { '---@param n', { at('-@param n', 1, 11) }, {}, {} },
            { '--[[@as T]]', {}, { at('@as T', 1, 11) }, {} },
            -- ---@ghost g = 0
            -- --[[@proof l(g) ]]
            -- in source order, though long comments are read first
            {
                '---@ghost g = 0\n--[[@proof l(g) ]]',
                { at('-@ghost g = 0', 1, 15) },
                { at('@proof l(g) ', 17, 34) },
                { { 'ghost', 9, 16 }, { 'proof', 26, 33 } },
            },
        }
        for _, c in ipairs(cases) do
            local found = {}
            for i, gr in ipairs(comments.ghost_ranges(c[2], c[3], c[1])) do
                found[i] = { gr.kind, gr.head, gr.close }
            end
            assert.are.same({ c[1], c[4] }, { c[1], found })
        end
    end)

    it('blanks the markers and tags of ghost code and keeps every offset', function()
        local cases = {
            -- 12345678901234567890123
            -- --[==[ @proof l(1) ]==]
            { '--[==[ @proof l(1) ]==]', { { 'proof', 1, 23, 13, 20 } }, (' '):rep(13) .. ' l(1) ' .. (' '):rep(4) },
            -- ---@ghost g = 0
            { '---@ghost g = 0', { { 'ghost', 1, 15, 9, 16 } }, (' '):rep(9) .. ' g = 0' },
            -- ---@assert x > 0, whose opening and tag make room for the statement `local _ =`
            { '---@assert x > 0', { { 'assert', 1, 16, 10, 17 } }, ' local _ = x > 0' },
            -- f()
            -- ---@ghost g = 1
            -- g()
            -- the text around the ranges stays
            { 'f()\n---@ghost g = 1\ng()', { { 'ghost', 5, 19, 13, 20 } }, 'f()\n' .. (' '):rep(9) .. ' g = 1\ng()' },
        }
        for _, c in ipairs(cases) do
            local ranges = {}
            for i, r in ipairs(c[2]) do
                ranges[i] = { kind = r[1], span = arena.span(1, r[2], r[3]), head = r[4], close = r[5] }
            end
            assert.are.same({ c[1], c[3] }, { c[1], comments.unmask(c[1], ranges) })
        end
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

    it('places the directives above a function that is marked or in a region', function()
        local p = parse.run(
            stringx.dedent [=[
            ---@param n integer
            ---@clavius
            ---@pre n > 0
            local function f(n) end
            ---@param x integer
            ---@frob
            local function g(x) end
            ---@unsafe
            ---@post true
            function h() end
            ---@clavius begin
            ---@return boolean
            local k = function() end
            ---@clavius end
            ---@clavius
            ---@pre true
            local l = function() end
            ]=],
            1
        )
        local found = {}
        for i, id in ipairs(index.build(p.src).by_tag.Function) do
            local n = p.src.nodes[id] --[[@as SrcFunction]]
            found[i] = {}
            for j, d in ipairs(n.directives) do
                found[i][j] = p.src.nodes[d].tag
            end
        end
        assert.are.same({
            { 'ClvParam', 'ClvMarker', 'ClvPre' },
            {},
            { 'ClvUnsafe', 'ClvPost' },
            { 'ClvReturn' },
            { 'ClvMarker', 'ClvPre' },
        }, found)
    end)

    it('parses the directives above functions in a region into the functions', function()
        local text = stringx.dedent [=[
            ---@clavius begin
            ---@param n integer
            ---@pre n > 0
            local function f(n) return n end

            ---@param m integer
            ---@return integer
            local g = function(m) return m + 1 end
            ---@clavius end
        ]=]
        local p, diags = parse.run(text, 1)
        assert.are.same({}, diags)
        assert.are.equal(
            '(Block [(ClvRegion [(LocalFunction (Binder f) (Function '
                .. '[(ClvParam n false (ClvTypeName integer)) (ClvPre (BinOp gt (Id n) (Literal number 0)))] '
                .. '[(Binder n)] false (Block [(Return [(Id n)])]))) '
                .. '(Local [(Function '
                .. '[(ClvParam m false (ClvTypeName integer)) (ClvReturn nil (ClvTypeName integer))] '
                .. '[(Binder m)] false (Block [(Return [(BinOp add (Id m) (Literal number 1))])]))] [(Binder g)])])])',
            write.flat(dump.write_src(p.src, p.root, {}))
        )
    end)

    it('reports misplaced directives in marked code', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@param x integer
            ---@frob
            local y = 1
            ---@clavius
            --! E-misplaced-directive
            local z = 1
            ---@clavius begin
            ---@pre x > 0
            --! E-misplaced-directive
            local a = 1
            local b = { 1,
                ---@type integer
                --! E-misplaced-directive
                2 }
            ---@frob
            local c = 1
            ---@invariant c > 0
            --! E-misplaced-directive
            local d = c ---@type integer
            --! E-unsupported-directive
            ---@pre d > 0
            --! E-misplaced-directive
            ---@clavius end
            ---@clavius
            local function f(n)
                local m = n
                ---@pre m > 0
                --! E-misplaced-directive
            end
            ---@unsafe
            local function g()
                ---@frob
                local h = 1
            end
            ]=]
        )
    end)

    it('places the directives above a loop in marked code into the loop', function()
        local p, diags = parse.run(
            stringx.dedent [=[
            ---@invariant x > 0
            while x do end
            ---@clavius begin
            ---@invariant i >= 1
            ---@decrease n - i
            while i < n do end
            ---@invariant true
            repeat until true
            ---@decrease 1
            for j = 1, 2 do end
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, diags)
        local loops = {}
        for _, id in ipairs(p.src.nodes[p.root].statements) do
            local n = p.src.nodes[id]
            if n.tag == 'ClvRegion' then
                for _, s in ipairs(n.statements) do
                    loops[#loops + 1] = write.flat(dump.write_src(p.src, s, {}))
                end
            else
                loops[#loops + 1] = write.flat(dump.write_src(p.src, id, {}))
            end
        end
        assert.are.same({
            '(While [] (Id x) (Block []))',
            '(While [(ClvInvariant (BinOp ge (Id i) (Literal number 1))) (ClvDecrease [(BinOp sub (Id n) (Id i))])] '
                .. '(BinOp lt (Id i) (Id n)) (Block []))',
            '(Repeat [(ClvInvariant (Literal true true))] (Block []) (Literal true true))',
            '(Fornum [(ClvDecrease [(Literal number 1)])] (Literal number 1) (Literal number 2) nil (Binder j) (Block []))',
        }, loops)
    end)

    it('reports loop directives above anything but a loop, and function directives above a loop', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            local i = 1
            ---@invariant i > 0
            --! E-misplaced-directive
            i = 2
            ---@decrease i
            --! E-misplaced-directive
            if i > 0 then end
            ---@pre i > 0
            --! E-misplaced-directive
            while i > 0 do end
            ---@invariant i > 0
            --! E-misplaced-directive
            local function f() end
            ---@clavius end
            ]=]
        )
    end)

    it('reports what it places but does not accept', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            local a = 1 ---@type integer
            --! E-unsupported-directive
            local b = 2
            local c = 3
            ---@param x
            --! E-syntax
            local function f(x)
                ---@type integer
                --! E-unsupported-directive
                local m = x
                ---@pre m > 0
                --! E-misplaced-directive
                local n = m
            end
            ---@clavius end
            ]=]
        )
    end)

    it('reports a directive in a parameter list, and function marks above nothing anywhere', function()
        markers.expect_diags(
            'parse',
            [=[
            local t = {
                ---@type integer
                ---@unsafe
                --! E-misplaced-directive
                1 }
            ---@clavius begin
            local function f(a,
                ---@param a integer
                --! E-misplaced-directive
                b)
            end
            ---@clavius end
            local u = 1
            ---@clavius
            --! E-misplaced-directive
            ]=]
        )
    end)

    it('leaves a directive that a blank line separates from the statement above none', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius
            --! E-misplaced-directive

            local function f() end
            ---@param x integer

            local function g(x) end
            ---@clavius begin
            ---@pre x > 0
            --! E-misplaced-directive

            -- a comment line keeps the next directive above its statement
            ---@param y integer
            -- the parameter
            local function h(y) end
            ---@clavius end
            ]=]
        )
    end)

    it('reads ghost blocks, and reports long-comment directives in marked code', function()
        markers.expect_diags(
            'parse',
            [=[
            --[[@proof x ]]
            local x = 1 --[[@as integer]]
            --[[@spec local function s() end ]]
            ---@clavius begin
            local y = 1 --[[@as integer]] --! E-unsupported-directive
            if y > 0 then
                --[[@proof assert(y > 0) ]]
            end
            ---@unsafe
            ---@return integer
            local function u()
                local a = 1 --[[@as integer]]
                return a
            end
            ---@clavius end
            ---@clavius
            local function f()
                --[[@proof assert(true) ]]
            end
            ---@clavius frob
            --! E-syntax
            ]=]
        )
    end)
end)

describe('syntax.luacheck ghost code', function()
    it('rejects ghost code that holds part of a statement or joins exec code', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            local x = 1
            local y = x --[[@proof + 1 ]] --! E-misplaced-directive
            --[[@proof if x > 0 then ]] --! E-misplaced-directive
            x = 2
            --[[@proof end ]]
            local t = { 1,
                --[[@proof 2 ]] --! E-misplaced-directive
            }
            ---@clavius end
            ]=]
        )
    end)

    it('rejects ghost code inside ghost code, which takes no tags', function()
        markers.expect_diags(
            'parse',
            [===[
            --[[@lemma
            ---@param n Nat
            local function l(n)
                ---@assert n >= 0
                --! E-misplaced-directive
            end
            ]]
            --[==[@lemma
            local function m()
                --[[@proof l(1) ]] --! E-misplaced-directive
            end
            ]==]
            --[[@spec
            ---@return Int
            local function s()
                ---@proof l(1)
                --! E-misplaced-directive
                return 1
            end
            ]]
            ]===]
        )
    end)

    it('rejects blocks below the top level and lines that hold more than they may', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            local function f()
                --[[@spec local function s() end ]] --! E-misplaced-directive
            end
            local y = 0
            ---@ghost local a = 1; y = 2 --! E-mode
            ---@assert y, a --! E-syntax
            ---@clavius end
            ]=]
        )
    end)

    it('reports syntax errors in ghost code, and reads a block with no code as nothing', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            --[[@proof ]]
            local t = { 1,
                --[[@proof -- a note ]]
                2 }
            ---@ghost local = 1 --! E-syntax
            ---@clavius end
            ]=]
        )
    end)

    it('reports ghost code after an exec `return` and a `return` that ends ghost code in exec code', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            local function after(a)
                if a then
                    return
                end
                ---@ghost local g = 0
                return
                ---@ghost local h = 0
                --! E-misplaced-directive
                --[[@proof h = 1 ]] --! E-misplaced-directive
            end
            local function returns()
                --[[@proof return ]] --! E-mode
                local y = 1
                ---@proof return
                --! E-mode
                ---@ghost return
                --! E-mode
            end
            local function inside()
                -- parses, since the `return` ends its own block; resolve rejects it
                --[[@proof
                    if true then
                        return
                    end
                ]]
                local z = 1
            end
            ---@clavius end
            local function plain()
                return
                ---@ghost local g = 0
            end
            ]=]
        )
    end)

    it('keeps `break` last on each side of the ghost and exec boundary', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            while true do
                break
                ---@ghost local g = 0
                --! E-misplaced-directive
            end
            --[[@proof
                while true do
                    break
                    local z = 1 --! E-syntax
                end
            ]]
            ---@clavius end
            ]=]
        )
    end)

    it('leaves ghost code in unmarked code a comment, even when it would not parse', function()
        markers.expect_diags(
            'parse',
            [=[
            --[[@proof this is not code ]]
            ---@assert )
            ---@clavius begin
            ---@unsafe
            local function trusted()
                --[[@proof neither is this ]]
            end
            ---@clavius end
            ---@ghost local g = 0
            --! E-misplaced-directive
            ---@clavius
            local function f() end
            ]=]
        )
    end)

    it('takes the innermost marking of nested marked and unsafe functions', function()
        markers.expect_diags(
            'parse',
            [=[
            ---@clavius begin
            ---@unsafe
            local function trusted()
                --[[@proof not code ]]
                local a = 1 --[[@as integer]]

                ---@clavius
                local function checked()
                    ---@ghost local g = 0
                    local b = 1 --[[@as integer]] --! E-unsupported-directive

                    ---@unsafe
                    local function inner()
                        --[[@proof nor this ]]
                        local c = 1 --[[@as integer]]
                    end
                end
            end
            ---@clavius end
            ---@clavius
            local function outer()
                ---@unsafe
                local function trusted_too()
                    ---@ghost local h = 0
                    --! E-misplaced-directive
                    ---@clavius
                    local function checked_too() end
                end
            end
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

    it('gives each node the ghost code it is in at any depth', function()
        local p = parse.run(
            [=[
            ---@clavius begin
            local x = 1
            ---@ghost local g = x
            --[[@proof
                local q = g
                if q > 0 then
                    local r = q
                end
            ]]
            ---@assert g >= 0
            ---@clavius end
            --[[@spec
            ---@param n Nat
            ---@return Nat
            local function s(n)
                return n
            end
            ]]
            ]=],
            1
        )
        local idx = index.build(p.src)

        --- @param id NodeId
        --- @return string
        local function ghost_tag(id)
            local g = idx.ghost[id]
            return g == 0 and '-' or p.src.nodes[g].tag
        end

        local found = {}
        for _, tag in ipairs { 'Binder', 'Id' } do
            for _, id in ipairs(idx.by_tag[tag]) do
                found[#found + 1] = {
                    (p.src.nodes[id] --[[@as SrcBinder|SrcId]]).name,
                    ghost_tag(id),
                }
            end
        end
        assert.are.same({
            -- binders
            { 'x', '-' },
            { 'g', 'ClvGhost' },
            { 'q', 'ClvProof' },
            { 'r', 'ClvProof' },
            { 's', 'ClvSpec' },
            { 'n', 'ClvSpec' },
            -- names read: `x` in `g = x`, `g` in `q = g`, `q` twice, `g` in the assert, `n` in `return n`
            { 'x', 'ClvGhost' },
            { 'g', 'ClvProof' },
            { 'q', 'ClvProof' },
            { 'q', 'ClvProof' },
            { 'g', 'ClvAssert' },
            { 'n', 'ClvSpec' },
        }, found)
        -- ghost code itself is in no ghost code, since it never nests
        for _, tag in ipairs { 'ClvGhost', 'ClvProof', 'ClvAssert', 'ClvSpec' } do
            assert.are.same({ tag, '-' }, { tag, ghost_tag(idx.by_tag[tag][1]) })
        end
    end)
end)
