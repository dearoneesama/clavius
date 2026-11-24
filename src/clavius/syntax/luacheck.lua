-- Converts what luacheck's parser and lexer return into source nodes and comment records. This is the
-- only module that requires luacheck, and nothing in luacheck's own format leaves it.

local arena = require 'clavius.ir.arena'
local comments = require 'clavius.syntax.comments'
local diag = require 'clavius.ir.diag'
local lexer = require 'luacheck.lexer'
local parser = require 'luacheck.parser'
local splice = require 'clavius.syntax.splice'

--- A node of luacheck's AST: a tag, a range and its children in the array part. Blocks and
--- expression lists are arrays with no tag.
--- @class LcNode
--- @field tag string|nil
--- @field offset integer|nil
--- @field end_offset integer|nil
--- @field implicit boolean|nil set on the `self` parameter of a method defined with `:`
--- @field [integer] any

--- A short comment as luacheck's parser returns it.
--- @class LcComment
--- @field contents string
--- @field line integer
--- @field offset integer
--- @field end_offset integer

--- A syntax error that luacheck's parser raises.
--- @class LcSyntaxError
--- @field msg string
--- @field offset integer
--- @field end_offset integer

--- The text interface that luacheck's lexer reads through.
--- @class LcSource
--- @field get_codepoint fun(self: LcSource, i: integer): integer|nil
--- @field get_substring fun(self: LcSource, from: integer, to: integer): string
--- @field get_printable_substring fun(self: LcSource, from: integer, to: integer): string
--- @field get_length fun(self: LcSource): integer
--- @field find fun(self: LcSource, pattern: string, from: integer): integer|nil, integer|nil

--- A comment and its span. A short comment's `text` follows its `--`, so `---@clavius begin` gives
--- `-@clavius begin`. A long comment's `text` is what lies between its brackets.
--- @class Comment
--- @field text string
--- @field span Span
--- @field line integer the line it starts on

--- A converted file.
--- @class Chunk
--- @field statements NodeId[] the top-level statements
--- @field comments Comment[] short comments in source order
--- @field regions SpliceRegion[]
--- @field annotations LongAnnotation[] the long comments that start with a tag
--- @field marks MarkedSpan[] where the marking changes, each after the spans that hold it
--- @field ghosts GhostRange[] the unmasked ghost comments
--- @field exits integer[] the last offset of each `return` and `break` statement

--- What luacheck reads from a text, and the errors its lexer finds.
--- @class LcParse
--- @field ast LcNode[]
--- @field short Comment[]
--- @field long Comment[]
--- @field diags Diag[]

--- A statement of a list, or the statements that one ghost comment holds.
--- @class LcItem
--- @field nodes LcNode[]
--- @field ghost GhostRange|nil
--- @field split boolean whether the statement starts or ends in a ghost comment that it doesn't lie in

--- @class ConvertState
--- @field src SrcArena
--- @field file FileId
--- @field shift integer added to luacheck's offsets to get the file's
--- @field diags Diag[]
--- @field vararg boolean whether the function being converted takes `...`
--- @field loops integer the loops around the code being converted, inside its function
--- @field cursor SpliceCursor|nil the directives, when converting a whole file
--- @field marked boolean whether the code being converted is marked
--- @field marks MarkedSpan[]
--- @field ghosts GhostRange[]
--- @field consumed table<GhostRange, boolean> the ghost comments whose statements are converted
--- @field open table<GhostRange, boolean> the ghost comments whose statements are being converted
--- @field exits integer[]

local M = {}

-- the Lua 5.3 operators that luacheck parses and LuaJIT rejects
local LUA53_OPS = { idiv = true, band = true, bor = true, bxor = true, shl = true, shr = true, bnot = true }

local LITERAL_KINDS = { Nil = 'nil', True = 'true', False = 'false', Number = 'number', String = 'string' }

-- luacheck's loop tags
local LOOPS = { While = true, Repeat = true, Fornum = true, Forin = true }

--- Makes a source object over the raw bytes of `text`. luacheck's own decoder counts code points in a
--- valid UTF-8 file, so its offsets wouldn't be byte offsets after the first non-ASCII character. Over
--- raw bytes, the lexer takes the path it takes for files that aren't UTF-8.
--- @param text string
--- @return LcSource
local function byte_source(text)
    --- @param _ LcSource
    --- @param i integer
    --- @return integer|nil
    local function get_codepoint(_, i)
        return text:byte(i)
    end
    --- @param _ LcSource
    --- @param from integer
    --- @param to integer
    --- @return string
    local function get_substring(_, from, to)
        return text:sub(from, to)
    end
    --- @param c string
    --- @return string
    local function escape(c)
        return ('\\%03d'):format(c:byte())
    end
    --- @param _ LcSource
    --- @param from integer
    --- @param to integer
    --- @return string
    local function get_printable_substring(_, from, to)
        return (text:sub(from, to):gsub('[^\32-\126]', escape))
    end
    --- @return integer
    local function get_length()
        return #text
    end
    --- @param _ LcSource
    --- @param pattern string
    --- @param from integer
    --- @return integer|nil
    --- @return integer|nil
    local function find(_, pattern, from)
        return text:find(pattern, from)
    end
    return {
        get_codepoint = get_codepoint,
        get_substring = get_substring,
        get_printable_substring = get_printable_substring,
        get_length = get_length,
        find = find,
    }
end

--- @param st ConvertState
--- @param start integer
--- @param finish integer
--- @return Span
local function span(st, start, finish)
    return arena.span(st.file, start + st.shift, finish + st.shift)
end

--- @param st ConvertState
--- @param node LcNode
--- @return Span
local function node_span(st, node)
    return span(st, assert(node.offset), assert(node.end_offset))
end

--- Reports syntax that luacheck accepts and LuaJIT rejects. `form` names the case.
--- @param st ConvertState
--- @param s Span
--- @param form string
--- @mut st
local function reject(st, s, form)
    st.diags[#st.diags + 1] = diag.at_span('E-syntax', s, { form })
end

--- @param st ConvertState
--- @param node SrcNode
--- @param s Span
--- @mut st
--- @return NodeId
local function add(st, node, s)
    return arena.add_src(st.src, node, s)
end

-- Forward declarations for mutually recursive functions.
local expression, statement_list, block

--- @param st ConvertState
--- @param list LcNode[]
--- @mut st
--- @return NodeId[]
local function expression_list(st, list)
    local ids = {}
    for i, node in ipairs(list) do
        ids[i] = expression(st, node)
    end
    return ids
end

--- @param st ConvertState
--- @param node LcNode an `Id`
--- @mut st
--- @return NodeId
local function binder(st, node)
    return add(st, { tag = 'Binder', name = node[1] }, node_span(st, node))
end

--- Converts a `Function` node: `{ params, body }`. A function that a statement defines comes with the
--- placement of the directives above that statement; any other one has no directives, and its body is
--- marked when the code around it is.
--- @param st ConvertState
--- @param node LcNode
--- @param placed Placement|nil
--- @mut st
--- @return NodeId
local function func(st, node, placed)
    local params, vararg = {}, false
    local header_end = assert(node.offset)
    for _, p in ipairs(node[1]) do
        if p.tag == 'Dots' then
            vararg = true
        else
            params[#params + 1] = binder(st, p)
        end
        header_end = p.end_offset or header_end
    end
    local marked = st.marked
    if placed then
        marked = placed.marked
    end
    if st.cursor then
        -- a directive in the parameter list is above no statement
        splice.dangle(st.cursor, header_end, st.marked)
        if marked ~= st.marked then
            st.marks[#st.marks + 1] = { span = node_span(st, node), marked = marked }
        end
    end
    local outer_vararg, outer_loops, outer_marked = st.vararg, st.loops, st.marked
    st.vararg, st.loops, st.marked = vararg, 0, marked
    local body = block(st, node[2], assert(node.offset))
    if st.cursor then
        splice.dangle(st.cursor, assert(node.end_offset), marked)
    end
    st.vararg, st.loops, st.marked = outer_vararg, outer_loops, outer_marked
    local directives = placed and placed.directives or {}
    return add(st, { tag = 'Function', directives = directives, params = params, vararg = vararg, body = body }, node_span(st, node))
end

--- Returns the function that a statement defines: `local function f`, `function t.f`, or a `local` or
--- assignment of one function value to one name.
--- @param node LcNode
--- @return LcNode|nil
local function defined_function(node)
    if node.tag == 'Localrec' then
        return node[2][1]
    elseif (node.tag == 'Local' or node.tag == 'Set') and #node[1] == 1 and node[2] and #node[2] == 1 and node[2][1].tag == 'Function' then
        return node[2][1]
    end
    return nil
end

--- @param st ConvertState
--- @param node LcNode
--- @mut st
--- @return NodeId
function expression(st, node)
    local tag = node.tag
    local s = node_span(st, node)
    if LITERAL_KINDS[tag] then
        local text = node[1]
        if tag == 'Nil' or tag == 'True' or tag == 'False' then
            text = LITERAL_KINDS[tag]
        end
        return add(st, { tag = 'Literal', kind = LITERAL_KINDS[tag], text = text }, s)
    elseif tag == 'Id' then
        return add(st, { tag = 'Id', name = node[1] }, s)
    elseif tag == 'Dots' then
        if not st.vararg then
            reject(st, s, 'vararg-outside-vararg-function')
        end
        return add(st, { tag = 'Dots' }, s)
    elseif tag == 'Paren' then
        return add(st, { tag = 'Paren', expr = expression(st, node[1]) }, s)
    elseif tag == 'Index' then
        local obj = expression(st, node[1])
        return add(st, { tag = 'Index', obj = obj, key = expression(st, node[2]) }, s)
    elseif tag == 'Call' then
        local f = expression(st, node[1])
        local args = {}
        for i = 2, #node do
            args[#args + 1] = expression(st, node[i])
        end
        return add(st, { tag = 'Call', func = f, method = nil, args = args }, s)
    elseif tag == 'Invoke' then
        local obj = expression(st, node[1])
        local args = {}
        for i = 3, #node do
            args[#args + 1] = expression(st, node[i])
        end
        return add(st, { tag = 'Call', func = obj, method = node[2][1], args = args }, s)
    elseif tag == 'Function' then
        return func(st, node)
    elseif tag == 'Table' then
        local fields = {}
        for _, item in ipairs(node) do
            local key, value
            if item.tag == 'Pair' then
                key = expression(st, item[1])
                value = expression(st, item[2])
            else
                value = expression(st, item)
            end
            fields[#fields + 1] = add(st, { tag = 'TableField', key = key, value = value }, node_span(st, item))
        end
        return add(st, { tag = 'Table', fields = fields }, s)
    elseif tag == 'Op' and node[3] == nil then
        local arg = expression(st, node[2])
        if LUA53_OPS[node[1]] then
            reject(st, s, 'lua53-operator')
            return arg
        end
        return add(st, { tag = 'UnOp', op = node[1], arg = arg }, s)
    elseif tag == 'Op' then
        local lhs = expression(st, node[2])
        local rhs = expression(st, node[3])
        if LUA53_OPS[node[1]] then
            reject(st, s, 'lua53-operator')
            return rhs
        end
        return add(st, { tag = 'BinOp', op = node[1], lhs = lhs, rhs = rhs }, s)
    end
    error(('luacheck adapter: unhandled expression %s'):format(tostring(tag)))
end

--- Converts the values of a `local` or an assignment. The one that the statement defines as a function
--- gets the placement of the directives above it.
--- @param st ConvertState
--- @param list LcNode[]
--- @param fn LcNode|nil
--- @param placed Placement|nil
--- @mut st
--- @return NodeId[]
local function values_of(st, list, fn, placed)
    local ids = {}
    for i, node in ipairs(list) do
        if node == fn then
            ids[i] = func(st, node, placed)
        else
            ids[i] = expression(st, node)
        end
    end
    return ids
end

--- Converts a statement. `above` holds the directives above it.
--- @param st ConvertState
--- @param node LcNode
--- @param above Directive[]
--- @mut st
--- @return NodeId
local function statement(st, node, above)
    local tag = node.tag
    local s = node_span(st, node)
    local fn = defined_function(node)
    --- @type SpliceBelow
    local below = 'other'
    if fn then
        below = 'function'
    elseif LOOPS[tag] then
        below = 'loop'
    end
    local placed = nil
    if st.cursor then
        placed = splice.place(st.cursor, above, below, st.marked)
    end
    local directives = (placed and below == 'loop') and placed.directives or {}
    if tag == 'Local' then
        local values = values_of(st, node[2] or {}, fn, placed)
        local names = {}
        for i, id in ipairs(node[1]) do
            names[i] = binder(st, id)
        end
        return add(st, { tag = 'Local', values = values, names = names }, s)
    elseif tag == 'Localrec' then
        local b = binder(st, node[1][1])
        return add(st, { tag = 'LocalFunction', binder = b, func = func(st, node[2][1], placed) }, s)
    elseif tag == 'Set' or tag == 'OpSet' then
        if tag == 'OpSet' then
            reject(st, s, 'compound-assignment')
        end
        local targets = expression_list(st, node[1])
        return add(st, { tag = 'Set', targets = targets, values = values_of(st, node[2], fn, placed) }, s)
    elseif tag == 'Call' or tag == 'Invoke' then
        return expression(st, node)
    elseif tag == 'Do' then
        return add(st, { tag = 'Block', statements = statement_list(st, node) }, s)
    elseif tag == 'If' then
        local arms = {}
        for i = 1, #node - 1, 2 do
            local cond = expression(st, node[i])
            local body = block(st, node[i + 1], node[i].end_offset + 1)
            local arm_span = span(st, node[i].offset, st.src.spans[body].finish)
            arms[#arms + 1] = add(st, { tag = 'IfArm', cond = cond, body = body }, arm_span)
        end
        local else_block = nil
        if #node % 2 == 1 then
            else_block = block(st, node[#node], st.src.spans[arms[#arms]].finish + 1)
        end
        return add(st, { tag = 'If', arms = arms, else_block = else_block }, s)
    elseif tag == 'While' then
        local cond = expression(st, node[1])
        st.loops = st.loops + 1
        local body = block(st, node[2], node[1].end_offset + 1)
        st.loops = st.loops - 1
        return add(st, { tag = 'While', directives = directives, cond = cond, body = body }, s)
    elseif tag == 'Repeat' then
        st.loops = st.loops + 1
        local body = block(st, node[1], assert(node.offset))
        st.loops = st.loops - 1
        return add(st, { tag = 'Repeat', directives = directives, body = body, cond = expression(st, node[2]) }, s)
    elseif tag == 'Fornum' then
        local start = expression(st, node[2])
        local limit = expression(st, node[3])
        local step = nil
        if #node == 5 then
            step = expression(st, node[4])
        end
        local var = binder(st, node[1])
        st.loops = st.loops + 1
        local body = block(st, node[#node], node[#node - 1].end_offset + 1)
        st.loops = st.loops - 1
        local fornum = { tag = 'Fornum', directives = directives, start = start, limit = limit, step = step, var = var, body = body }
        return add(st, fornum, s)
    elseif tag == 'Forin' then
        local iters = expression_list(st, node[2])
        local names = {}
        for i, id in ipairs(node[1]) do
            names[i] = binder(st, id)
        end
        st.loops = st.loops + 1
        local body = block(st, node[3], node[2][#node[2]].end_offset + 1)
        st.loops = st.loops - 1
        return add(st, { tag = 'Forin', directives = directives, iters = iters, names = names, body = body }, s)
    elseif tag == 'Return' then
        st.exits[#st.exits + 1] = s.finish
        return add(st, { tag = 'Return', values = expression_list(st, node) }, s)
    elseif tag == 'Break' then
        if st.loops == 0 then
            reject(st, s, 'break-outside-loop')
        end
        st.exits[#st.exits + 1] = s.finish
        return add(st, { tag = 'Break' }, s)
    elseif tag == 'Goto' then
        return add(st, { tag = 'Goto', label = node[1] }, s)
    elseif tag == 'Label' then
        return add(st, { tag = 'Label', name = node[1] }, s)
    end
    error(('luacheck adapter: unhandled statement %s'):format(tostring(tag)))
end

--- Returns the ghost comment that holds the file offset `offset`, if any, other than one whose
--- statements are being converted.
--- @param st ConvertState
--- @param offset integer
--- @return GhostRange|nil
local function ghost_at(st, offset)
    for _, gr in ipairs(st.ghosts) do
        if arena.contains(gr.span, offset) and not st.open[gr] then
            return gr
        end
    end
    return nil
end

--- Groups a statement list into items: each statement on its own, except that those a ghost comment
--- holds form one item.
--- @param st ConvertState
--- @param list LcNode[]
--- @return LcItem[]
local function items(st, list)
    local out = {}
    for _, node in ipairs(list) do
        local finish = assert(node.end_offset) + st.shift
        local gr = ghost_at(st, assert(node.offset) + st.shift)
        local last = out[#out]
        if gr and finish <= gr.span.finish and last and last.ghost == gr then
            -- a later statement of the comment the last item holds joins it
            last.nodes[#last.nodes + 1] = node
        elseif gr and finish <= gr.span.finish then
            -- the first statement of a ghost comment starts its item
            out[#out + 1] = { nodes = { node }, ghost = gr, split = false }
        else
            -- exec code, split when it starts or ends inside a ghost comment and so runs across its edge
            out[#out + 1] = { nodes = { node }, ghost = nil, split = gr ~= nil or ghost_at(st, finish) ~= nil }
        end
    end
    return out
end

--- Converts a statement with the directives above it.
--- @param st ConvertState
--- @param node LcNode
--- @param top boolean whether it is a top-level statement
--- @mut st
--- @return NodeId
local function one_statement(st, node, top)
    local above = {}
    if st.cursor then
        above = splice.take(st.cursor, assert(node.offset), top, st.marked)
    end
    local id = statement(st, node, above)
    if st.cursor then
        -- what the statement holds but its own statements don't take, such as a directive in an expression
        splice.dangle(st.cursor, assert(node.end_offset), st.marked)
    end
    return id
end

--- Converts an `---@assert E` line, which unmasking turned into `local _ = E`.
--- @param st ConvertState
--- @param node LcNode
--- @param gr GhostRange
--- @param top boolean whether it is a top-level statement
--- @mut st
--- @return SrcNode
local function assert_node(st, node, gr, top)
    if st.cursor then
        splice.place(st.cursor, splice.take(st.cursor, assert(node.offset), top, st.marked), 'other', st.marked)
    end
    local values = node[2]
    if #values > 1 then
        st.diags[#st.diags + 1] = diag.at_span('E-syntax', gr.span, { 'one-expression' })
    end
    local cond = expression(st, values[1])
    if st.cursor then
        splice.dangle(st.cursor, assert(node.end_offset), st.marked)
    end
    return { tag = 'ClvAssert', cond = cond }
end

--- Converts the statements of a ghost comment and returns the node for its kind. A `--[[@spec` or
--- `--[[@lemma` block below the top level is reported and makes no node.
--- @param st ConvertState
--- @param item LcItem
--- @param top boolean whether the list is the file's top level
--- @mut st
--- @return NodeId|nil
local function ghost_statement(st, item, top)
    local gr = assert(item.ghost)
    st.consumed[gr] = true
    local declares = gr.kind == 'spec' or gr.kind == 'lemma'
    if declares and not top then
        st.diags[#st.diags + 1] = diag.at_span('E-misplaced-directive', gr.span, { 'not-top-level' })
        return nil
    elseif (gr.kind == 'ghost' or gr.kind == 'assert') and #item.nodes > 1 then
        st.diags[#st.diags + 1] = diag.at_span('E-mode', gr.span, { 'ghost-line' })
    end
    local outer = st.marked
    -- spec functions and lemmas are checked wherever they sit
    if declares and not outer then
        st.marked = true
        st.marks[#st.marks + 1] = { span = gr.span, marked = true }
    end
    st.open[gr] = true
    --- @type SrcNode
    local node
    if gr.kind == 'assert' then
        node = assert_node(st, item.nodes[1], gr, top)
    else
        local statements = {}
        for i, n in ipairs(item.nodes) do
            statements[i] = one_statement(st, n, top)
        end
        if gr.kind == 'spec' then
            node = { tag = 'ClvSpec', statements = statements }
        elseif gr.kind == 'lemma' then
            node = { tag = 'ClvLemma', statements = statements }
        elseif gr.kind == 'ghost' then
            node = { tag = 'ClvGhost', statement = statements[1] }
        else
            node = { tag = 'ClvProof', block = gr.kind == 'proof', statements = statements }
        end
    end
    st.marked = outer
    st.open[gr] = nil
    return add(st, node, gr.span)
end

--- Converts a statement list. At the top level, `regions` tells which statements are marked.
--- @param st ConvertState
--- @param list LcNode[]
--- @param regions SpliceRegion[]|nil
--- @mut st
--- @return NodeId[]
function statement_list(st, list, regions)
    -- LuaJIT, like Lua 5.1, wants `break` to end its block; luacheck doesn't. one of the two may be
    -- ghost code, which LuaJIT never sees
    for i = 2, #list do
        local before = list[i - 1]
        local after = list[i]
        if before.tag == 'Break' then
            local ghost = comments.ghost_at(st.ghosts, assert(before.offset) + st.shift)
            if ghost == comments.ghost_at(st.ghosts, assert(after.offset) + st.shift) then
                reject(st, node_span(st, after), 'break-not-last')
            end
        end
    end

    local ids = {}
    for i, item in ipairs(items(st, list)) do
        if regions then
            st.marked = splice.in_region(regions, i)
        end
        if item.ghost then
            ids[#ids + 1] = ghost_statement(st, item, regions ~= nil)
        else
            if item.split then
                local node = item.nodes[1]
                st.diags[#st.diags + 1] = diag.at_span('E-misplaced-directive', node_span(st, node), { 'ghost-overlap' })
                -- reported here, so not again as ghost code that no statement list takes
                for _, offset in ipairs { assert(node.offset), assert(node.end_offset) } do
                    local gr = ghost_at(st, offset + st.shift)
                    if gr then
                        st.consumed[gr] = true
                    end
                end
            end
            ids[#ids + 1] = one_statement(st, item.nodes[1], regions ~= nil)
        end
    end
    return ids
end

--- Converts a block. Its span covers its statements, or is empty at `empty_at` when it has none.
--- @param st ConvertState
--- @param list LcNode[]
--- @param empty_at integer
--- @mut st
--- @return NodeId
function block(st, list, empty_at)
    local statements = statement_list(st, list)
    local s = span(st, empty_at, empty_at - 1)
    if #statements > 0 then
        s = span(st, st.src.spans[statements[1]].start, st.src.spans[statements[#statements]].finish)
    end
    return add(st, { tag = 'Block', statements = statements }, s)
end

--- Lexes the text again for what the parser drops or reads more loosely than LuaJIT. It returns the long
--- comments and reports:
--- - a Lua 5.4 local attribute such as `local x <const> = 1`: luacheck skips it;
--- - a number that runs into a name such as `3x` or `1or 2`: luacheck reads two tokens.
--- @param st ConvertState
--- @param source LcSource
--- @mut st
--- @return Comment[] long_comments
local function scan_tokens(st, source)
    local long = {}
    local ls = lexer.new_state(source)
    -- in a `local` name list: 'name' when a name comes next, 'after' right after one
    local names = nil
    while true do
        local token, value, line, offset = lexer.next_token(ls)
        if token == nil or token == 'eof' then
            break
        end
        local finish = ls.offset - 1
        if token == 'long_comment' then
            long[#long + 1] = { text = value, span = span(st, offset, finish), line = line }
        elseif token ~= 'short_comment' then
            if token == 'local' then
                names = 'name'
            elseif names == 'name' and token == 'name' then
                names = 'after'
            elseif names == 'after' and token == ',' then
                names = 'name'
            else
                if names == 'after' and token == '<' then
                    reject(st, span(st, offset, finish), 'local-attribute')
                end
                names = nil
            end
            local after = source:get_codepoint(finish + 1)
            if token == 'number' and after and string.char(after):match '[%w_]' then
                reject(st, span(st, offset, finish + 1), 'malformed-number')
            end
        end
    end
    return long
end

--- @param src SrcArena
--- @param file FileId
--- @param shift integer
--- @return ConvertState
local function new_state(src, file, shift)
    return {
        src = src,
        file = file,
        shift = shift,
        diags = {},
        vararg = true,
        loops = 0,
        cursor = nil,
        marked = false,
        marks = {},
        ghosts = {},
        consumed = {},
        open = {},
        exits = {},
    }
end

--- Runs luacheck's parser. Returns its AST, comments and hanging semicolons, or nil and the one syntax
--- error it raised.
--- @param st ConvertState
--- @param source LcSource
--- @return LcNode[]|nil ast
--- @return LcComment[]|Diag comments
--- @return LcNode[]|nil hanging
local function run_parser(st, source)
    local ok, ast, comments_list, _, _, hanging = pcall(parser.parse, source)
    if not ok then
        if type(ast) ~= 'table' then
            error(ast, 0)
        end
        local e = ast --[[@as LcSyntaxError]]
        return nil, diag.at_span('E-syntax', span(st, e.offset, e.end_offset), { e.msg }), nil
    end
    return ast, comments_list, hanging
end

--- Parses and lexes a whole file. Returns what luacheck reads, or nil and the one syntax error its
--- parser raised.
--- @param text string
--- @param file FileId
--- @return LcParse|nil parsed
--- @return Diag|nil err
local function parse_text(text, file)
    local st = new_state(arena.new_src(), file, 0)
    local source = byte_source(text)
    local ast, found, hanging = run_parser(st, source)
    if not ast then
        return nil, found --[[@as Diag]]
    end
    --- @cast found LcComment[]
    --- @cast hanging LcNode[]
    local short = {}
    for i, c in ipairs(found) do
        short[i] = { text = c.contents, span = span(st, c.offset, c.end_offset), line = c.line }
    end
    local long = scan_tokens(st, source)
    -- a `;` at the start of a block or after another `;`: Lua 5.1 has no empty statement
    for _, r in ipairs(hanging) do
        reject(st, node_span(st, r), 'empty-statement')
    end
    return { ast = ast, short = short, long = long, diags = st.diags }, nil
end

--- Returns whether `code` holds any code, not just spaces and comments.
--- @param code string
--- @return boolean
local function has_code(code)
    local ls = lexer.new_state(byte_source(code))
    while true do
        local token = lexer.next_token(ls)
        if token == nil or token == 'eof' then
            return false
        elseif token ~= 'short_comment' and token ~= 'long_comment' then
            return true
        end
    end
end

-- tokens that open and close a block
local OPENS = { ['do'] = true, ['if'] = true, ['function'] = true, ['repeat'] = true }
local CLOSES = { ['end'] = true, ['until'] = true }

--- Returns whether `code` has a `return` outside every block in it.
--- @param code string
--- @return boolean
local function returns_at_top(code)
    local ls = lexer.new_state(byte_source(code))
    local depth = 0
    while true do
        local token = lexer.next_token(ls)
        if token == nil or token == 'eof' then
            return false
        elseif token == 'return' and depth == 0 then
            return true
        elseif OPENS[token] then
            depth = depth + 1
        elseif CLOSES[token] then
            depth = depth - 1
        end
    end
end

--- Returns the key for a ghost comment in exec code that `return` or `break` would leave out of its
--- block, or nil: one right after an exec `return` or `break`, which it would never run after (there
--- is nothing in between), or one with a `return` outside any block of its own, which unmasking would
--- put before the code after it.
--- @param text string the file as written
--- @param exits integer[] the last offset of each exec `return` and `break` statement
--- @param gr GhostRange
--- @return string|nil
local function misplaced_exit(text, exits, gr)
    for _, finish in ipairs(exits) do
        if finish < gr.span.start and not has_code(text:sub(finish + 1, gr.span.start - 1)) then
            return 'ghost-after-exit'
        end
    end
    if gr.kind ~= 'assert' and returns_at_top(text:sub(gr.head + 1, gr.close - 1)) then
        return 'ghost-return'
    end
    return nil
end

--- Converts a parsed file whose ghost comments `ghosts` are unmasked.
--- @param src SrcArena
--- @param text string
--- @param file FileId
--- @param parsed LcParse
--- @param ghosts GhostRange[]
--- @mut src
--- @return Chunk chunk
--- @return Diag[] diags
local function convert_parsed(src, text, file, parsed, ghosts)
    local st = new_state(src, file, 0)
    st.ghosts = ghosts
    local directives = comments.directives(parsed.short)
    -- the statements of one ghost comment count as one, so a region marker can't split them
    local top_spans = {}
    for i, item in ipairs(items(st, parsed.ast)) do
        top_spans[i] = item.ghost and item.ghost.span or node_span(st, item.nodes[1])
    end
    local regions = splice.regions(top_spans, directives, st.diags)
    for _, r in ipairs(regions) do
        st.marks[#st.marks + 1] = { span = r.span, marked = true }
    end
    --- @type CodeParser
    local function code(text_of_code, start)
        return M.expressions(src, file, text_of_code, start)
    end
    st.cursor = splice.cursor(src, text, directives, code, st.diags, ghosts)
    local statements = statement_list(st, parsed.ast, regions)
    splice.finish(st.cursor)
    -- ghost code that no statement list took is inside some exec statement
    for _, gr in ipairs(ghosts) do
        if not st.consumed[gr] and has_code(text:sub(gr.head + 1, gr.close - 1)) then
            st.diags[#st.diags + 1] = diag.at_span('E-misplaced-directive', gr.span, { 'ghost-overlap' })
        end
    end
    for _, d in ipairs(parsed.diags) do
        st.diags[#st.diags + 1] = d
    end
    local chunk = {
        statements = statements,
        comments = parsed.short,
        regions = regions,
        annotations = comments.annotations(parsed.long),
        marks = st.marks,
        ghosts = ghosts,
        exits = st.exits,
    }
    return chunk, st.diags
end

--- Parses `text` and adds its nodes to `src`, with the directives placed and the ghost code unmasked.
--- Returns the converted file and the syntax and placement errors. When luacheck can't parse the text,
--- the result is nil and the one error luacheck raised.
---
--- Spec and lemma blocks are unmasked wherever they sit. Other ghost code is unmasked only in marked
--- code, which is found by converting the text as written first, and is reported anywhere else.
--- @param src SrcArena
--- @param text string
--- @param file FileId
--- @mut src
--- @return Chunk|nil chunk
--- @return Diag[] diags
function M.convert(src, text, file)
    -- parse once to know which ghosts are kept, then parse again with unmasked ghosts
    local parsed, err = parse_text(text, file)
    if not parsed then
        return nil, { assert(err) }
    end
    --- @cast parsed LcParse
    local ghosts = {}
    local dropped = {}
    local diags = {}
    --- @type Chunk|nil
    local written = nil
    for _, gr in ipairs(comments.ghost_ranges(parsed.short, parsed.long, text)) do
        if gr.kind == 'spec' or gr.kind == 'lemma' then
            -- declarations, which need no marked code
            ghosts[#ghosts + 1] = gr
        else
            written = written or convert_parsed(arena.new_src(), text, file, parsed, {})
            if splice.marked_at(written.marks, gr.span.start) then
                local key = misplaced_exit(text, written.exits, gr)
                if key then
                    local code = key == 'ghost-return' and 'E-mode' or 'E-misplaced-directive'
                    diags[#diags + 1] = diag.at_span(code, gr.span, { key })
                    dropped[#dropped + 1] = gr
                else
                    ghosts[#ghosts + 1] = gr
                end
            else
                diags[#diags + 1] = diag.at_span('E-misplaced-directive', gr.span, { 'ghost-outside' })
                dropped[#dropped + 1] = gr
            end
        end
    end
    if #ghosts == 0 and #dropped == 0 then
        return convert_parsed(src, text, file, parsed, {})
    end

    local unmasked = comments.unmask(text, ghosts)
    -- a reported comment is blanked whole, so the rest still parses and splice sees no directive in it
    for _, gr in ipairs(dropped) do
        local s = gr.span
        local blank = (unmasked:sub(s.start, s.finish):gsub('[^\n]', ' '))
        unmasked = unmasked:sub(1, s.start - 1) .. blank .. unmasked:sub(s.finish + 1)
    end
    local reparsed, reparse_err = parse_text(unmasked, file)
    if not reparsed then
        diags[#diags + 1] = assert(reparse_err)
        return nil, diags
    end
    --- @cast reparsed LcParse
    local chunk, more = convert_parsed(src, unmasked, file, reparsed, ghosts)
    for _, d in ipairs(more) do
        diags[#diags + 1] = d
    end
    return chunk, diags
end

--- Parses Lua code that sits at offset `start` of a file, such as the `n > 0` of `---@pre n > 0`, as the
--- values of `return code`, and adds their nodes to `src`. Returns the nodes and the syntax errors. Every
--- long-comment annotation in the code, such as a cast, is reported as unsupported.
--- @param src SrcArena
--- @param file FileId
--- @param code string
--- @param start integer
--- @mut src
--- @return NodeId[] values
--- @return Diag[] diags
function M.expressions(src, file, code, start)
    local prefix = 'return '
    local st = new_state(src, file, start - 1 - #prefix)
    local source = byte_source(prefix .. code)
    local ast, err = run_parser(st, source)
    if not ast then
        return {}, {
            err --[[@as Diag]],
        }
    end
    -- `return` must be the last statement, so it is the only one
    local values = expression_list(st, ast[1])
    for _, a in ipairs(comments.annotations(scan_tokens(st, source))) do
        st.diags[#st.diags + 1] = diag.at_span('E-unsupported-directive', a.span, { a.tag })
    end
    return values, st.diags
end

return M
