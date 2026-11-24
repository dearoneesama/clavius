-- Converts between programs and printable s-expressions. A node is written as its tag followed by its
-- fields in schema order:
--
--   (Unit main linear
--     [(VarDecl x int)]
--     [(Assume 1 (BinOp > (Var x) (Int 0)))
--      (Check 1 (BinOp > (BinOp + (Var x) (Int 1)) (Var x)))])
--
--   (obligation 1 :kind range :node 0)
--
--   (assumption 1 :kind branch :node 0)
--
-- A source arena is written the same way. Side tables follow a node's fields:
--
--   (Local [(BinOp add (Id x$1 :type int53) (Literal number 1 :type int53) :type int53)] [(Binder y$2 :type int53)])
--   (While [] (Id on$3 :type boolean) (Block [(Set [(Id y$2 :type int53)] [(Literal number 1 :type int53)])]) :writes [y$2])

local arena = require 'clavius.ir.arena'
local read = require 'clavius.sexpr.read'
local schema = require 'clavius.sexpr.schema'
local write = require 'clavius.sexpr.write'

--- A core arena with its declarations, its units and the tables that its `Check` and `Assume` nodes
--- refer to.
--- @class CoreProgram
--- @field core CoreArena
--- @field decls NodeId[] the SortDecl, FunDecl and Axiom nodes
--- @field units NodeId[] the Unit nodes
--- @field obligations Obligation[] indexed by obligation id
--- @field assumptions Assumption[] indexed by assumption id

--- A node field's value as read by the field's name.
--- @alias FieldValue NodeId|NodeId[]|string|integer|boolean|nil

--- The side tables written with a source arena.
--- @class SrcDumpTables
--- @field names table<NodeId, string>|nil unique names, written in place of the names of Binder and Id nodes
--- @field types table<NodeId, string>|nil types, written after a node's fields as `:type T`
--- @field writes table<NodeId, string[]>|nil the locals that each loop writes, written after its fields as `:writes [x$1 y$2]`

--- A shape error while reading. It's raised with `error` and caught in `read_core`.
--- @class DumpError
--- @field offset integer
--- @field message string

local M = {}

local DECLARATIONS = { SortDecl = true, FunDecl = true, Axiom = true }

--- @param nodes (SrcNode|CoreNode)[]
--- @param specs table<string, SexpFieldSpec[]> the fields of each kind
--- @param id NodeId
--- @param tables SrcDumpTables
--- @return Sexp
local function node_sexp(nodes, specs, id, tables)
    local n = nodes[id]
    local fields = n --[[@as table<string, FieldValue>]]
    --- @type Sexp[]
    local items = { write.sym(n.tag) }
    for _, f in ipairs(specs[n.tag]) do
        local v = fields[f.name]
        if f.name == 'name' and f.shape == 'str' and tables.names and tables.names[id] then
            v = tables.names[id]
        end
        if v == nil then
            items[#items + 1] = write.sym 'nil'
        elseif f.shape == 'node' or f.shape == 'opt' then
            items[#items + 1] = node_sexp(nodes, specs, v --[[@as NodeId]], tables)
        elseif f.shape == 'list' then
            local kids = {}
            for i, kid in
                ipairs(v --[[@as NodeId[] ]])
            do
                kids[i] = node_sexp(nodes, specs, kid, tables)
            end
            items[#items + 1] = write.vec(kids)
        elseif
            (f.shape == 'str' or f.shape == 'opt_str')
            and (
                not write.is_symbol_text(v --[[@as string]])
                or ((n.tag == 'Literal' or n.tag == 'ClvTypeLiteral') and fields.kind == 'string')
            )
        then
            -- a string literal is always quoted, so `(Literal string "x")` differs from `(Id x)`
            items[#items + 1] = write.str(v --[[@as string]])
        else
            -- int, bool, enum, and strings that are valid symbols
            items[#items + 1] = write.sym(tostring(v))
        end
    end
    if tables.types and tables.types[id] then
        items[#items + 1] = write.sym ':type'
        items[#items + 1] = write.sym(tables.types[id])
    end
    if tables.writes and tables.writes[id] then
        local names = {}
        for i, name in ipairs(tables.writes[id]) do
            names[i] = write.sym(name)
        end
        items[#items + 1] = write.sym ':writes'
        items[#items + 1] = write.vec(names)
    end
    return write.list(items)
end

--- Writes the tree under `root` of a source arena with the given side tables.
--- @param src SrcArena
--- @param root NodeId
--- @param tables SrcDumpTables
--- @return Sexp
function M.write_src(src, root, tables)
    return node_sexp(src.nodes, schema.source, root, tables)
end

--- @param head string `obligation` or `assumption`
--- @param id integer
--- @param record Obligation|Assumption
--- @return Sexp
local function record_sexp(head, id, record)
    local items = {
        write.sym(head),
        write.sym(tostring(id)),
        write.sym ':kind',
        write.sym(record.kind),
        write.sym ':node',
        write.sym(tostring(record.node)),
    }
    local extra = head == 'obligation' and (record --[[@as Obligation]]).clause or (record --[[@as Assumption]]).decl
    if extra ~= nil then
        items[#items + 1] = write.sym(head == 'obligation' and ':clause' or ':decl')
        items[#items + 1] = write.sym(tostring(extra))
    end
    return write.list(items)
end

--- Writes a program as s-expressions: its declarations and units as trees, then its obligations and
--- assumptions. A node shared by two parents is written in full under each.
--- @param prog CoreProgram
--- @return Sexp[]
function M.write_core(prog)
    local out = {}
    for _, id in ipairs(prog.decls) do
        out[#out + 1] = node_sexp(prog.core.nodes, schema.core, id, {})
    end
    for _, id in ipairs(prog.units) do
        out[#out + 1] = node_sexp(prog.core.nodes, schema.core, id, {})
    end
    for id, o in ipairs(prog.obligations) do
        out[#out + 1] = record_sexp('obligation', id, o)
    end
    for id, a in ipairs(prog.assumptions) do
        out[#out + 1] = record_sexp('assumption', id, a)
    end
    return out
end

--- @param x Sexp
--- @param message string
local function fail(x, message)
    error({ offset = x.start or 1, message = message } --[[@as DumpError]], 0)
end

--- @param x Sexp
--- @return integer
local function read_int(x)
    if x.tag ~= 'Sym' or not x.text:match '^%-?%d+$' then
        fail(x, 'expected an integer')
    end
    --- @cast x SexpSym
    return assert(tonumber(x.text))
end

--- Reads a node and the nodes under it into `core` and returns its id. Children are added first.
--- @param core CoreArena
--- @param file FileId
--- @param x Sexp
--- @mut core
--- @return NodeId
local function read_node(core, file, x)
    if x.tag ~= 'List' or not x.items[1] or x.items[1].tag ~= 'Sym' then
        fail(x, 'expected a core node')
    end
    --- @cast x SexpList
    local tag = x.items[1].text
    local fields = schema.core[tag]
    if not fields then
        fail(x.items[1], ('unknown core kind %s'):format(tag))
    end
    if #x.items ~= #fields + 1 then
        fail(x, ('%s takes %d fields, found %d'):format(tag, #fields, #x.items - 1))
    end
    --- @type table<string, FieldValue>
    local node = { tag = tag }
    for i, f in ipairs(fields) do
        local item = x.items[i + 1]
        if f.shape == 'node' then
            node[f.name] = read_node(core, file, item)
        elseif f.shape == 'list' then
            if item.tag ~= 'Vec' then
                fail(item, ('expected a [ … ] list for %s'):format(f.name))
            end
            --- @cast item SexpVec
            local kids = {}
            for j, kid in ipairs(item.items) do
                kids[j] = read_node(core, file, kid)
            end
            node[f.name] = kids
        elseif f.shape == 'int' then
            node[f.name] = read_int(item)
        elseif item.tag ~= 'Sym' and not (f.shape == 'str' and item.tag == 'Str') then
            fail(item, ('expected a symbol for %s'):format(f.name))
        else
            --- @cast item SexpSym|SexpStr
            local text = item.text
            if f.shape == 'bool' then
                if text ~= 'true' and text ~= 'false' then
                    fail(item, 'expected true or false')
                end
                node[f.name] = text == 'true'
            elseif f.shape == 'enum' then
                local ok = false
                for _, v in ipairs(f.values) do
                    ok = ok or v == text
                end
                if not ok then
                    fail(item, ('%s must be one of %s'):format(f.name, table.concat(f.values, ' ')))
                end
                node[f.name] = text
            else
                node[f.name] = text
            end
        end
    end
    return arena.add_core(core, node --[[@as CoreNode]], arena.span(file, x.start or 1, x.finish or 0))
end

--- Reads `(obligation ID :kind K :node N)` or `(assumption ID :kind K :node N)`, whose id must be
--- `expected_id`.
--- @param x SexpList
--- @param expected_id integer
--- @return Obligation|Assumption
local function read_record(x, expected_id)
    local head = x.items[1] --[[@as SexpSym]]
    if not x.items[2] or read_int(x.items[2]) ~= expected_id then
        fail(x, ('expected %s id %d: ids count up from 1'):format(head.text, expected_id))
    end
    --- @type table<string, Sexp>
    local attrs = {}
    local i = 3
    while i <= #x.items do
        local key = x.items[i]
        local value = x.items[i + 1]
        local extra = head.text == 'obligation' and ':clause' or ':decl'
        if key.tag ~= 'Sym' or (key.text ~= ':kind' and key.text ~= ':node' and key.text ~= extra) or not value then
            fail(key, ('expected :kind, :node or %s with a value'):format(extra))
        end
        --- @cast key SexpSym
        if attrs[key.text] then
            fail(key, ('duplicate %s'):format(key.text))
        end
        attrs[key.text] = value
        i = i + 2
    end
    local kind = attrs[':kind']
    local node = attrs[':node']
    if not kind or kind.tag ~= 'Sym' or not node then
        fail(x, ('%s needs :kind with a symbol and :node'):format(head.text))
    end
    --- @cast kind SexpSym
    --- @cast node Sexp
    -- the kind is checked against the closed list by validate, not here
    local record = { kind = kind.text, node = read_int(node) }
    local extra = attrs[':clause'] or attrs[':decl']
    if extra then
        record[head.text == 'obligation' and 'clause' or 'decl'] = read_int(extra)
    end
    return record --[[@as Obligation|Assumption]]
end

--- Reads a core program: any number of declarations, units, obligations and assumptions in any order.
--- Each node's span covers its form in `text`. Returns the first error instead if `text` is malformed.
--- @param text string
--- @param file FileId
--- @return CoreProgram|nil prog
--- @return SexpReadError|nil err
function M.read_core(text, file)
    local xs, err = read.read_all(text)
    if not xs then
        return nil, err
    end
    --- @type CoreProgram
    local prog = { core = arena.new_core(), decls = {}, units = {}, obligations = {}, assumptions = {} }
    --- @return nil
    local function read_forms()
        for _, x in ipairs(xs) do
            local head = x.tag == 'List' and x.items[1]
            if head and head.tag == 'Sym' and head.text == 'obligation' then
                --- @cast x SexpList
                prog.obligations[#prog.obligations + 1] = read_record(x, #prog.obligations + 1) --[[@as Obligation]]
            elseif head and head.tag == 'Sym' and head.text == 'assumption' then
                --- @cast x SexpList
                prog.assumptions[#prog.assumptions + 1] = read_record(x, #prog.assumptions + 1) --[[@as Assumption]]
            elseif head and head.tag == 'Sym' and head.text == 'Unit' then
                prog.units[#prog.units + 1] = read_node(prog.core, file, x)
            elseif head and head.tag == 'Sym' and DECLARATIONS[head.text] then
                prog.decls[#prog.decls + 1] = read_node(prog.core, file, x)
            else
                fail(x, 'expected a declaration, Unit, obligation or assumption')
            end
        end
    end
    local ok, e = pcall(read_forms)
    if not ok then
        if type(e) ~= 'table' then
            error(e, 0)
        end
        --- @cast e DumpError
        return nil, read.error_at(text, e.offset, e.message)
    end
    return prog, nil
end

return M
