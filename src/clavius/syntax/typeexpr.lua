-- LuaLS type expressions as source nodes, and the tokens of annotation text that they are read from.
-- For example `Seq<int53>`, `'circle' | 'rect'`, `fun(a: integer): boolean` or `{ x: integer }`.
--
-- source: LuaLS 3.19.2's script/parser/luadoc.lua (https://github.com/LuaLS/lua-language-server)

local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'

--- One line of annotation text and the file offset of its first byte.
--- @class DocLine
--- @field text string
--- @field start integer

--- A token of annotation text, split as LuaLS splits it. A name may hold `.`, `*` and `-`, as in
--- `a.b`. A string's text is its value.
--- @class DocToken
--- @field kind 'name' | 'integer' | 'string' | 'code' | 'symbol'
--- @field text string
--- @field start integer
--- @field finish integer

--- Reads the tokens of a directive's line, and of the lines below it that a type continues onto.
--- @class DocLexer
--- @field file FileId
--- @field lines DocLine[]
--- @field line integer the line being read
--- @field tokens DocToken[] its tokens
--- @field pos integer the next token
--- @field used integer the last line read: moved to, or taken for its `|` member

--- A grammar error. It is raised with `error` and caught where a directive is parsed.
--- @class DocError
--- @field diag Diag

local M = {}

-- the bytes that start a symbol; `...` and `[]` are symbols too
local SYMBOLS = ':|,;<>()?+#{}*[].-'

local ESCAPES = { a = '\a', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', v = '\v' }

--- Returns the value of the quoted string that starts at `i`, and the index of its closing quote, or
--- nil when the line ends first.
--- @param s string
--- @param i integer
--- @return string|nil value
--- @return integer|nil close
local function quoted(s, i)
    local quote = s:sub(i, i)
    local out = {}
    local j = i + 1
    while j <= #s do
        local c = s:sub(j, j)
        if c == quote then
            return table.concat(out), j
        elseif c == '\\' then
            local e = s:sub(j + 1, j + 1)
            local digits = s:match('^%d%d?%d?', j + 1)
            local code = digits and tonumber(digits) --[[@as integer|nil]]
            if ESCAPES[e] then
                out[#out + 1], j = ESCAPES[e], j + 2
            elseif code and code <= 255 then
                out[#out + 1], j = string.char(code), j + 1 + #digits
            elseif e == '\\' or e == '"' or e == "'" then
                out[#out + 1], j = e, j + 2
            else
                -- LuaLS keeps an unknown escape as it is
                out[#out + 1], j = c, j + 1
            end
        else
            out[#out + 1], j = c, j + 1
        end
    end
    return nil, nil
end

--- Splits a line into tokens. Tokens stop at the first byte that starts none, such as the `--` of a
--- comment.
--- @param line DocLine
--- @return DocToken[]
local function tokenize(line)
    local s = line.text
    local tokens = {}
    --- @param kind 'name' | 'integer' | 'string' | 'code' | 'symbol'
    --- @param text string
    --- @param i integer
    --- @param j integer
    local function push(kind, text, i, j)
        tokens[#tokens + 1] = { kind = kind, text = text, start = line.start + i - 1, finish = line.start + j - 1 }
    end
    local i = s:find '%S'
    while i do
        local c = s:sub(i, i)
        local int = s:match('^%-?%d+', i)
        local name = s:match('^[%w_\128-\255][%w_\128-\255%.%*%-]*', i)
        local level = s:match('^%[(=*)%[', i)
        local j
        if int and s:sub(i + #int, i + #int) ~= '.' then
            push('integer', int, i, i + #int - 1)
            j = i + #int
        elseif name then
            push('name', name, i, i + #name - 1)
            j = i + #name
        elseif c == '"' or c == "'" then
            local value, close = quoted(s, i)
            if not value or not close then
                break
            end
            push('string', value, i, close)
            j = close + 1
        elseif level then
            local close_start, close_finish = s:find(']' .. level .. ']', i + #level + 2, true)
            if not close_start or not close_finish then
                break
            end
            push('string', s:sub(i + #level + 2, close_start - 1), i, close_finish)
            j = close_finish + 1
        elseif c == '`' then
            local close = s:find('`', i + 1, true)
            if not close then
                break
            end
            push('code', s:sub(i + 1, close - 1), i, close)
            j = close + 1
        else
            -- `--` starts a comment
            if not SYMBOLS:find(c, 1, true) or s:sub(i, i + 1) == '--' then
                break
            end
            local sym = s:sub(i, i + 2) == '...' and '...' or s:sub(i, i + 1) == '[]' and '[]' or c
            push('symbol', sym, i, i + #sym - 1)
            j = i + #sym
        end
        i = s:find('%S', j)
    end
    return tokens
end

--- Makes a lexer over the given lines. The first is the text after a tag, and the rest are lines a type
--- may continue onto.
--- @param file FileId
--- @param lines DocLine[]
--- @return DocLexer
function M.lexer(file, lines)
    return { file = file, lines = lines, line = 1, tokens = tokenize(lines[1]), pos = 1, used = 1 }
end

--- Returns the `k`-th token ahead, by default the next one, without taking it.
--- @param lx DocLexer
--- @param k integer|nil
--- @return DocToken|nil
function M.peek(lx, k)
    return lx.tokens[lx.pos + (k or 1) - 1]
end

--- Takes the next token.
--- @param lx DocLexer
--- @mut lx
--- @return DocToken|nil
function M.next(lx)
    local t = lx.tokens[lx.pos]
    if t then
        lx.pos = lx.pos + 1
    end
    return t
end

--- Takes the next token if it is the symbol `text`.
--- @param lx DocLexer
--- @param text string
--- @mut lx
--- @return DocToken|nil
function M.symbol(lx, text)
    local t = lx.tokens[lx.pos]
    if t and t.kind == 'symbol' and t.text == text then
        lx.pos = lx.pos + 1
        return t
    end
    return nil
end

--- Returns the file offset of the last byte read on the current line.
--- @param lx DocLexer
--- @return integer
local function last_finish(lx)
    if lx.pos > 1 then
        return lx.tokens[lx.pos - 1].finish
    end
    return lx.lines[lx.line].start - 1
end

--- Raises a grammar error at `tok`, or at the next token, or where the text after the last token
--- starts.
--- @param lx DocLexer
--- @param key string the error's argument
--- @param tok DocToken|nil
function M.fail(lx, key, tok)
    local t = tok or M.peek(lx)
    local s
    if t then
        s = arena.span(lx.file, t.start, t.finish)
    else
        local line = lx.lines[lx.line]
        local at = line.start - 1 + (line.text:find('%S', last_finish(lx) - line.start + 2) or #line.text + 1)
        s = arena.span(lx.file, at, at - 1)
    end
    --- @type DocError
    local e = { diag = diag.at_span('E-syntax', s, { key }) }
    error(e, 0)
end

--- Takes the symbol `text`, or raises an `expected-<text>` error.
--- @param lx DocLexer
--- @param text string
--- @mut lx
--- @return DocToken
function M.expect(lx, text)
    local t = M.symbol(lx, text)
    if not t then
        M.fail(lx, 'expected-' .. text)
    end
    return t --[[@as DocToken]]
end

--- Returns whether nothing but spaces follows the last token taken on the current line.
--- @param lx DocLexer
--- @return boolean
function M.at_end(lx)
    local line = lx.lines[lx.line]
    return line.text:find('^%s*$', last_finish(lx) - line.start + 2) ~= nil
end

--- Moves to the next unread line when the current one has no tokens left. LuaLS does this inside
--- brackets, so a table or function type can span lines.
--- @param lx DocLexer
--- @mut lx
function M.slide(lx)
    if lx.pos <= #lx.tokens or lx.used >= #lx.lines then
        return
    end
    lx.used = lx.used + 1
    lx.line = lx.used
    lx.tokens = tokenize(lx.lines[lx.line])
    lx.pos = 1
end

local parse_type -- forward

--- Adds a node spanning `start` to `finish`.
--- @param src SrcArena
--- @param lx DocLexer
--- @param node SrcNode
--- @param start integer
--- @param finish integer
--- @mut src
--- @return NodeId
local function add(src, lx, node, start, finish)
    return arena.add_src(src, node, arena.span(lx.file, start, finish))
end

--- Parses the `<T, U>` after `fun`, a class name or an alias name into ClvTypeGeneric nodes.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId[]
function M.generics(src, lx)
    local out = {}
    M.expect(lx, '<')
    repeat
        local t = M.next(lx)
        if not t or t.kind ~= 'name' then
            M.fail(lx, 'expected-name', t)
        end
        --- @cast t DocToken
        out[#out + 1] = add(src, lx, { tag = 'ClvTypeGeneric', name = t.text }, t.start, t.finish)
    until not M.symbol(lx, ',')
    M.expect(lx, '>')
    return out
end

--- Parses `fun(a: A, b?: B, ...: C): R1, R2`. Generics may follow `fun`, and `async` may come before
--- it.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
local function fun_type(src, lx)
    local first = M.next(lx) --[[@as DocToken]]
    local async = first.text == 'async'
    if async then
        M.next(lx)
    end
    local generics = {}
    if M.peek(lx) and M.peek(lx).text == '<' then
        generics = M.generics(src, lx)
    end
    M.expect(lx, '(')
    local params = {}
    while true do
        M.slide(lx)
        if M.symbol(lx, ')') then
            break
        end
        local t = M.next(lx)
        if not t or not (t.kind == 'name' or t.text == '...') then
            M.fail(lx, 'expected-name', t)
        end
        --- @cast t DocToken
        local optional = M.symbol(lx, '?') ~= nil
        local ty = nil
        if M.symbol(lx, ':') then
            ty = parse_type(src, lx, false)
        end
        params[#params + 1] = add(src, lx, { tag = 'ClvTypeParam', name = t.text, optional = optional, type = ty }, t.start, last_finish(lx))
        if not M.symbol(lx, ',') then
            M.expect(lx, ')')
            break
        end
    end
    M.slide(lx)
    local returns = {}
    if M.symbol(lx, ':') then
        M.slide(lx)
        local paren = M.symbol(lx, '(')
        repeat
            M.slide(lx)
            local start = M.peek(lx) and M.peek(lx).start or last_finish(lx) + 1
            local name = nil
            local after = M.peek(lx, 2)
            if after and after.text == ':' and after.kind == 'symbol' then
                local t = M.peek(lx) --[[@as DocToken]]
                if t.kind == 'name' or t.text == '...' then
                    name = t.text
                    M.next(lx)
                    M.next(lx)
                end
            end
            local ty = parse_type(src, lx, false)
            returns[#returns + 1] = add(src, lx, { tag = 'ClvTypeReturn', name = name, type = ty }, start, last_finish(lx))
        until not M.symbol(lx, ',')
        if paren then
            M.expect(lx, ')')
        end
    end
    local node = { tag = 'ClvTypeFun', async = async, generics = generics, params = params, returns = returns }
    return add(src, lx, node, first.start, last_finish(lx))
end

--- Parses a table type `{ x: T, y?: U, [K]: V }`. A field may be wrapped in parentheses.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
local function table_type(src, lx)
    local open = M.next(lx) --[[@as DocToken]]
    local fields = {}
    while true do
        M.slide(lx)
        if M.symbol(lx, '}') then
            break
        end
        local start = M.peek(lx) and M.peek(lx).start or last_finish(lx) + 1
        local paren = M.symbol(lx, '(')
        local name, key = nil, nil
        local t = M.peek(lx)
        if t and t.kind == 'name' then
            M.next(lx)
            name = t.text
        elseif M.symbol(lx, '[') then
            key = parse_type(src, lx, false)
            M.expect(lx, ']')
        else
            M.fail(lx, 'expected-name')
        end
        local optional = M.symbol(lx, '?') ~= nil
        M.expect(lx, ':')
        local ty = parse_type(src, lx, false)
        if paren then
            M.expect(lx, ')')
        end
        local field = { tag = 'ClvTypeField', key = key, name = name, optional = optional, type = ty }
        fields[#fields + 1] = add(src, lx, field, start, last_finish(lx))
        if not (M.symbol(lx, ',') or M.symbol(lx, ';')) then
            M.expect(lx, '}')
            break
        end
    end
    return add(src, lx, { tag = 'ClvTypeTable', fields = fields }, open.start, last_finish(lx))
end

--- Parses a tuple type `[A, B]`.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
local function tuple_type(src, lx)
    local open = M.next(lx) --[[@as DocToken]]
    local items = {}
    while true do
        M.slide(lx)
        if M.symbol(lx, ']') then
            break
        end
        items[#items + 1] = parse_type(src, lx, false)
        if not (M.symbol(lx, ',') or M.symbol(lx, ';')) then
            M.expect(lx, ']')
            break
        end
    end
    return add(src, lx, { tag = 'ClvTypeTuple', items = items }, open.start, last_finish(lx))
end

--- Parses a backtick type with the names that touch it, such as `` `T` `` or `` Foo.`T` ``. Returns
--- nil and takes nothing when the touching tokens hold no backtick type.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId|nil
local function code_type(src, lx)
    local parts, code, count = {}, nil, 0
    local prev = nil
    while true do
        local t = M.peek(lx, count + 1)
        if not t or (prev and t.start ~= prev.finish + 1) then
            break
        end
        if t.kind == 'code' and not code then
            code = t.text
            parts[#parts + 1] = '%s'
        elseif t.kind == 'name' or (code and (t.kind == 'integer' or (t.kind == 'symbol' and (t.text == '.' or t.text == '*' or t.text == '-')))) then
            parts[#parts + 1] = t.text
        else
            break
        end
        prev, count = t, count + 1
    end
    if not code then
        return nil
    end
    local first = M.peek(lx) --[[@as DocToken]]
    for _ = 1, count do
        M.next(lx)
    end
    local pattern = count > 1 and table.concat(parts) or nil
    return add(src, lx, { tag = 'ClvTypeCode', text = code, pattern = pattern }, first.start, last_finish(lx))
end

--- Parses one member of a union: a name, literal, function, table, tuple, backtick or parenthesized
--- type. Any `<args>` and then any `[]` may follow it.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
function M.unit(src, lx)
    local t = M.peek(lx)
    if not t then
        M.fail(lx, 'expected-type')
    end
    --- @cast t DocToken
    local after = M.peek(lx, 2)
    local id
    if t.kind == 'name' and (t.text == 'fun' or (t.text == 'async' and after and after.kind == 'name' and after.text == 'fun')) then
        id = fun_type(src, lx)
    elseif t.kind == 'symbol' and t.text == '{' then
        id = table_type(src, lx)
    elseif t.kind == 'symbol' and t.text == '[' then
        id = tuple_type(src, lx)
    elseif t.kind == 'string' or t.kind == 'integer' or (t.kind == 'name' and (t.text == 'true' or t.text == 'false')) then
        M.next(lx)
        --- @type 'string' | 'integer' | 'boolean'
        local kind = 'boolean'
        local text = t.text
        local q = text:sub(1, 1)
        if t.kind == 'integer' then
            kind = 'integer'
        elseif t.kind == 'string' then
            kind = 'string'
            if #text > 1 and (q == '"' or q == "'") and text:sub(-1) == q then
                -- old LuaLS spelling of a literal: `'"r"'` is the string `r`
                text = text:sub(2, -2)
            end
        end
        id = add(src, lx, { tag = 'ClvTypeLiteral', kind = kind, text = text }, t.start, t.finish)
    elseif t.kind == 'symbol' and t.text == '(' then
        M.next(lx)
        id = parse_type(src, lx, false)
        M.expect(lx, ')')
    else
        id = code_type(src, lx)
        if not id then
            if t.kind ~= 'name' and t.text ~= '...' then
                M.fail(lx, 'expected-type')
            end
            M.next(lx)
            id = add(src, lx, { tag = 'ClvTypeName', name = t.text }, t.start, t.finish)
        end
    end
    while M.peek(lx) and M.peek(lx).kind == 'symbol' and M.peek(lx).text == '<' do
        M.next(lx)
        local args = {}
        repeat
            args[#args + 1] = parse_type(src, lx, false)
        until not M.symbol(lx, ',')
        M.expect(lx, '>')
        id = add(src, lx, { tag = 'ClvTypeApply', base = id, args = args }, t.start, last_finish(lx))
    end
    while M.symbol(lx, '[]') do
        id = add(src, lx, { tag = 'ClvTypeArray', elem = id }, t.start, last_finish(lx))
    end
    return id
end

--- Adds the members of the `---| T` lines below to `members`. Other `---` lines between them are
--- descriptions.
--- @param src SrcArena
--- @param lx DocLexer
--- @param members NodeId[]
--- @mut src
--- @mut lx
--- @mut members
local function continued_members(src, lx, members)
    for i = lx.used + 1, #lx.lines do
        local line = lx.lines[i]
        local after = line.text:match '^%s*|()'
        if after then
            local member = M.lexer(lx.file, { { text = line.text:sub(after), start = line.start + after - 1 } })
            -- `>` marks the default value and `+` an added one; neither changes the type
            M.symbol(member, '>')
            M.symbol(member, '+')
            members[#members + 1] = M.unit(src, member)
            lx.used = i
        end
    end
end

--- Parses `A | B | …`, then an optional `?` for the whole union. At the top of a directive, a type
--- that isn't followed by `,` continues with the members of the `---|` lines below, and it may consist
--- of them only.
--- @param src SrcArena
--- @param lx DocLexer
--- @param top boolean
--- @mut src
--- @mut lx
--- @return NodeId
function parse_type(src, lx, top)
    local members = {}
    if M.peek(lx) or not top then
        repeat
            members[#members + 1] = M.unit(src, lx)
        until not M.symbol(lx, '|')
    end
    local optional = M.symbol(lx, '?')
    if top and not (M.peek(lx) and M.peek(lx).text == ',') then
        continued_members(src, lx, members)
    end
    if #members == 0 then
        M.fail(lx, 'expected-type')
    end
    local id = members[1]
    local start = src.spans[id].start
    local finish = src.spans[members[#members]].finish
    if #members > 1 then
        id = add(src, lx, { tag = 'ClvTypeUnion', members = members }, start, finish)
    end
    if optional then
        id = add(src, lx, { tag = 'ClvTypeOptional', inner = id }, start, math.max(finish, optional.finish))
    end
    return id
end

--- Parses a type at the top of a directive, with its `---|` lines.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
function M.parse(src, lx)
    return parse_type(src, lx, true)
end

--- Parses a type nested in a directive's arguments, such as a generic's bound.
--- @param src SrcArena
--- @param lx DocLexer
--- @mut src
--- @mut lx
--- @return NodeId
function M.parse_inner(src, lx)
    return parse_type(src, lx, false)
end

return M
