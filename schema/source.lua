-- Source node types: Lua nodes and Clavius source nodes, whose tags start with `Clv`. `schema/gen.lua` turns
-- this into src/clavius/ir/source_nodes.lua and src/clavius/sexpr/schema.lua.
--
-- Each field is { name, type, doc }. The type is `node`, `node?`, `node[]`, or an atom: `string`,
-- `string?`, `integer`, `boolean`, or a union of string literals. Fields are listed in evaluation order.

local BINOPS = "'add' | 'sub' | 'mul' | 'div' | 'mod' | 'pow' | 'concat' | 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge' | 'and' | 'or'"

--- @type NodeType[]
return {
    {
        tag = 'Block',
        doc = 'A statement list with its own scope: a `do … end` or the body of a construct.',
        fields = { { 'statements', 'node[]' } },
    },
    {
        tag = 'ClvRegion',
        doc = 'The statements between `---@clavius begin` and `---@clavius end`. It is not a scope.',
        fields = { { 'statements', 'node[]' } },
    },
    {
        tag = 'Local',
        doc = '`local names = values`. The values come first, because they are evaluated before the names are bound.',
        fields = { { 'values', 'node[]' }, { 'names', 'node[]', 'Binder nodes' } },
    },
    {
        tag = 'LocalFunction',
        doc = '`local function binder … end`. The binder comes first, so the function can call itself.',
        fields = { { 'binder', 'node' }, { 'func', 'node', 'a Function node' } },
    },
    {
        tag = 'Set',
        doc = '`targets = values`. Targets are Id and Index nodes.',
        fields = { { 'targets', 'node[]' }, { 'values', 'node[]' } },
    },
    {
        tag = 'Call',
        doc = '`func(args)`, or `func:method(args)` when `method` is set.',
        fields = { { 'func', 'node' }, { 'method', 'string?' }, { 'args', 'node[]' } },
    },
    {
        tag = 'If',
        doc = '`if` with its `elseif` arms.',
        fields = { { 'arms', 'node[]', 'IfArm nodes, one per `if` and `elseif`' }, { 'else_block', 'node?' } },
    },
    { tag = 'IfArm', doc = 'One condition and its body.', fields = { { 'cond', 'node' }, { 'body', 'node' } } },
    { tag = 'While', fields = { { 'cond', 'node' }, { 'body', 'node' } } },
    {
        tag = 'Repeat',
        doc = '`repeat body until cond`. The condition sees the locals of the body.',
        fields = { { 'body', 'node' }, { 'cond', 'node' } },
    },
    {
        tag = 'Fornum',
        doc = '`for var = start, limit, step do body end`.',
        fields = { { 'start', 'node' }, { 'limit', 'node' }, { 'step', 'node?' }, { 'var', 'node', 'a Binder node' }, { 'body', 'node' } },
    },
    {
        tag = 'Forin',
        doc = '`for names in iters do body end`.',
        fields = { { 'iters', 'node[]' }, { 'names', 'node[]', 'Binder nodes' }, { 'body', 'node' } },
    },
    { tag = 'Return', fields = { { 'values', 'node[]' } } },
    { tag = 'Break', fields = {} },
    { tag = 'Goto', fields = { { 'label', 'string' } } },
    { tag = 'Label', fields = { { 'name', 'string' } } },
    { tag = 'Binder', doc = 'A name in a binding position.', fields = { { 'name', 'string' } } },
    { tag = 'Id', doc = 'A name that is read or assigned.', fields = { { 'name', 'string' } } },
    {
        tag = 'Literal',
        doc = 'A literal value.',
        fields = {
            { 'kind', "'nil' | 'true' | 'false' | 'number' | 'string'" },
            { 'text', 'string', "a number's source spelling such as '1LL', a string's value, or the keyword" },
        },
    },
    { tag = 'Dots', doc = '`...`.', fields = {} },
    {
        tag = 'Function',
        doc = 'A function body. A method defined with `:` has an explicit `self` parameter.',
        fields = { { 'params', 'node[]', 'Binder nodes' }, { 'vararg', 'boolean', 'whether `...` ends the parameters' }, { 'body', 'node' } },
    },
    { tag = 'Table', doc = 'A table constructor.', fields = { { 'fields', 'node[]', 'TableField nodes' } } },
    {
        tag = 'TableField',
        doc = 'One item of a table constructor. A positional item has no key.',
        fields = { { 'key', 'node?' }, { 'value', 'node' } },
    },
    { tag = 'Index', doc = '`obj[key]`, and `obj.name` with a string key.', fields = { { 'obj', 'node' }, { 'key', 'node' } } },
    { tag = 'BinOp', fields = { { 'op', BINOPS }, { 'lhs', 'node' }, { 'rhs', 'node' } } },
    { tag = 'UnOp', fields = { { 'op', "'not' | 'unm' | 'len'" }, { 'arg', 'node' } } },
    { tag = 'Paren', doc = 'A parenthesized expression. It truncates a call to one value.', fields = { { 'expr', 'node' } } },
}
