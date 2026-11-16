local arena = require 'clavius.ir.arena'
local dump = require 'clavius.sexpr.dump'
local typeexpr = require 'clavius.syntax.typeexpr'
local write = require 'clavius.sexpr.write'

--- @param src SrcArena
--- @param id NodeId
--- @return string
local function flat(src, id)
    return write.flat(dump.write_src(src, id, {}))
end

--- Parses `text` as a type. Returns the nodes, or the error's argument and the text at its span.
--- @param text string
--- @return string
local function ty(text)
    local src = arena.new_src()
    local ok, res = pcall(typeexpr.parse, src, typeexpr.lexer(1, { { text = text, start = 1 } }))
    if not ok then
        local d = (res --[[@as DocError]]).diag
        local s = assert(d.span)
        return ('%s at %q'):format(d.args[1], text:sub(s.start, s.finish))
    end
    return flat(src, res --[[@as NodeId]])
end

describe('syntax.typeexpr', function()
    it('parses names, applications, arrays and literals', function()
        assert.are.equal('(ClvTypeName int53)', ty 'int53')
        assert.are.equal('(ClvTypeName a.b)', ty 'a.b')
        assert.are.equal('(ClvTypeApply (ClvTypeName Seq) [(ClvTypeName int53)])', ty 'Seq<int53>')
        assert.are.equal(
            '(ClvTypeArray (ClvTypeArray (ClvTypeApply (ClvTypeName table) [(ClvTypeName string) (ClvTypeName boolean)])))',
            ty 'table<string, boolean>[][]'
        )
        assert.are.equal('(ClvTypeUnion [(ClvTypeLiteral integer 1) (ClvTypeLiteral integer -1) (ClvTypeLiteral boolean true)])', ty '1 | -1 | true')
        assert.are.equal('(ClvTypeName ...)', ty '...')
    end)

    it('reads string literal types', function()
        assert.are.equal('(ClvTypeUnion [(ClvTypeLiteral string "circle") (ClvTypeLiteral string "a b")])', ty [['circle'|"a b"]])
        assert.are.equal('(ClvTypeLiteral string "a\\nb\\"")', ty [['a\nb\"']])
        assert.are.equal('(ClvTypeLiteral string "x]")', ty '[=[x]]=]')
        assert.are.equal('(ClvTypeLiteral string "A")', ty [['\65']])
        -- LuaLS keeps an escape it doesn't know
        assert.are.equal('(ClvTypeLiteral string "\\\\q")', ty [['\q']])
        -- an old LuaLS spelling
        assert.are.equal('(ClvTypeLiteral string "r")', ty [['"r"']])
    end)

    it('applies `?` to a whole union, and parentheses group', function()
        assert.are.equal('(ClvTypeOptional (ClvTypeUnion [(ClvTypeName A) (ClvTypeName B)]))', ty 'A|B?')
        assert.are.equal('(ClvTypeUnion [(ClvTypeOptional (ClvTypeName A)) (ClvTypeName B)])', ty '((A?)|B)')
        assert.are.equal('(ClvTypeUnion [(ClvTypeName A) (ClvTypeOptional (ClvTypeName B))])', ty '(A|(B?))')
        assert.are.equal('(ClvTypeArray (ClvTypeUnion [(ClvTypeName A) (ClvTypeName B)]))', ty '(A|B)[]')
    end)

    it('parses function types', function()
        assert.are.equal('(ClvTypeFun false [] [] [])', ty 'fun()')
        assert.are.equal(
            '(ClvTypeFun false [] [(ClvTypeParam a false (ClvTypeName integer)) (ClvTypeParam b true nil) '
                .. '(ClvTypeParam ... false (ClvTypeName boolean))] [(ClvTypeReturn nil (ClvTypeName boolean))])',
            ty 'fun(a: integer, b?, ...: boolean): boolean'
        )
        assert.are.equal(
            '(ClvTypeFun true [(ClvTypeGeneric T)] [(ClvTypeParam x false (ClvTypeName T))] '
                .. '[(ClvTypeReturn ok (ClvTypeName boolean)) (ClvTypeReturn err (ClvTypeOptional (ClvTypeName string)))])',
            ty 'async fun<T>(x: T): (ok: boolean, err: string?)'
        )
    end)

    it('parses table and tuple types', function()
        -- not supported in Clavius over generic parse error
        assert.are.equal(
            '(ClvTypeTable [(ClvTypeField nil x false (ClvTypeName integer)) '
                .. '(ClvTypeField (ClvTypeName string) nil false (ClvTypeName boolean)) (ClvTypeField nil y true (ClvTypeName T))])',
            ty '{ x: integer, [string]: boolean; y?: T, }'
        )
        assert.are.equal('(ClvTypeTuple [(ClvTypeName integer) (ClvTypeName string)])', ty '[integer, string]')
    end)

    it('parses backtick types', function()
        -- not supported in Clavius over generic parse error
        assert.are.equal('(ClvTypeCode T nil)', ty '`T`')
        assert.are.equal('(ClvTypeCode T Foo.%s)', ty 'Foo.`T`')
    end)

    it('stops at text that starts no token', function()
        assert.are.equal('(ClvTypeName integer)', ty 'integer -- the count')
    end)

    it('gives each node the span of its text', function()
        local text = 'fun(a: Seq<int53>): boolean?'
        local src = arena.new_src()
        typeexpr.parse(src, typeexpr.lexer(1, { { text = text, start = 1 } }))
        local spans = {}
        for i, s in ipairs(src.spans) do
            spans[i] = text:sub(s.start, s.finish)
        end
        assert.are.same({ 'Seq', 'int53', 'Seq<int53>', 'a: Seq<int53>', 'boolean', 'boolean?', 'boolean?', text }, spans)
    end)

    it('reports what it expected where the type stops', function()
        assert.are.equal('expected-type at ""', ty '')
        assert.are.equal('expected-type at "|"', ty '|')
        assert.are.equal('expected-> at ""', ty 'Seq<int53')
        assert.are.equal('expected-type at ")"', ty 'fun(a: )')
        assert.are.equal('expected-: at "integer"', ty '{ x integer }')
        assert.are.equal('expected-type at ""', ty "'open")
        assert.are.equal('expected-type at ""', ty 'A |')
        assert.are.equal('expected-name at "1"', ty 'fun<1>()')
        assert.are.equal('expected-name at "1"', ty 'fun(1)')
        assert.are.equal('expected-name at "1"', ty '{ 1: integer }')
        assert.are.equal('expected-) at "}"', ty '{ (x: integer }')
    end)
end)
