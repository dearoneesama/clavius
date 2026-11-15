local cli = require 'clavius.cli'
local stringx = require 'pl.stringx'
local utils = require 'pl.utils'

--- @class CliRun
--- @field status integer
--- @field out string
--- @field err string

--- Runs the CLI in-process with temporary files for its output streams.
--- @param argv string[]
--- @return CliRun
local function run(argv)
    local out, err = assert(io.tmpfile()), assert(io.tmpfile())
    local status = cli.main(argv, out, err)
    --- @param f file*
    --- @return string
    local function contents(f)
        f:seek 'set'
        local text = f:read '*a'
        f:close()
        return text
    end
    return { status = status, out = contents(out), err = contents(err) }
end

describe('cli', function()
    it('lowers a core file to Boogie', function()
        local r = run { 'lower', 'tests/snapshots/boogie/control.core.sexp' }
        assert.are.same({ cli.EXIT_OK, '' }, { r.status, r.err })
        assert.are.equal(utils.readfile('tests/snapshots/boogie/control.bpl', true), r.out)
    end)

    it('reports a file it cannot read', function()
        local r = run { 'lower', 'tests/no-such-file.core.sexp' }
        assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
        assert.is_truthy(r.err:find('no-such-file.core.sexp', 1, true))
    end)

    --- Runs the CLI with `argv` and a temporary file holding `text` as its last argument. The file's name
    --- ends in `ext`, and is `f<ext>` in the error output.
    --- @param argv string[]
    --- @param ext string
    --- @param text string
    --- @return CliRun
    local function run_with_file(argv, ext, text)
        local base = os.tmpname()
        local file = base .. ext
        assert(utils.writefile(file, text, true))
        local args = { unpack(argv) }
        args[#args + 1] = file
        local r = run(args)
        os.remove(file)
        os.remove(base)
        r.err = stringx.replace(r.err, file, 'f' .. ext)
        return r
    end

    --- Runs `clavius <command> FILE` on a temporary core file holding `text`.
    --- @param command string
    --- @param text string
    --- @return CliRun
    local function run_on(command, text)
        return run_with_file({ command }, '.core.sexp', text)
    end

    it('reports a malformed core file at its position', function()
        for _, command in ipairs { 'lower', 'verify' } do
            local r = run_on(command, '(Unit u\n  [] [(Havoc)])')
            assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
            assert.are.equal('f.core.sexp:2:7: Havoc takes 1 fields, found 0\n', r.err)
        end
    end)

    it('reports every validation error at its node', function()
        for _, command in ipairs { 'lower', 'verify' } do
            local r = run_on(command, '(Unit u []\n  [(Check 1 (Bool true))\n   (Var x)\n   (Block l [])\n   (Block l [(Exit m)])])')
            assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
            assert.are.equal(
                table.concat({
                    'f.core.sexp:2:4: E-internal-check: Check O1 has no obligation of a known kind',
                    'f.core.sexp:3:4: E-internal-node: Var where a statement belongs',
                    'f.core.sexp:5:4: E-internal-label: Block label l is already used in this unit',
                    'f.core.sexp:5:14: E-internal-exit: Exit m has no enclosing Block with that label',
                    '',
                }, '\n'),
                r.err
            )
        end
    end)

    it('dumps a Lua file after a stage', function()
        local text = '---@clavius begin\nlocal x = 1\n---@clavius end\n'
        local cases = {
            { 'parse', '(Block [(ClvRegion [(Local [(Literal number 1)] [(Binder x)])])])\n' },
            { 'types', '(Block [(ClvRegion [(Local [(Literal number 1 :type int53)] [(Binder x$1 :type int53)])])])\n' },
            { 'validate', '(Unit main$1 [(VarDecl x$1 int)] [(Assign x$1 (Int 1))])\n' },
        }
        for _, c in ipairs(cases) do
            local r = run_with_file({ 'dump', '--after', c[1] }, '.lua', text)
            assert.are.same({ cli.EXIT_OK, c[2], '' }, { r.status, r.out, r.err })
        end
    end)

    it('verifies a file with no region without running the backend', function()
        local r = run_with_file({ 'verify' }, '.lua', 'local t = {}\nprint(#t)\n')
        assert.are.same({ cli.EXIT_OK, '', '' }, { r.status, r.out, r.err })
    end)

    it('reports the diagnostics of the stage that fails, in source order', function()
        local text = '---@clavius begin\nlocal x = 1 + true\nlocal y = print\n---@clavius end\n'
        for _, argv in ipairs { { 'verify' }, { 'dump', '--after', 'types' } } do
            local r = run_with_file(argv, '.lua', text)
            assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
            assert.are.equal("f.lua:3:11: E-unsupported-call: `print` isn't supported in this version; leave this code unmarked\n", r.err)
        end
        local r = run_with_file({ 'verify' }, '.lua', '---@clavius begin\nlocal x = 1 + true\n---@clavius end\n')
        assert.are.equal('f.lua:2:15: E-type-mismatch: expected int53, found boolean\n', r.err)
    end)

    it('prints help on stdout and succeeds', function()
        for _, argv in ipairs { { '-h' }, { 'verify', '-h' }, { 'dump', '--help' }, { 'lower', '-h', 'f' } } do
            local r = run(argv)
            assert.are.equal(cli.EXIT_OK, r.status)
            assert.is_truthy(r.out:find('Usage: clavius', 1, true))
            assert.are.equal('', r.err)
        end
        assert.is_truthy(run({ 'dump', '-h' }).out:find('--after', 1, true))
    end)

    it('rejects bad usage', function()
        for _, argv in ipairs {
            {},
            { 'frobnicate' },
            { 'verify' },
            { 'dump', 'f.lua' },
            { 'dump', '--after', 'parse', '--ids', 'f.lua' },
            { 'dump', '--after', 'frob', 'f.lua' },
            { 'lower', '--backend', 'boogie', 'f.core.sexp' },
        } do
            local r = run(argv)
            assert.are.equal(cli.EXIT_USAGE, r.status)
            assert.is_truthy(r.err:find('Error: ', 1, true))
        end
    end)
end)
