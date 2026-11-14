local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local snapshot = require 'support.snapshot'
local utils = require 'pl.utils'

-- tests/snapshots/<STAGE>/<NAME>.lua is dumped after STAGE into <NAME>.<STAGE>.sexp
for _, stage in ipairs({ 'elaborate' }) do
    describe(('dump --after %s'):format(stage), function()
        local inputs = dir.getfiles(('tests/snapshots/%s'):format(stage), '*.lua')
        table.sort(inputs)
        for _, input in ipairs(inputs) do
            it(input, function()
                local text = assert(utils.readfile(input, true))
                -- an elaborated program also goes through validate
                local c = driver.run_until('validate', text, 1)
                assert.are.same({}, c.diags)
                snapshot.check((input:gsub('%.lua$', ('.%s.sexp'):format(stage))), driver.dump_core(c))
            end)
        end
    end)
end
