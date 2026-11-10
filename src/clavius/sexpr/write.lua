-- Generic s-expressions: their types, constructors, and the writer. For example:
--
--   ; a comment, to the end of the line
--   (Local
--     [(Binder y$2 :type int53)]
--     [(Call print "hello" 1LL #17)])

--- @class SexpList
--- @field tag 'List'
--- @field items Sexp[]
--- @field start integer|nil offset of `(` in the text it was read from

--- @class SexpVec
--- @field tag 'Vec'
--- @field items Sexp[]
--- @field start integer|nil offset of `[` in the text it was read from

--- @class SexpSym
--- @field tag 'Sym'
--- @field text string
--- @field start integer|nil

--- @class SexpStr
--- @field tag 'Str'
--- @field text string the decoded bytes
--- @field start integer|nil offset of the opening quote

--- @alias Sexp SexpList | SexpVec | SexpSym | SexpStr

--- @class SexpWriteOptions
--- @field width integer|nil lines longer than this are broken (default 100)

local M = {}

M.DEFAULT_WIDTH = 100

--- @param items Sexp[]
--- @return SexpList
function M.list(items)
    return { tag = 'List', items = items }
end

--- @param items Sexp[]
--- @return SexpVec
function M.vec(items)
    return { tag = 'Vec', items = items }
end

--- @param text string
--- @return SexpSym
function M.sym(text)
    return { tag = 'Sym', text = text }
end

--- @param text string
--- @return SexpStr
function M.str(text)
    return { tag = 'Str', text = text }
end

--- Returns whether `text` can be written as a symbol: non-empty, with no whitespace, brackets, quotes or `;`.
--- @param text string
--- @return boolean
function M.is_symbol_text(text)
    return text ~= '' and not text:find '[%s%(%)%[%]";]'
end

-- other control bytes become `\ddd` (decimal, as in Lua); bytes from 128 up stay raw
local ESCAPES = { ['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r' }

--- Writes `text` as a string literal.
--- @param text string
--- @return string
function M.quote(text)
    --- @param c string
    --- @return string
    local function escape(c)
        return ESCAPES[c] or ('\\%03d'):format(c:byte())
    end
    return ('"%s"'):format((text:gsub('[%c\\"]', escape)))
end

--- @param x Sexp
--- @return boolean
local function is_atom(x)
    return x.tag == 'Sym' or x.tag == 'Str'
end

--- Returns an atom as it is written: a symbol's text, or a quoted string. Raises an error if a symbol's
--- text isn't valid symbol text.
--- @param x SexpSym|SexpStr
--- @return string
local function atom_text(x)
    if x.tag == 'Str' then
        return M.quote(x.text)
    end
    if not M.is_symbol_text(x.text) then
        error(('sexpr.write: %q is not a valid symbol'):format(x.text))
    end
    return x.text
end

--- @param x SexpList|SexpVec
--- @return string open
--- @return string close
local function brackets(x)
    if x.tag == 'List' then
        return '(', ')'
    end
    return '[', ']'
end

--- Writes `x` on one line.
--- @param x Sexp
--- @return string
function M.flat(x)
    if x.tag == 'Sym' or x.tag == 'Str' then
        return atom_text(x)
    end
    local parts = {}
    for i, item in ipairs(x.items) do
        parts[i] = M.flat(item)
    end
    local open, close = brackets(x)
    return open .. table.concat(parts, ' ') .. close
end

--- Splits a list's items into lines: the leading atoms form the head, and each later item is its own
--- line, except that a `:keyword` symbol stays on the line of the item after it. For example,
--- `(BinOp add (Id x$1) (Literal number 1) :type int53)` gives:
---
---   head  BinOp add
---   rest  (Id x$1)
---         (Literal number 1)
---         :type int53
--- @param items Sexp[]
--- @return Sexp[] head
--- @return Sexp[][] rest
local function group(items)
    local head = {}
    local i = 1
    while i <= #items and is_atom(items[i]) and not (items[i].tag == 'Sym' and items[i].text:sub(1, 1) == ':') do
        head[#head + 1] = items[i]
        i = i + 1
    end
    local rest = {}
    while i <= #items do
        local line = { items[i] }
        if items[i].tag == 'Sym' and items[i].text:sub(1, 1) == ':' and i < #items then
            line[2] = items[i + 1]
            i = i + 1
        end
        rest[#rest + 1] = line
        i = i + 1
    end
    return head, rest
end

--- Appends the lines for `x`, whose first line starts at column `col` and is followed by `trail`
--- closing brackets.
---
--- If `x` and those brackets fit in `width`, it is written flat. Otherwise the head from `group` stays
--- on the first line and each later line is indented two past the open bracket. With no head, the
--- first item follows the bracket and the indent is one. For example, at width 60:
---
---   (Local
---     [(Binder y$2 :type int53)]
---     [(BinOp add
---        (Id x$1 :type int53)
---        (Literal number 1 :type int53)
---        :type int53)]
---     :rec false)
---
--- The first vector fits flat at column 2. The second would need 79 columns. Its first item is a list,
--- so it has no head and `(BinOp` follows the `[`. BinOp's head is `BinOp add`.
--- @param x Sexp
--- @param col integer
--- @param trail integer
--- @param width integer
--- @param out string[] lines; the last one is being extended
--- @mut out
local function render(x, col, trail, width, out)
    -- flat if `x` and the `trail` closers after it fit; atoms are always flat, even when too long
    local f = M.flat(x)
    if x.tag == 'Sym' or x.tag == 'Str' or col + #f + trail <= width then
        out[#out] = out[#out] .. f
        return
    end

    local open, close = brackets(x)
    local head, rest = group(x.items)
    local first = {}
    for i, a in ipairs(head) do
        first[i] = M.flat(a)
    end
    out[#out] = out[#out] .. open .. table.concat(first, ' ')
    -- later lines start two past the open bracket, or one when there's no head
    local inner = col + (#head > 0 and 2 or 1)
    for li, line in ipairs(rest) do
        -- with no head, the first item goes right after the bracket
        if li > 1 or #head > 0 then
            out[#out + 1] = (' '):rep(inner)
        end
        local last_line = li == #rest
        for j, item in ipairs(line) do
            if j > 1 then
                out[#out] = out[#out] .. ' '
            end
            -- only the last item has closers after it: the parent's `trail` plus the parent's own close
            -- bracket. e.g. `int53` after `:type` in the example: col 11, trail 2 for `)]`, 11 + 5 + 2 <= 60
            local t = (last_line and j == #line) and trail + 1 or 0
            -- the item starts where the line ends so far
            render(item, #out[#out], t, width, out)
        end
    end
    out[#out] = out[#out] .. close
end

--- Writes one s-expression, breaking lines wider than `opts.width`. The result has no final newline.
--- @param x Sexp
--- @param opts SexpWriteOptions|nil
--- @return string
function M.write_one(x, opts)
    local width = (opts and opts.width) or M.DEFAULT_WIDTH
    local out = { '' }
    -- the top level starts at column 0 with no closers after it
    render(x, 0, 0, width, out)
    return table.concat(out, '\n')
end

--- Writes several s-expressions, one after another, each ending with a newline.
--- @param xs Sexp[]
--- @param opts SexpWriteOptions|nil
--- @return string
function M.write_all(xs, opts)
    local parts = {}
    for i, x in ipairs(xs) do
        parts[i] = M.write_one(x, opts) .. '\n'
    end
    return table.concat(parts)
end

return M
