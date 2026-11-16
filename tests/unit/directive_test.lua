local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local directive = require 'clavius.syntax.directive'
local dump = require 'clavius.sexpr.dump'
local luacheck = require 'clavius.syntax.luacheck'
local write = require 'clavius.sexpr.write'

--- @param src SrcArena
--- @param id NodeId
--- @return string
local function flat(src, id)
    return write.flat(dump.write_src(src, id, {}))
end

--- Parses every directive in `text`. Each result is its nodes written out, or the error's code, argument
--- and the text at its span.
--- @param text string
--- @return string[][]
local function directives(text)
    local src = arena.new_src()
    local chunk = assert(luacheck.convert(src, text, 1))
    --- @type CodeParser
    local function code_parser(c, start)
        return luacheck.expressions(src, 1, c, start)
    end
    local out = {}
    for i, d in ipairs(comments.directives(chunk.comments)) do
        local nodes, diags = directive.parse(src, d, code_parser)
        if #diags > 0 then
            local s = assert(diags[1].span)
            out[i] = { diags[1].code, diags[1].args[1], text:sub(s.start, s.finish) }
        else
            out[i] = {}
            for j, id in ipairs(nodes) do
                out[i][j] = flat(src, id)
            end
        end
    end
    return out
end

--- @param cases (string|string[])[][] each a directive and what it parses to
local function check(cases)
    local lines = {}
    for i, c in ipairs(cases) do
        lines[i] = c[1]
    end
    local found = directives(table.concat(lines, '\n'))
    for i, c in ipairs(cases) do
        assert.are.same(c[2], found[i], c[1])
    end
end

describe('syntax.directive', function()
    it('parses Clavius tags', function()
        check {
            { '---@clavius', { '(ClvMarker)' } },
            { '--- @clavius begin', {} },
            { '---@clavius end', {} },
            { '---@unsafe', { '(ClvUnsafe)' } },
            { '---@entry', { '(ClvEntry)' } },
            { '---@extern', { '(ClvExtern)' } },
            { '---@no_callback', { '(ClvNoCallback)' } },
            { '---@may_raise', { '(ClvMayRaise)' } },
            {
                '---@pre n > 0 and m > 0 -- why',
                { '(ClvPre (BinOp and (BinOp gt (Id n) (Literal number 0)) (BinOp gt (Id m) (Literal number 0))))' },
            },
            { '---@post result == n', { '(ClvPost (BinOp eq (Id result) (Id n)))' } },
            { '---@invariant i <= n', { '(ClvInvariant (BinOp le (Id i) (Id n)))' } },
            { '---@module_invariant ok', { '(ClvModuleInvariant (Id ok))' } },
            { '---@decrease n, m - 1', { '(ClvDecrease [(Id n) (BinOp sub (Id m) (Literal number 1))])' } },
            { '---@closure_invariant(n >= 0)', { '(ClvClosureInvariant (Paren (BinOp ge (Id n) (Literal number 0))))' } },
            { '---@ghost local seen = 0', {} },
            { '---@proof lemma(xs, i)', {} },
            { '---@assert seen > 0', {} },
            { '---@mut p', { '(ClvMut p)' } },
            { '---@move item', { '(ClvMove item)' } },
            { '---@frozen', { '(ClvFrozen nil)' } },
            { '---@frozen levels', { '(ClvFrozen levels)' } },
            { '---@len dst n', { '(ClvLen dst n)' } },
            { '---@disjoint a, b', { '(ClvDisjoint a b)' } },
            { '---@rlimit 20000000', { '(ClvRlimit 20000000)' } },
            { '---@proof_by(nonlinear_arith)', { '(ClvProofBy nonlinear_arith)' } },
            { '---@proof_by (bit_vector)', { '(ClvProofBy bit_vector)' } },
            { '---@reveal_with_fuel(sum, 3)', { '(ClvRevealWithFuel sum 3)' } },
        }
    end)

    it('parses LuaLS tags with their descriptions', function()
        check {
            { '---@param n int53 the count', { '(ClvParam n false (ClvTypeName int53))' } },
            { '--- @param xs? Seq<T>', { '(ClvParam xs true (ClvTypeApply (ClvTypeName Seq) [(ClvTypeName T)]))' } },
            { '---@param ... int53', { '(ClvParam ... false (ClvTypeName int53))' } },
            { '---@return int53 sum', { '(ClvReturn sum (ClvTypeName int53))' } },
            { '---@return int53 ...', { '(ClvReturn ... (ClvTypeName int53))' } },
            {
                '---@return boolean, string err # why it failed',
                { '(ClvReturn nil (ClvTypeName boolean))', '(ClvReturn err (ClvTypeName string))' },
            },
            { '---@type int53, boolean', { '(ClvType [(ClvTypeName int53) (ClvTypeName boolean)])' } },
            { '---@vararg int53', { '(ClvVararg (ClvTypeName int53))' } },
            { '---@overload fun(a: int53)', { '(ClvOverload (ClvTypeFun false [] [(ClvTypeParam a false (ClvTypeName int53))] []))' } },
            { '---@overload async fun()', { '(ClvOverload (ClvTypeFun true [] [] []))' } },
            { '---@as int53', { '(ClvAs (ClvTypeName int53))' } },
            {
                '---@class (exact) Pool<T>: Base, { n: int53 }',
                {
                    '(ClvClass true false Pool [(ClvTypeGeneric T)] '
                        .. '[(ClvTypeName Base) (ClvTypeTable [(ClvTypeField nil n false (ClvTypeName int53))])])',
                },
            },
            { '---@class (partial) Point', { '(ClvClass false true Point [] [])' } },
            { '---@field private items T[] the items', { '(ClvField nil items false (ClvTypeArray (ClvTypeName T)))' } },
            { '---@field next? Node', { '(ClvField nil next true (ClvTypeName Node))' } },
            { '---@field [string] int53', { '(ClvField (ClvTypeName string) nil false (ClvTypeName int53))' } },
            { '---@field public integer', { '(ClvField nil public false (ClvTypeName integer))' } },
            {
                "---@alias Dir 'n' | 's'",
                { '(ClvAlias Dir [] (ClvTypeUnion [(ClvTypeLiteral string "n") (ClvTypeLiteral string "s")]))' },
            },
            {
                '---@alias Pair<K, V> [K, V]',
                { '(ClvAlias Pair [(ClvTypeGeneric K) (ClvTypeGeneric V)] (ClvTypeTuple [(ClvTypeName K) (ClvTypeName V)]))' },
            },
            { '---@enum (key) Color', { '(ClvEnum true false Color)' } },
            { '---@enum Dir', { '(ClvEnum false false Dir)' } },
            { '---@generic T, K : value', { '(ClvGeneric T nil)', '(ClvGeneric K (ClvTypeName value))' } },
            { '---@cast x +int53, -?', { '(ClvCast x add (ClvTypeName int53))', '(ClvCast x remove nil)' } },
            { '---@cast x Point', { '(ClvCast x set (ClvTypeName Point))' } },
            { '---@operator add(Vec): Vec', { '(ClvOperator add (ClvTypeName Vec) (ClvTypeName Vec))' } },
            { '---@operator unm: Vec', { '(ClvOperator unm nil (ClvTypeName Vec))' } },
            { '---@operator call(): boolean', { '(ClvOperator call nil (ClvTypeName boolean))' } },
            { '---@meta', { '(ClvMeta nil)' } },
            { '---@meta game', { '(ClvMeta game)' } },
            { "---@module 'socket'", { '(ClvModule socket)' } },
            -- tags that Clavius doesn't read, LuaLS's editor-only ones among them
            { '---@diagnostic disable-next-line: unused-local', {} },
            { '---@deprecated use g instead', {} },
            { '---@usage f(1)', {} },
            { '---@prec x > 0', {} },
        }
    end)

    it('gives the code in a directive its place in the file', function()
        local text = 'local a = 1\n---@pre n + 1 > 0'
        local src = arena.new_src()
        local chunk = assert(luacheck.convert(src, text, 1))
        local d = comments.directives(chunk.comments)[1]
        local first = #src.nodes + 1
        directive.parse(src, d, function(c, start)
            return luacheck.expressions(src, 1, c, start)
        end)
        local spans = {}
        for id = first, #src.nodes do
            spans[#spans + 1] = text:sub(src.spans[id].start, src.spans[id].finish)
        end
        assert.are.same({ 'n', '1', 'n + 1', '0', 'n + 1 > 0', '---@pre n + 1 > 0' }, spans)
    end)

    it('continues a type onto the lines below', function()
        local found = directives(table.concat({
            '---@alias Shape',
            "---| 'circle' # a circle",
            '--- a rectangle:',
            "---| 'rect'",
            '---@param mode string',
            "---|>'r'",
            "---|+ 'w'",
            '---@type {',
            '---   x: int53,',
            '---   y: int53,',
            '---}',
            '---@param f fun(a: int53)',
            '--- and a description',
        }, '\n'))
        assert.are.same({
            { '(ClvAlias Shape [] (ClvTypeUnion [(ClvTypeLiteral string "circle") (ClvTypeLiteral string "rect")]))' },
            { '(ClvParam mode false (ClvTypeUnion [(ClvTypeName string) (ClvTypeLiteral string "r") (ClvTypeLiteral string "w")]))' },
            { '(ClvType [(ClvTypeTable [(ClvTypeField nil x false (ClvTypeName int53)) (ClvTypeField nil y false (ClvTypeName int53))])])' },
            { '(ClvParam f false (ClvTypeFun false [] [(ClvTypeParam a false (ClvTypeName int53))] []))' },
        }, found)
    end)

    it("reports what doesn't fit a tag", function()
        check {
            { '---@pre', { 'E-syntax', 'expected-code', '' } },
            { '---@pre a, b', { 'E-syntax', 'one-expression', 'a, b' } },
            { '---@pre x = 1', { 'E-syntax', "expected <eof> near '='", '=' } },
            { '---@pre x --[[@as int53]] > 0', { 'E-unsupported-directive', 'as', '--[[@as int53]]' } },
            { '---@mut a, b', { 'E-syntax', 'unexpected-text', ',' } },
            { '---@mut a.b', { 'E-syntax', 'expected-name', 'a.b' } },
            { '---@unsafe because', { 'E-syntax', 'unexpected-text', 'because' } },
            { '---@frozen p = 1', { 'E-syntax', 'unexpected-text', '' } },
            { '---@clavius haha', { 'E-syntax', 'clavius-args', 'haha' } },
            { '---@disjoint a b', { 'E-syntax', 'expected-,', 'b' } },
            { '---@rlimit 0', { 'E-syntax', 'expected-positive-integer', '0' } },
            { '---@proof_by(magic)', { 'E-syntax', 'unknown-theory', 'magic' } },
            { '---@param x', { 'E-syntax', 'expected-type', '' } },
            { '---@param x Seq<int53', { 'E-syntax', 'expected->', '' } },
            { '---@overload integer', { 'E-syntax', 'expected-fun', 'integer' } },
            { '---@module socket', { 'E-syntax', 'expected-string', 'socket' } },
            { '---@class (haha) A', { 'E-syntax', 'unknown-attribute', 'haha' } },
            { '---@enum (exact) E', { 'E-syntax', 'unknown-attribute', 'exact' } },
            { '---@alias (partial) A int53', { 'E-syntax', 'unknown-attribute', 'partial' } },
            { '---@clavius begin now', { 'E-syntax', 'clavius-args', 'now' } },
            { '---@decrease', { 'E-syntax', 'expected-code', '' } },
            { '---@post a, b', { 'E-syntax', 'one-expression', 'a, b' } },
            { '---@decrease n =', { 'E-syntax', "expected <eof> near '='", '=' } },
            { '---@mut', { 'E-syntax', 'expected-name', '' } },
            { '---@frozen a.b', { 'E-syntax', 'expected-name', 'a.b' } },
            { '---@len dst', { 'E-syntax', 'expected-name', '' } },
            { '---@rlimit 1.5', { 'E-syntax', 'expected-positive-integer', '1.5' } },
            { '---@proof_by nonlinear_arith', { 'E-syntax', 'expected-(', 'nonlinear_arith' } },
            { '---@reveal_with_fuel(sum)', { 'E-syntax', 'expected-,', ')' } },
            { '---@reveal_with_fuel(sum, 0)', { 'E-syntax', 'expected-positive-integer', '0' } },
            { '---@operator add(Vec) Vec', { 'E-syntax', 'expected-:', 'Vec' } },
            { '---@generic', { 'E-syntax', 'expected-name', '' } },
            { '---@field x', { 'E-syntax', 'expected-type', '' } },
        }
    end)
end)
