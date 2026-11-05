package.path = './src/?.lua;./src/?/init.lua;./tests/?.lua;' .. package.path

local clavius = require 'clavius'
assert(clavius.greet() == 'Hello, world!')
assert(clavius.greet 'Lua' == 'Hello, Lua!')
