local M = {}

--- Returns a greeting for `name` (defaults to 'world').
--- @param name string|nil
--- @return string
function M.greet(name)
    return ('Hello, %s!'):format(name or 'world')
end

return M
