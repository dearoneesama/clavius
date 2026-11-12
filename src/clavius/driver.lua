-- Connects the stages for the command line and the tests.

local boogie_print = require 'clavius.backend.boogie.print'
local boogie_run = require 'clavius.backend.boogie.run'
local dump = require 'clavius.sexpr.dump'
local validate = require 'clavius.validate'

local M = {}

--- Reads a core program from s-expression text and validates it. Returns the program and the
--- validation diagnostics, which are empty when it is valid, or nil and the read error.
--- @param text string
--- @param file FileId
--- @return CoreProgram|nil prog
--- @return SexpReadError|nil err
--- @return Diag[] diags
function M.load_core(text, file)
    local prog, err = dump.read_core(text, file)
    if not prog then
        return nil, err, {}
    end
    return prog, nil, validate.run(prog.core, prog.units, prog.obligations, prog.assumptions)
end

--- Prints a valid core program as a Boogie file.
--- @param prog CoreProgram
--- @return string
function M.lower_core(prog)
    return boogie_print.program(prog.core, prog.units, nil)
end

--- Verifies a valid core program with Boogie. Returns the ids of the failing obligations in ascending order,
--- or nil and an error when Boogie gives no verdict.
--- @param prog CoreProgram
--- @return integer[]|nil failed
--- @return string|nil err
function M.verify_core(prog)
    return boogie_run.check(prog.core, prog.units, nil)
end

return M
