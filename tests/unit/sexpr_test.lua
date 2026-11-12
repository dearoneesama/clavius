local dir = require 'pl.dir'
local snapshot = require 'support.snapshot'
local utils = require 'pl.utils'
local read = require 'clavius.sexpr.read'
local write = require 'clavius.sexpr.write'

--- Copies a tree without the reader's `start` offsets, so read results compare with built trees.
--- @param x Sexp
--- @return Sexp
local function strip(x)
    if x.tag == 'Sym' then
        return write.sym(x.text)
    elseif x.tag == 'Str' then
        return write.str(x.text)
    end
    local items = {}
    for i, item in ipairs(x.items) do
        items[i] = strip(item)
    end
    return x.tag == 'List' and write.list(items) or write.vec(items)
end

--- Reads the one s-expression in `text`, without its `start` offsets.
--- @param text string
--- @return Sexp
local function read_one(text)
    local xs, err = read.read_all(text)
    assert(xs, err and read.format_error(err))
    assert.are.equal(1, #xs)
    return strip(xs[1])
end

--- @param text string
--- @return SexpReadError
local function read_error(text)
    local x, err = read.read_all(text)
    assert.is_nil(x)
    return assert(err)
end

describe('sexpr.read', function()
    it('reads lists, vectors, symbols and strings', function()
        assert.are.same(
            write.list({
                write.sym 'Local',
                write.vec({ write.list({ write.sym 'Binder', write.sym 'y$2' }) }),
                write.str 'x y',
                write.sym ':rec',
                write.sym 'false',
            }),
            read_one '(Local [(Binder y$2)] "x y" :rec false)'
        )
    end)

    it('skips whitespace and comments', function()
        local xs = assert(read.read_all '; header\n(a) ; trailing\n\n  b ;; end')
        assert.are.same({ write.list({ write.sym 'a' }), write.sym 'b' }, { strip(xs[1]), strip(xs[2]) })
    end)

    it('records start offsets', function()
        local x = assert(read.read_all '  (a "b")')[1]
        assert(x.tag == 'List')
        assert.are.equal(3, x.start)
        assert.are.equal(4, x.items[1].start)
        assert.are.equal(6, x.items[2].start)
    end)

    it('decodes escapes', function()
        assert.are.same(write.str 'a"b\\c\nd\te\rf\0g\255', read_one [["a\"b\\c\nd\te\rf\0g\255"]])
    end)

    it('ends a symbol at a delimiter', function()
        assert.are.same(write.list({ write.sym 'a', write.str 'b', write.vec({ write.sym 'c' }) }), read_one '(a"b"[c])')
    end)

    it('reports errors with line and column', function()
        local cases = {
            { '(a\n  (b)', 1, 1, 'unclosed (' },
            { '[a b', 1, 1, 'unclosed [' },
            { 'a)', 1, 2, 'unexpected )' },
            { '(a\n b]', 2, 3, 'expected ), found ]' },
            { '(a "bc', 1, 4, 'unterminated string' },
            { '"a\\q"', 1, 3, 'bad escape in string' },
            { '"\\256"', 1, 2, 'bad escape in string' },
        }
        for _, c in ipairs(cases) do
            local err = read_error(c[1])
            assert.are.same({ c[2], c[3], c[4] }, { err.line, err.col, err.message })
        end
    end)
end)

describe('sexpr.write', function()
    it('writes flat when it fits', function()
        assert.are.equal(
            '(Id x$1 :type int53)',
            write.write_one(write.list({ write.sym 'Id', write.sym 'x$1', write.sym ':type', write.sym 'int53' }))
        )
    end)

    it('breaks wide lists after their leading atoms, keeping :keyword pairs together', function()
        local x = write.list({
            write.sym 'Unit',
            write.sym 'main',
            write.list({ write.sym 'Assume', write.sym 'A1', write.list({ write.sym 'is_int53', write.sym 'x$1' }) }),
            write.list({
                write.sym 'Check',
                write.sym 'O1',
                write.list({ write.sym 'is_int53', write.list({ write.sym '+', write.sym 'x$1', write.sym '1' }) }),
            }),
            write.sym ':rec',
            write.sym 'false',
        })
        assert.are.equal(
            table.concat({
                '(Unit main',
                '  (Assume A1 (is_int53 x$1))',
                '  (Check O1 (is_int53 (+ x$1 1)))',
                '  :rec false)',
            }, '\n'),
            write.write_one(x, { width = 40 })
        )
    end)

    it('puts the first item after the bracket when there are no leading atoms', function()
        local x = write.vec({
            write.list({ write.sym 'a', write.sym 'bbbbbbbb' }),
            write.list({ write.sym 'c', write.sym 'dddddddd' }),
            write.list({ write.sym 'e', write.sym 'ffffffff' }),
        })
        assert.are.equal('[(a bbbbbbbb)\n (c dddddddd)\n (e ffffffff)]', write.write_one(x, { width = 20 }))
    end)

    it('counts closing brackets against the width', function()
        -- flat, the inner list fits in 14 columns but not with the outer `)`
        local x = write.list({ write.sym 'a', write.list({ write.sym 'bbbbb', write.sym 'cccc' }) })
        assert.are.equal('(a (bbbbb cccc))', write.write_one(x, { width = 16 }))
        assert.are.equal('(a\n  (bbbbb cccc))', write.write_one(x, { width = 15 }))
    end)

    it('escapes strings', function()
        assert.are.equal([["a\"b\\c\nd\te\rf\000g\127]] .. '\255"', write.write_one(write.str 'a"b\\c\nd\te\rf\0g\127\255'))
    end)

    it('rejects symbols that would not read back', function()
        for _, bad in ipairs({ '', 'a b', 'a(', '"', 'a;b', 'a]' }) do
            assert.has_error(function()
                write.write_one(write.sym(bad))
            end)
        end
    end)

    it('write_all ends every value with a newline', function()
        assert.are.equal('a\n(b)\n', write.write_all({ write.sym 'a', write.list({ write.sym 'b' }) }))
    end)
end)

describe('sexpr round trip', function()
    -- a fixed seed keeps the generated trees, and so the test, deterministic
    math.randomseed(1724)

    local SYMBOLS = { 'a', 'Local', 'x$1', '1LL', ':type', '#17', 'nil', '-', '+' }

    --- @return string
    local function random_bytes()
        local bytes = {}
        for i = 1, math.random(0, 6) do
            bytes[i] = string.char(math.random(0, 255))
        end
        return table.concat(bytes)
    end

    --- @param depth integer
    --- @return Sexp
    local function random_tree(depth)
        local r = math.random(1, 4)
        if depth == 0 or r == 1 then
            return write.sym(SYMBOLS[math.random(1, #SYMBOLS)])
        elseif r == 2 then
            return write.str(random_bytes())
        end
        local items = {}
        for i = 1, math.random(0, 5) do
            items[i] = random_tree(depth - 1)
        end
        return r == 3 and write.list(items) or write.vec(items)
    end

    it('read(write(x)) == x for random trees at any width', function()
        for _ = 1, 300 do
            local x = random_tree(4)
            local text = write.write_one(x, { width = math.random(1, 80) })
            assert.are.same(x, read_one(text))
        end
    end)

    it('every byte survives a string round trip', function()
        local bytes = {}
        for b = 0, 255 do
            bytes[#bytes + 1] = string.char(b)
        end
        local s = write.str(table.concat(bytes))
        assert.are.same(s, read_one(write.write_one(s)))
    end)
end)

describe('sexpr layout snapshots', function()
    -- tests/snapshots/sexpr/NAME.sexp is read and written back at width 60 into NAME.pretty.sexp
    local inputs = dir.getallfiles('tests/snapshots/sexpr', '*.sexp')
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        if not input:match '%.pretty%.sexp$' then
            it(input, function()
                local xs, err = read.read_all(assert(utils.readfile(input, true)))
                assert(xs, err and read.format_error(err))
                snapshot.check((input:gsub('%.sexp$', '.pretty.sexp')), write.write_all(xs, { width = 60 }))
            end)
        end
    end
end)
