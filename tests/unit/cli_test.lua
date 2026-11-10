local cli = require 'clavius.cli'

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
    it('reports each subcommand as not implemented yet', function()
        for _, argv in ipairs({
            { 'verify', 'f.lua' },
            { 'dump', '--after', 'parse', 'f.lua' },
            { 'lower', 'f.core.sexp' },
        }) do
            local r = run(argv)
            assert.are.equal(cli.EXIT_NOT_IMPLEMENTED, r.status)
            assert.are.equal(('clavius %s: not implemented yet\n'):format(argv[1]), r.err)
            assert.are.equal('', r.out)
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
