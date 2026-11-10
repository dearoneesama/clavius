-- The command line.

local argparse = require 'argparse'

--- argparse ships no type annotations, so its parser objects are untyped here.
--- @alias ArgParser any

--- The parsed arguments, as argparse returns them.
--- @class CliArgs
--- @field command string
--- @field file string
--- @field after string|nil

local M = {}

M.EXIT_OK = 0
M.EXIT_USAGE = 2
M.EXIT_NOT_IMPLEMENTED = 3

--- Builds the parser. A `-h` on any command records that command's help text in `help` instead of
--- printing it and exiting, which is argparse's default.
--- @param help string[] receives the help text
--- @return ArgParser
local function build_parser(help)
    --- @param cmd ArgParser
    --- @return ArgParser
    local function with_help(cmd)
        --- @return nil
        local function record_help()
            help[#help + 1] = cmd:get_help()
        end
        return cmd:add_help({ action = record_help })
    end

    local parser = with_help(argparse('clavius', 'A deductive verifier for a subset of LuaJIT.'))
    parser:command_target 'command'

    local verify = with_help(parser:command('verify', 'Verify a Lua file.'))
    verify:argument('file', 'The Lua file to verify.')

    local dump = with_help(parser:command('dump', 'Print the program as an s-expression after a stage.'))
    dump:argument('file', 'The Lua file to read.')
    dump:option('--after', 'The stage to stop after.'):argname('<stage>'):count(1)

    local lower = with_help(parser:command('lower', 'Print a Boogie file from a core s-expression file.'))
    lower:argument('file', 'The .core.sexp file to read.')

    return parser
end

--- Runs the command line. It takes its output streams and returns an exit status instead of exiting,
--- so the tests can run it in-process.
--- @param argv string[] the arguments, without the program name
--- @param out file* standard output
--- @param err file* standard error
--- @return integer status
function M.main(argv, out, err)
    local help = {}
    local parser = build_parser(help)
    local ok, result = parser:pparse(argv)
    -- a `-h` wins over any parse error that follows it, as with argparse's own help action
    if #help > 0 then
        out:write(help[1], '\n')
        return M.EXIT_OK
    end
    if not ok then
        err:write(parser:get_usage(), '\n\n', ('Error: %s\n'):format(tostring(result)))
        return M.EXIT_USAGE
    end
    --- @type CliArgs
    local args = result
    err:write(('clavius %s: not implemented yet\n'):format(args.command))
    return M.EXIT_NOT_IMPLEMENTED
end

return M
