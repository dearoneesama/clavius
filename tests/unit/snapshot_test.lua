local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local messages = require 'clavius.report.messages'
local snapshot = require 'support.snapshot'
local utils = require 'pl.utils'

-- tests/snapshots/<STAGE>/<NAME>.lua is dumped after STAGE into <NAME>.<STAGE>.sexp
for _, stage in ipairs({ 'parse', 'resolve', 'types', 'elaborate' }) do
    describe(('dump --after %s'):format(stage), function()
        local inputs = dir.getfiles(('tests/snapshots/%s'):format(stage), '*.lua')
        table.sort(inputs)
        for _, input in ipairs(inputs) do
            it(input, function()
                local text = assert(utils.readfile(input, true))
                -- an elaborated program also goes through validate
                local c = driver.run_until(stage == 'elaborate' and 'validate' or stage, text, 1)
                assert.are.same({}, messages.diags(c.diags, c.spans, text))
                snapshot.check((input:gsub('%.lua$', ('.%s.sexp'):format(stage))), driver.dump(c))
            end)
        end
    end)
end
