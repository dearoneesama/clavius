local dir = require 'pl.dir'
local driver = require 'clavius.driver'
local messages = require 'clavius.report.messages'
local snapshot = require 'support.snapshot'
local trust = require 'clavius.report.trust'
local utils = require 'pl.utils'

-- tests/snapshots/<STAGE>/<NAME>.lua is dumped after STAGE into <NAME>.<STAGE>.sexp
for _, stage in ipairs { 'parse', 'resolve', 'types', 'effects', 'elaborate' } do
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

-- tests/snapshots/trust/<NAME>.lua gets its trust report in <NAME>.trust.txt
describe('trust report', function()
    local inputs = dir.getfiles('tests/snapshots/trust', '*.lua')
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        it(input, function()
            local text = assert(utils.readfile(input, true))
            local c = driver.run_until('validate', text, 1)
            assert.are.same({}, messages.diags(c.diags, c.spans, text))
            local lines = trust.report(assert(c.prog), c.src, assert(c.index), text, (input:match '[^/]+$'))
            snapshot.check((input:gsub('%.lua$', '.trust.txt')), table.concat(lines, '\n') .. '\n')
        end)
    end
end)
