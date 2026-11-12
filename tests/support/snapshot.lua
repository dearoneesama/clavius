-- Snapshot files are expected test outputs.

local luassert = require 'luassert'
local utils = require 'pl.utils'

local M = {}

--- Compares `actual` with the snapshot file at `path`, or rewrites the file under UPDATE_SNAPSHOTS=1. Raises an error
--- if the file is missing or differs.
--- @param path string
--- @param actual string
function M.check(path, actual)
    if os.getenv 'UPDATE_SNAPSHOTS' == '1' then
        assert(utils.writefile(path, actual, true))
        return
    end
    local expected = utils.readfile(path, true)
    assert(expected, ('snapshot file %s is missing; run UPDATE_SNAPSHOTS=1 make test to create it'):format(path))
    luassert.are.equal(expected, actual, ('%s does not match (UPDATE_SNAPSHOTS=1 make test rewrites it)'):format(path))
end

return M
