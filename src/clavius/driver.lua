-- Connects the stages for the command line and the tests. A Lua file goes through the stages in
-- order, and the run stops after the first stage that reports a diagnostic.

local boogie_print = require 'clavius.backend.boogie.print'
local boogie_run = require 'clavius.backend.boogie.run'
local dump = require 'clavius.sexpr.dump'
local effects = require 'clavius.passes.effects'
local elaborate = require 'clavius.elaborate'
local index = require 'clavius.ir.index'
local interfaces = require 'clavius.passes.interfaces'
local parse = require 'clavius.syntax.parse'
local resolve = require 'clavius.passes.resolve'
local termination = require 'clavius.passes.termination'
local types = require 'clavius.passes.types'
local validate = require 'clavius.validate'
local write = require 'clavius.sexpr.write'

--- A file of a run: the Lua module being verified, or a `---@meta` file.
--- @class SourceFile
--- @field name string as messages show it
--- @field text string
--- @field kind 'module' | MetaKind

--- A `---@meta` file to read, by its name and text.
--- @class MetaSource
--- @field name string
--- @field text string

--- One Lua file on its way through the stages. Each stage fills in its fields.
--- @class CompilerContext
--- @field file FileId
--- @field files table<FileId, SourceFile> the Lua file and the `---@meta` files
--- @field src SrcArena
--- @field root NodeId
--- @field metas MetaRoot[] the parsed `---@meta` files
--- @field index NodeIndex|nil
--- @field iface Interface|nil
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

--- The modules whose files hold the shipped specs, read in this order.
local STDLIB = { 'clavius.meta.math' }

--- Returns the shipped `---@meta` files of the standard library, found through `package.path`.
--- @return MetaSource[]
function M.stdlib()
    local out = {}
    for _, module in ipairs(STDLIB) do
        local relative = module:gsub('%.', '/')
        local found = nil
        -- read as text, never required: running one would assign into the real library
        for template in package.path:gmatch '[^;]+' do
            local path = template:gsub('%?', relative)
            local f = io.open(path, 'rb')
            if f then
                found = { name = relative .. '.lua', text = f:read '*a' }
                f:close()
                break
            end
        end
        out[#out + 1] = assert(found, ('clavius: the shipped specs %s are missing from package.path'):format(module))
    end
    return out
end

--- @param c CompilerContext
--- @return Diag[]
local function run_parse(c)
    -- the Lua file comes first, so its node ids don't depend on the `---@meta` files
    local root, diags = parse.append(c.src, c.files[c.file].text, c.file, false)
    c.root = root
    if root == 0 then
        return diags
    end
    local ids = {}
    for id in pairs(c.files) do
        if id ~= c.file then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local f = c.files[id]
        local meta_root, meta_diags = parse.append(c.src, f.text, id, true)
        for _, d in ipairs(meta_diags) do
            diags[#diags + 1] = d
        end
        c.metas[#c.metas + 1] = {
            root = meta_root,
            kind = f.kind --[[@as MetaKind]],
        }
    end
    if #diags == 0 then
        c.index = index.build(c.src)
    end
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_interfaces(c)
    local iface, diags = interfaces.run(c.src, c.metas)
    c.iface = iface
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_resolve(c)
    local res, diags = resolve.run(c.src, c.root, c.iface)
    c.res = res
    return diags
end

--- @param c CompilerContext
--- @return Diag[]
local function run_types(c)
    local info, diags = types.run(c.src, c.root, assert(c.res), c.iface)
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
    local source = { src = c.src, index = assert(c.index), ops = assert(c.info).ops, cycle = assert(c.termination).cycle }
    return validate.run(prog.core, prog.decls, prog.units, prog.obligations, prog.assumptions, source)
end

--- Each stage needs the results of every stage before it.
--- @type Stage[]
local STAGES = {
    { name = 'parse', run = run_parse },
    { name = 'interfaces', run = run_interfaces },
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
--- diagnostic. The shipped specs are part of every run, and `metas` adds the project's `---@meta` files.
--- @param stage string one of `STAGES`
--- @param text string
--- @param file FileId
--- @param metas MetaSource[]|nil
--- @param name string|nil the Lua file's name, as messages show it
--- @return CompilerContext
function M.run_until(stage, text, file, metas, name)
    --- @type table<FileId, SourceFile>
    local files = { [file] = { name = name or '', text = text, kind = 'module' } }
    local next_id = file
    for _, list in ipairs { M.stdlib(), metas or {} } do
        for _, m in ipairs(list) do
            next_id = next_id + 1
            files[next_id] = { name = m.name, text = m.text, kind = list == metas and 'extern' or 'stdlib' }
        end
    end
    --- @type CompilerContext
    local c = {
        file = file,
        files = files,
        src = { nodes = {}, spans = {} },
        root = 0,
        metas = {},
        stage = '',
        diags = {},
        spans = {},
    }
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
--- @param opts BoogieRunOptions|nil
--- @return integer[]|nil failed
--- @return string|nil err
function M.verify_core(prog, opts)
    return boogie_run.check(prog.core, prog.decls, prog.units, opts)
end

return M
