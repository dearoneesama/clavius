-- The command line.

local argparse = require 'argparse'
local driver = require 'clavius.driver'
local messages = require 'clavius.report.messages'
local read = require 'clavius.sexpr.read'
local trust = require 'clavius.report.trust'

--- argparse ships no type annotations, so its parser objects are untyped here.
--- @alias ArgParser any

--- The parsed arguments, as argparse returns them.
--- @class CliArgs
--- @field command string
--- @field file string
--- @field after string|nil
--- @field trust_report boolean|nil `verify --trust-report`

local M = {}

M.EXIT_OK = 0
M.EXIT_FAILED = 1 -- some obligation may fail
M.EXIT_USAGE = 2
M.EXIT_ERROR = 4 -- no verdict: the input is unreadable or invalid, or the backend gave none

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
        return cmd:add_help { action = record_help }
    end

    local parser = with_help(argparse('clavius', 'A deductive verifier for a subset of LuaJIT.'))
    parser:command_target 'command'

    local verify = with_help(parser:command('verify', 'Verify a Lua file.'))
    verify:argument('file', 'The .lua file or .core.sexp file to verify.')
    verify:flag('--trust-report', 'Also print what the run assumed rather than proved.')

    local dump = with_help(parser:command('dump', 'Print the program as an s-expression after a stage.'))
    dump:argument('file', 'The .lua file to read.')
    dump:option('--after', 'The stage to stop after.'):argname('<stage>'):choices(driver.STAGES):count(1)

    local lower = with_help(parser:command('lower', 'Print a Boogie file from a core s-expression file.'))
    lower:argument('file', 'The .core.sexp file to read.')

    return parser
end

--- Writes each message on its own line after the file name.
--- @param stream file*
--- @param file string
--- @param lines string[]
local function write_lines(stream, file, lines)
    for _, line in ipairs(lines) do
        stream:write(('%s:%s\n'):format(file, line))
    end
end

--- Runs `lower` or `verify` on a core file.
--- @param args CliArgs
--- @param text string the file's contents
--- @param out file*
--- @param err file*
--- @return integer status
local function run_core(args, text, out, err)
    local prog, read_err, diags = driver.load_core(text, 1)
    if not prog then
        err:write(('%s:%s\n'):format(args.file, read.format_error(assert(read_err))))
        return M.EXIT_ERROR
    end
    if #diags > 0 then
        write_lines(err, args.file, messages.diags(diags, prog.core.spans, text))
        return M.EXIT_ERROR
    end
    if args.command == 'lower' then
        out:write(driver.lower_core(prog))
        return M.EXIT_OK
    end
    local failed, run_err = driver.verify_core(prog)
    if not failed then
        err:write(('clavius: %s\n'):format(run_err))
        return M.EXIT_ERROR
    end
    for _, id in ipairs(failed) do
        out:write(('O%d\n'):format(id))
    end
    return #failed > 0 and M.EXIT_FAILED or M.EXIT_OK
end

--- Runs `dump` or `verify` on a Lua file.
--- @param args CliArgs
--- @param text string the file's contents
--- @param out file*
--- @param err file*
--- @return integer status
local function run_lua(args, text, out, err)
    local c = driver.run_until(args.after or 'validate', text, 1)
    if #c.diags > 0 then
        write_lines(err, args.file, messages.diags(c.diags, c.spans, text))
        return M.EXIT_ERROR
    end
    if args.command == 'dump' then
        out:write(driver.dump(c))
        return M.EXIT_OK
    end
    local prog = assert(c.prog)
    local failed, run_err = driver.verify_core(prog)
    if not failed then
        err:write(('clavius: %s\n'):format(run_err))
        return M.EXIT_ERROR
    end
    local failures = messages.failures(failed, prog.obligations, c.src, text)
    write_lines(out, args.file, failures)
    local report = {}
    if args.trust_report then
        report = trust.report(prog, c.src, assert(c.index), text, args.file)
    end
    if #report > 0 and #failures > 0 then
        out:write '\n'
    end
    for _, line in ipairs(report) do
        out:write(line, '\n')
    end
    return #failed > 0 and M.EXIT_FAILED or M.EXIT_OK
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

    local f, open_err = io.open(args.file, 'rb')
    if not f then
        err:write(('clavius: %s\n'):format(open_err))
        return M.EXIT_ERROR
    end
    local text = f:read '*a'
    f:close()
    if args.command == 'lower' or (args.command == 'verify' and args.file:match '%.core%.sexp$') then
        return run_core(args, text, out, err)
    end
    return run_lua(args, text, out, err)
end

return M
