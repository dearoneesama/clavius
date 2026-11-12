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
    it('reports verifying Lua and dumping as not implemented', function()
        for _, argv in ipairs({
            { 'verify', 'f.lua' },
            { 'dump', '--after', 'parse', 'f.lua' },
        }) do
            local r = run(argv)
            assert.are.equal(cli.EXIT_NOT_IMPLEMENTED, r.status)
            assert.are.equal(('clavius %s: not implemented yet\n'):format(argv[1]), r.err)
            assert.are.equal('', r.out)
        end
    end)

    it('lowers a core file to Boogie', function()
        local r = run({ 'lower', 'tests/snapshots/boogie/control.core.sexp' })
        assert.are.same({ cli.EXIT_OK, '' }, { r.status, r.err })
        assert.are.equal(utils.readfile('tests/snapshots/boogie/control.bpl', true), r.out)
    end)

    it('reports a file it cannot read', function()
        local r = run({ 'lower', 'tests/no-such-file.core.sexp' })
        assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
        assert.is_truthy(r.err:find('no-such-file.core.sexp', 1, true))
    end)

    --- Runs `clavius <command> FILE` on a temporary core file holding `text`.
    --- @param command string
    --- @param text string
    --- @return CliRun
    local function run_on(command, text)
        local base = os.tmpname()
        local file = base .. '.core.sexp'
        assert(utils.writefile(file, text, true))
        local r = run({ command, file })
        os.remove(file)
        os.remove(base)
        r.err = stringx.replace(r.err, file, 'f.core.sexp')
        return r
    end

    it('reports a malformed core file at its position', function()
        for _, command in ipairs({ 'lower', 'verify' }) do
            local r = run_on(command, '(Unit u\n  [] [(Havoc)])')
            assert.are.same({ cli.EXIT_ERROR, '' }, { r.status, r.out })
            assert.are.equal('f.core.sexp:2:7: Havoc takes 1 fields, found 0\n', r.err)
        end
    end)

    it('reports every validation error at its node', function()
        for _, command in ipairs({ 'lower', 'verify' }) do
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

    it('prints help on stdout and succeeds', function()
        for _, argv in ipairs({ { '-h' }, { 'verify', '-h' }, { 'dump', '--help' }, { 'lower', '-h', 'f' } }) do
            local r = run(argv)
            assert.are.equal(cli.EXIT_OK, r.status)
            assert.is_truthy(r.out:find('Usage: clavius', 1, true))
            assert.are.equal('', r.err)
        end
        assert.is_truthy(run({ 'dump', '-h' }).out:find('--after', 1, true))
    end)

    it('rejects bad usage', function()
        for _, argv in ipairs({
            {},
            { 'frobnicate' },
            { 'verify' },
            { 'dump', 'f.lua' },
            { 'dump', '--after', 'parse', '--ids', 'f.lua' },
            { 'lower', '--backend', 'boogie', 'f.core.sexp' },
        }) do
            local r = run(argv)
            assert.are.equal(cli.EXIT_USAGE, r.status)
            assert.is_truthy(r.err:find('Error: ', 1, true))
        end
    end)
end)
