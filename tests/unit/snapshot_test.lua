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

-- tests/snapshots/trust/<NAME>.lua gets its trust report in <NAME>.trust.txt, with <NAME>.meta.lua as
-- its `---@meta` file when there is one
describe('trust report', function()
    local inputs = {}
    for _, path in ipairs(dir.getfiles('tests/snapshots/trust', '*.lua')) do
        if not path:match '%.meta%.lua$' then
            inputs[#inputs + 1] = path
        end
    end
    table.sort(inputs)
    for _, input in ipairs(inputs) do
        it(input, function()
            local text = assert(utils.readfile(input, true))
            local meta_path = input:gsub('%.lua$', '.meta.lua')
            local meta_text = utils.readfile(meta_path, true)
            local metas = meta_text and { { name = (meta_path:match '[^/]+$'), text = meta_text } } or nil
            local c = driver.run_until('validate', text, 1, metas, (input:match '[^/]+$'))
            assert.are.same({}, messages.diags(c.diags, c.spans, text))
            local lines = trust.report(assert(c.prog), c.src, assert(c.index), c.files, c.file)
            snapshot.check((input:gsub('%.lua$', '.trust.txt')), table.concat(lines, '\n') .. '\n')
        end)
    end
end)
