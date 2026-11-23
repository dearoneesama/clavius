-- Connects the stages for the command line and the tests. A Lua file goes through the stages in
-- order, and the run stops after the first stage that reports a diagnostic.

local boogie_print = require 'clavius.backend.boogie.print'
local boogie_run = require 'clavius.backend.boogie.run'
local dump = require 'clavius.sexpr.dump'
local effects = require 'clavius.passes.effects'
local elaborate = require 'clavius.elaborate'
local index = require 'clavius.ir.index'
local parse = require 'clavius.syntax.parse'
local resolve = require 'clavius.passes.resolve'
local termination = require 'clavius.passes.termination'
local types = require 'clavius.passes.types'
local validate = require 'clavius.validate'
local write = require 'clavius.sexpr.write'

--- One Lua file on its way through the stages. Each stage fills in its fields.
--- @class CompilerContext
--- @field file FileId
--- @field text string
--- @field src SrcArena
--- @field root NodeId
--- @field index NodeIndex|nil
--- @field res Resolution|nil
--- @field info TypeInfo|nil
--- @field effects Effects|nil
--- @field termination Termination|nil
--- @field prog CoreProgram|nil
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

--- @param c CompilerContext
--- @return Diag[]
local function run_effects(c)
    c.effects = effects.run(c.src, assert(c.res), assert(c.index))
    return {}
end

--- @param c CompilerContext
--- @return Diag[]
local function run_termination(c)
    local result, diags = termination.run(c.src, assert(c.index), assert(c.info))
    c.termination = result
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_elaborate(c)
    c.prog = elaborate.run(c.src, c.root, assert(c.res), assert(c.info), assert(c.effects), assert(c.termination))
    return {}
end

--- @param c CompilerContext
--- @return Diag[]
local function run_validate(c)
    local prog = assert(c.prog)
    local source = { src = c.src, index = assert(c.index), callees = assert(c.info).callees, cycle = assert(c.termination).cycle }
    return validate.run(prog.core, prog.decls, prog.units, prog.obligations, prog.assumptions, source)
end

--- Each stage needs the results of every stage before it.
--- @type Stage[]
local STAGES = {
    { name = 'parse', run = run_parse },
    { name = 'resolve', run = run_resolve },
    { name = 'types', run = run_types },
    { name = 'effects', run = run_effects },
    { name = 'termination', run = run_termination },
    { name = 'elaborate', run = run_elaborate },
    { name = 'validate', run = run_validate },
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
        -- validate reports on core nodes, and each carries the span of the source node it comes from
        c.spans = s.name == 'validate' and assert(c.prog).core.spans or c.src.spans
        if #c.diags > 0 or s.name == stage then
            break
        end
    end
    return c
end

--- Prints the core program that `elaborate` produced: its declarations, its units, its obligations and its
--- assumptions, with a blank line between the groups.
--- Not a coredump.
--- @param c CompilerContext
--- @return string
function M.dump_core(c)
    local prog = assert(c.prog)
    local xs = dump.write_core(prog)
    local groups = {}
    local first = 1
    for _, size in ipairs { #prog.decls, #prog.units, #prog.obligations, #prog.assumptions } do
        if size > 0 then
            groups[#groups + 1] = write.write_all { unpack(xs, first, first + size - 1) }
        end
        first = first + size
    end
    return table.concat(groups, '\n')
end

--- Prints what the last stage run on a compiler context produced: the source arena with the side tables so
--- far, or the core program from `elaborate` on.
--- @param c CompilerContext
--- @return string
function M.dump(c)
    if c.prog then
        return M.dump_core(c)
    end
    --- @type SrcDumpTables
    local tables = { names = nil, types = c.info and c.info.types, writes = nil }
    if c.res then
        -- an Id is written with the name of its Binder
        local names = {}
        for id, name in pairs(c.res.names) do
            names[id] = name
        end
        for id, binder in pairs(c.res.decl) do
            names[id] = c.res.names[binder]
        end
        tables.names = names
    end
    if c.res and c.effects then
        -- a loop is written with the names of the locals it writes
        local writes = {}
        for id, list in pairs(c.effects.writes) do
            writes[id] = {}
            for i, w in ipairs(list) do
                writes[id][i] = c.res.names[w.root]
            end
        end
        tables.writes = writes
    end
    return write.write_all { dump.write_src(c.src, c.root, tables) }
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
    return prog, nil, validate.run(prog.core, prog.decls, prog.units, prog.obligations, prog.assumptions, nil)
end

--- Prints a valid core program as a Boogie file.
--- @param prog CoreProgram
--- @return string
function M.lower_core(prog)
    return boogie_print.program(prog.core, prog.decls, prog.units, nil)
end

--- Verifies a valid core program with Boogie. Returns the ids of the failing obligations in ascending order,
--- or nil and an error when Boogie gives no verdict.
--- @param prog CoreProgram
--- @return integer[]|nil failed
--- @return string|nil err
function M.verify_core(prog)
    return boogie_run.check(prog.core, prog.decls, prog.units, nil)
end

return M
