-- Reads generic s-expressions. sexpr/write.lua shows the syntax.

local arena = require 'clavius.ir.arena'

--- Why reading failed, and where.
--- @class SexpReadError
--- @field message string
--- @field offset integer byte offset
--- @field line integer
--- @field col integer

--- An open list or vector while reading.
--- @class SexpFrame
--- @field node SexpList|SexpVec
--- @field close string the bracket that ends it

local M = {}

local SIMPLE_ESCAPES = { ['\\'] = '\\', ['"'] = '"', n = '\n', t = '\t', r = '\r' }

--- Makes an error at a byte offset of `text`.
--- @param text string
--- @param offset integer
--- @param message string
--- @return SexpReadError
function M.error_at(text, offset, message)
    local line, col = arena.line_col(text, arena.line_starts(text), offset)
    return { message = message, offset = offset, line = line, col = col }
end

--- Reads a string literal whose opening quote is at `start`.
--- @param text string
--- @param start integer
--- @return string|nil value
--- @return integer|SexpReadError next offset after the closing quote, or the error
local function read_string(text, start)
    local parts = {}
    local i = start + 1
    while true do
        local j = text:find('["\\]', i)
        if not j then
            return nil, M.error_at(text, start, 'unterminated string')
        end
        parts[#parts + 1] = text:sub(i, j - 1)
        if text:sub(j, j) == '"' then
            return table.concat(parts), j + 1
        end
        local c = text:sub(j + 1, j + 1)
        if SIMPLE_ESCAPES[c] then
            parts[#parts + 1] = SIMPLE_ESCAPES[c]
            i = j + 2
        else
            local digits = text:match('^%d%d?%d?', j + 1)
            local code = digits and tonumber(digits)
            if not code or code > 255 then
                return nil, M.error_at(text, j, 'bad escape in string')
            end
            parts[#parts + 1] = string.char(code)
            i = j + 1 + #digits
        end
    end
end

--- Reads every s-expression in `text`. Returns the first error instead if `text` is malformed.
--- @param text string
--- @return Sexp[]|nil values
--- @return SexpReadError|nil err
function M.read_all(text)
    local top = {}
    --- @type SexpFrame[]
    local stack = {}
    local i = 1
    local n = #text

    --- @param x Sexp
    local function push(x)
        local frame = stack[#stack]
        if frame then
            frame.node.items[#frame.node.items + 1] = x
        else
            top[#top + 1] = x
        end
    end

    while i <= n do
        local c = text:sub(i, i)
        if c:find '%s' then
            i = (text:find('[^%s]', i) or n + 1)
        elseif c == ';' then
            i = (text:find('\n', i, true) or n) + 1
        elseif c == '(' then
            stack[#stack + 1] = { node = { tag = 'List', items = {}, start = i }, close = ')' }
            i = i + 1
        elseif c == '[' then
            stack[#stack + 1] = { node = { tag = 'Vec', items = {}, start = i }, close = ']' }
            i = i + 1
        elseif c == ')' or c == ']' then
            local frame = stack[#stack]
            if not frame then
                return nil, M.error_at(text, i, ('unexpected %s'):format(c))
            end
            if frame.close ~= c then
                return nil, M.error_at(text, i, ('expected %s, found %s'):format(frame.close, c))
            end
            stack[#stack] = nil
            frame.node.finish = i
            push(frame.node)
            i = i + 1
        elseif c == '"' then
            local value, after = read_string(text, i)
            if not value then
                --- @cast after SexpReadError
                return nil, after
            end
            --- @cast after integer
            push { tag = 'Str', text = value, start = i }
            i = after
        else
            local j = (text:find('[%s%(%)%[%]";]', i) or n + 1)
            push { tag = 'Sym', text = text:sub(i, j - 1), start = i }
            i = j
        end
    end
    if #stack > 0 then
        local frame = stack[#stack]
        return nil, M.error_at(text, frame.node.start or 1, ('unclosed %s'):format(frame.node.tag == 'List' and '(' or '['))
    end
    return top, nil
end

--- Formats a read error as `line:col: message`.
--- @param err SexpReadError
--- @return string
function M.format_error(err)
    return ('%d:%d: %s'):format(err.line, err.col, err.message)
end

return M
