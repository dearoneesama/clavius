local cli = require 'clavius.cli'
local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local read = require 'clavius.sexpr.read'
local utils = require 'pl.utils'

-- the Boogie release whose output the backend reads
local BOOGIE_VERSION = '3.5.8'

describe('boogie', function()
    it(('is version %s'):format(BOOGIE_VERSION), function()
        local pipe = assert(io.popen(("'%s' /version 2>&1"):format(os.getenv 'BOOGIE' or 'boogie')))
        local text = pipe:read '*a'
        pipe:close()
        assert.is_truthy(text:find(('version %s'):format(BOOGIE_VERSION), 1, true), text)
    end)

    -- each fixture's first line lists the obligations expected to fail: `; fails: O2 O3`
    local inputs = dir.getallfiles('tests/snapshots/boogie', '*.core.sexp')
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        it(('reports the failing obligations of %s'):format(input), function()
            local text = assert(utils.readfile(input, true))
            local header = assert(text:match '^; fails:([^\n]*)', 'fixture has no `; fails:` line')
            local expected = {}
            for id in header:gmatch 'O(%d+)' do
                expected[#expected + 1] = assert(tonumber(id))
            end
            local prog, err, diags = driver.load_core(text, 1)
            assert(prog, err and read.format_error(err))
            assert.are.same({}, diags)
            local failed, run_err = driver.verify_core(prog)
            assert(failed, run_err)
            assert.are.same(expected, failed)
        end)
    end

    it('runs from the command line', function()
        local out, err = assert(io.tmpfile()), assert(io.tmpfile())
        local status = cli.main({ 'verify', 'tests/snapshots/boogie/several.core.sexp' }, out, err)
        out:seek 'set'
        err:seek 'set'
        assert.are.same({ cli.EXIT_FAILED, 'O1\nO2\nO4\nO6\nO8\n', '' }, { status, out:read '*a', err:read '*a' })
        assert.are.equal(cli.EXIT_OK, cli.main({ 'verify', 'tests/snapshots/boogie/terms.core.sexp' }, out, err))
    end)
end)
