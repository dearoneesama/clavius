rockspec_format = '3.0'
package = 'clavius'
version = 'dev-1'

source = {
    url = 'git+https://github.com/dearoneesama/clavius.git',
}

description = {
    summary = 'A deductive verifier for a subset of LuaJIT.',
    homepage = 'https://github.com/dearoneesama/clavius',
}

dependencies = {
    'lua ~> 5.1', -- LuaJIT reports itself as Lua 5.1
    'argparse == 0.7.2',
    'luacheck == 1.2.0',
}

test_dependencies = {
    'busted == 2.3.0',
    'penlight == 1.15.0',
    'luacov == 0.17.0',
}

test = {
    type = 'busted',
}

-- No module list: LuaRocks installs every module under src/ and every script under bin/.
build = {
    type = 'builtin',
}
