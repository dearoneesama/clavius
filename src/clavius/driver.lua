-- Connects the stages for the command line and the tests. A Lua file goes through the stages in
-- order, and the run stops after the first stage that reports a diagnostic.

local boogie_print = require 'clavius.backend.boogie.print'
local boogie_run = require 'clavius.backend.boogie.run'
local dump = require 'clavius.sexpr.dump'
local index = require 'clavius.ir.index'
local parse = require 'clavius.syntax.parse'
local resolve = require 'clavius.passes.resolve'
local types = require 'clavius.passes.types'
local validate = require 'clavius.validate'

--- One Lua file on its way through the stages. Each stage fills in its fields.
--- @class CompilerContext
--- @field file FileId
--- @field text string
--- @field src SrcArena
--- @field root NodeId
--- @field index NodeIndex|nil
--- @field res Resolution|nil
--- @field info TypeInfo|nil
--- @field stage string the last stage that ran
--- @field diags Diag[] the diagnostics of that stage
--- @field spans Span[] the spans of the arena that the diagnostics' nodes are in

--- @class Stage
--- @field name string
--- @field run fun(c: CompilerContext): Diag[]

local M = {}

--- @param c CompilerContext
--- @return Diag[]
local function run_parse(c)
    local p, diags = parse.run(c.text, c.file)
    c.src, c.root = p.src, p.root
    if #diags == 0 then
        c.index = index.build(p.src)
    end
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_resolve(c)
    local res, diags = resolve.run(c.src, c.root)
    c.res = res
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_types(c)
    local info, diags = types.run(c.src, c.root, assert(c.res))
    c.info = info
    return diags
end

--- Each stage needs the results of every stage before it.
--- @type Stage[]
local STAGES = {
    { name = 'parse', run = run_parse },
    { name = 'resolve', run = run_resolve },
    { name = 'types', run = run_types },
}

--- The stage names in order.
--- @type string[]
M.STAGES = {}
for i, s in ipairs(STAGES) do
    M.STAGES[i] = s.name
end

--- Runs the stages on a Lua file up to and including `stage`, or up to the first one that reports a
--- diagnostic.
--- @param stage string one of `STAGES`
--- @param text string
--- @param file FileId
--- @return CompilerContext
function M.run_until(stage, text, file)
    --- @type CompilerContext
    local c = { file = file, text = text, src = { nodes = {}, spans = {} }, root = 0, stage = '', diags = {}, spans = {} }
    for _, s in ipairs(STAGES) do
        c.stage = s.name
        c.diags = s.run(c)
        c.spans = c.src.spans
        if #c.diags > 0 or s.name == stage then
            break
        end
    end
    return c
end

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
