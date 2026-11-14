std = 'lua51'
max_line_length = 150
max_comment_line_length = false
exclude_files = { 'lua_modules/**', '.luarocks/**', 'tests/snapshots/**', 'tests/e2e/*/**' }

files['tests/**'] = { std = '+busted' }

-- code under these paths stays within the Lua subset that Clavius verifies, which has none of these
local UNVERIFIABLE = {
    'pcall',
    'xpcall',
    'pairs',
    'next',
    'setmetatable',
    'getmetatable',
    'rawget',
    'rawset',
    'rawequal',
    'io',
    'os',
    'debug',
    'coroutine',
    'load',
    'loadstring',
    'loadfile',
    'dofile',
    'print',
}
for _, path in ipairs({
    'src/clavius/ir/**',
    'src/clavius/passes/**',
    'src/clavius/elaborate/**',
    'src/clavius/declare.lua',
    'src/clavius/validate.lua',
}) do
    files[path] = { not_globals = UNVERIFIABLE }
end
