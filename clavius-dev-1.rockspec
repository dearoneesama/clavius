rockspec_format = '3.0'
package = 'clavius'
version = 'dev-1'

source = {
    url = 'git+https://github.com/dearoneesama/clavius.git',
}

description = {
    summary = 'A LuaJIT project.',
    homepage = 'https://github.com/dearoneesama/clavius',
}

dependencies = {
    'lua ~> 5.1', -- LuaJIT reports itself as Lua 5.1
}

test_dependencies = {
    'luacheck == 1.2.0',
}

test = {
    type = 'command',
    command = 'luajit tests/run.lua',
}

build = {
    type = 'builtin',
    modules = {
        clavius = 'src/clavius/init.lua',
    },
    install = {
        bin = {
            clavius = 'bin/clavius',
        },
    },
}
