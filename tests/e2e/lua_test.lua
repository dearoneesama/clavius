local cli = require 'clavius.cli'
local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local markers = require 'support.markers'
local utils = require 'pl.utils'

-- Every Lua program under tests/e2e/ but the *_test.lua and *.meta.lua files. Its markers name exactly
-- the diagnostics it gets or, when it gets none, the obligations that may fail. A program `foo.lua` with
-- a `foo.meta.lua` next to it is verified with that file as its `--meta` file.
describe('lua programs', function()
    local inputs = {}
    for _, path in ipairs(dir.getallfiles('tests/e2e', '*.lua')) do
        if not path:match '_test%.lua$' and not path:match '%.meta%.lua$' then
            inputs[#inputs + 1] = path
        end
    end
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        it(input, function()
            local text = assert(utils.readfile(input, true))
            local meta_path = input:gsub('%.lua$', '.meta.lua')
            local meta_text = utils.readfile(meta_path, true)
            local metas = meta_text and { { name = meta_path, text = meta_text } } or nil
            local c = driver.run_until('validate', text, 1, metas)
            if #c.diags > 0 then
                assert.are.same(markers.read(text), markers.diags(c))
                return
            end
            local failed, err = driver.verify_core(assert(c.prog))
            assert(failed, err)
            assert.are.same(markers.read(text), markers.failures(c, failed))
            -- a program that verifies runs on LuaJIT without an error
            if #failed == 0 then
                assert(loadfile(input))()
            end
        end)
    end

    it('runs from the command line', function()
        local out, err = assert(io.tmpfile()), assert(io.tmpfile())
        local status = cli.main({ 'verify', 'tests/e2e/verify/assert.lua' }, out, err)
        out:seek 'set'
        err:seek 'set'
        local message = 'tests/e2e/verify/assert.lua:9:1: assert: this assertion may fail [O3]\n'
        assert.are.same({ cli.EXIT_FAILED, message, '' }, { status, out:read '*a', err:read '*a' })
        assert.are.equal(cli.EXIT_OK, cli.main({ 'verify', 'tests/e2e/verify/assign.lua' }, out, err))
    end)

    it('prints the trust report from the command line', function()
        local out = assert(io.tmpfile())
        local err = assert(io.tmpfile())
        local status = cli.main({ 'verify', '--trust-report', 'tests/e2e/verify/unsafe.lua' }, out, err)
        out:seek 'set'
        local report = 'Trust report: tests/e2e/verify/unsafe.lua\n\n  @unsafe functions\n    bump  tests/e2e/verify/unsafe.lua:8\n'
        assert.are.same({ cli.EXIT_OK, report }, { status, out:read '*a' })
        -- without the flag, nothing is printed
        local quiet = assert(io.tmpfile())
        assert.are.equal(cli.EXIT_OK, cli.main({ 'verify', 'tests/e2e/verify/unsafe.lua' }, quiet, err))
        quiet:seek 'set'
        assert.are.equal('', quiet:read '*a')
    end)
end)
