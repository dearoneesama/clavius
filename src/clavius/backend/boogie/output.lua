-- Reads Boogie's output: the labels of the asserts that fail and the procedures that run out of
-- resources. For example:
--
--   O2
--   Execution trace:
--       f.bpl(11,3): anon0
--   f.bpl(14,30): Verification out of resource (loop)
--
--   Boogie program verifier finished with 1 verified, 1 error, 1 out of resource

--- @class BoogieOutput
--- @field failed integer[] obligation ids of the failing asserts in output order
--- @field out_of_resource string[] procedures whose resource limit ran out

local M = {}

-- outcomes in the summary line that still give every failing assert or name the procedure
local KNOWN_OUTCOMES = { verified = true, error = true, errors = true, ['out of resource'] = true }

--- Parses Boogie's output. Returns nil and a reason when the output has no verdict: Boogie didn't
--- run, rejected the program, or reported an outcome such as a time-out.
--- @param text string
--- @return BoogieOutput|nil result
--- @return string|nil err
function M.parse(text)
    --- @type BoogieOutput
    local result = { failed = {}, out_of_resource = {} }
    local finished = false
    for raw in text:gmatch '[^\n]+' do
        local line = (raw:gsub('%s+$', ''))
        -- a label is printed bare or after a position such as `f.bpl(9,3): Error: `
        local before, label = line:match '^(.-)O(%d+)$'
        if label and before ~= '' and not before:match ':%s$' then
            label = nil
        end
        local proc = line:match 'out of resource %((.-)%)'
        local summary = line:match 'verifier finished with (.*)$'
        if label then
            result.failed[#result.failed + 1] = assert(tonumber(label))
        elseif proc then
            result.out_of_resource[#result.out_of_resource + 1] = proc
        elseif summary then
            for count, what in summary:gmatch '(%d+) ([^,]+)' do
                if count ~= '0' and not KNOWN_OUTCOMES[what] then
                    return nil, ('Boogie reported %s %s'):format(count, what)
                end
            end
            finished = true
        elseif line:match 'errors? detected in' or line:match 'Fatal Error' then
            return nil, 'Boogie could not check the program'
        end
    end
    if not finished then
        return nil, 'Boogie gave no verdict'
    end
    return result, nil
end

return M
