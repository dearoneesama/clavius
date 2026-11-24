-- Source node types: Lua nodes and Clavius source nodes, whose tags start with `Clv`. `schema/gen.lua` turns
-- this into src/clavius/ir/source_nodes.lua and src/clavius/sexpr/schema.lua.
--
-- Each field is { name, type, doc }. The type is `node`, `node?`, `node[]`, or an atom: `string`,
-- `string?`, `integer`, `boolean`, or a union of string literals. Fields are listed in evaluation order.
-- `DOC` becomes the header comment of the node module.

local BINOPS = "'add' | 'sub' | 'mul' | 'div' | 'mod' | 'pow' | 'concat' | 'eq' | 'ne' | 'lt' | 'le' | 'gt' | 'ge' | 'and' | 'or'"

local DOC = [[
A statement node is a Local, LocalFunction, Set, Call, Block, If, While, Repeat, Fornum, Forin,
  Return, Break, Goto, Label, ClvSpec, ClvLemma, ClvProof, ClvGhost, ClvAssert or ClvAssume node.
An expression node is an Id, Literal, Dots, Function, Table, Index, Call, BinOp, UnOp or Paren node.
A type node is a `ClvType*` node that stands for a whole type, such as ClvTypeName or ClvTypeUnion.
A directive is a node made from a ---@ annotation, such as ClvPre.]]

--- @type NodeType[]
local NODES = {
    {
        tag = 'Block',
        doc = 'A statement list with its own scope: a `do … end` or the body of a construct.',
        fields = { { 'statements', 'node[]', 'statement nodes; the root also holds ClvRegion nodes' } },
    },
    {
        tag = 'ClvRegion',
        doc = 'The statements between `---@clavius begin` and `---@clavius end`, and the directives right above its `begin`. It is not a scope.',
        fields = { { 'directives', 'node[]', 'ClvProofBy nodes' }, { 'statements', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'Local',
        doc = '`local names = values`. The values come first, because they are evaluated before the names are bound.',
        fields = { { 'values', 'node[]', 'expression nodes' }, { 'names', 'node[]', 'Binder nodes' } },
    },
    {
        tag = 'LocalFunction',
        doc = '`local function binder … end`. The binder comes first, so the function can call itself.',
        fields = { { 'binder', 'node', 'a Binder node' }, { 'func', 'node', 'a Function node' } },
    },
    {
        tag = 'Set',
        doc = '`targets = values`.',
        fields = { { 'targets', 'node[]', 'Id and Index nodes' }, { 'values', 'node[]', 'expression nodes' } },
    },
    {
        tag = 'Call',
        doc = '`func(args)`, or `func:method(args)` when `method` is set.',
        fields = { { 'func', 'node', 'an expression node' }, { 'method', 'string?' }, { 'args', 'node[]', 'expression nodes' } },
    },
    {
        tag = 'If',
        doc = '`if` with its `elseif` arms.',
        fields = { { 'arms', 'node[]', 'IfArm nodes, one per `if` and `elseif`' }, { 'else_block', 'node?', 'a Block node' } },
    },
    { tag = 'IfArm', doc = 'One condition and its body.', fields = { { 'cond', 'node', 'an expression node' }, { 'body', 'node', 'a Block node' } } },
    {
        tag = 'While',
        doc = '`while cond do body end`.',
        fields = {
            { 'directives', 'node[]', 'the ClvInvariant and ClvDecrease directives above it' },
            { 'cond', 'node', 'an expression node' },
            { 'body', 'node', 'a Block node' },
        },
    },
    {
        tag = 'Repeat',
        doc = '`repeat body until cond`. The condition sees the locals of the body.',
        fields = {
            { 'directives', 'node[]', 'the ClvInvariant and ClvDecrease directives above it' },
            { 'body', 'node', 'a Block node' },
            { 'cond', 'node', 'an expression node' },
        },
    },
    {
        tag = 'Fornum',
        doc = '`for var = start, limit, step do body end`.',
        fields = {
            { 'directives', 'node[]', 'the ClvInvariant and ClvDecrease directives above it' },
            { 'start', 'node', 'an expression node' },
            { 'limit', 'node', 'an expression node' },
            { 'step', 'node?', 'an expression node' },
            { 'var', 'node', 'a Binder node' },
            { 'body', 'node', 'a Block node' },
        },
    },
    {
        tag = 'Forin',
        doc = '`for names in iters do body end`.',
        fields = {
            { 'directives', 'node[]', 'the ClvInvariant and ClvDecrease directives above it' },
            { 'iters', 'node[]', 'expression nodes' },
            { 'names', 'node[]', 'Binder nodes' },
            { 'body', 'node', 'a Block node' },
        },
    },
    { tag = 'Return', fields = { { 'values', 'node[]', 'expression nodes' } } },
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
        fields = {
            { 'directives', 'node[]', 'the directives above its definition' },
            { 'params', 'node[]', 'Binder nodes' },
            { 'vararg', 'boolean', 'whether `...` ends the parameters' },
            { 'body', 'node', 'a Block node' },
        },
    },
    { tag = 'Table', doc = 'A table constructor.', fields = { { 'fields', 'node[]', 'TableField nodes' } } },
    {
        tag = 'TableField',
        doc = 'One item of a table constructor. A positional item has no key.',
        fields = { { 'key', 'node?', 'an expression node' }, { 'value', 'node', 'an expression node' } },
    },
    {
        tag = 'Index',
        doc = '`obj[key]`, and `obj.name` with a string key.',
        fields = { { 'obj', 'node', 'an expression node' }, { 'key', 'node', 'an expression node' } },
    },
    { tag = 'BinOp', fields = { { 'op', BINOPS }, { 'lhs', 'node', 'an expression node' }, { 'rhs', 'node', 'an expression node' } } },
    { tag = 'UnOp', fields = { { 'op', "'not' | 'unm' | 'len'" }, { 'arg', 'node', 'an expression node' } } },
    { tag = 'Paren', doc = 'A parenthesized expression. It truncates a call to one value.', fields = { { 'expr', 'node', 'an expression node' } } },
    -- ghost code: in comments, so LuaJIT never runs it
    {
        tag = 'ClvSpec',
        doc = 'A `--[[@spec … ]]` block of spec functions. It is not a scope.',
        fields = { { 'statements', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'ClvLemma',
        doc = 'A `--[[@lemma … ]]` block of lemmas. It is not a scope.',
        fields = { { 'statements', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'ClvProof',
        doc = 'Proof code: a `--[[@proof … ]]` block, which is a scope, or a `---@proof` line of lemma calls.',
        fields = { { 'block', 'boolean' }, { 'statements', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'ClvGhost',
        doc = 'Ghost state: a `--[[@ghost … ]]` block of `local`s and assignments, or a `---@ghost` line of one. It is not a scope.',
        fields = { { 'statements', 'node[]', 'statement nodes' } },
    },
    { tag = 'ClvAssert', doc = '`---@assert cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvAssume', doc = '`---@assume cond`: a fact that nothing proves.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvTypeName', doc = 'A named type in an annotation, such as `int53`, `Seq` or `a.b`.', fields = { { 'name', 'string' } } },
    {
        tag = 'ClvTypeLiteral',
        doc = "A literal type: `'circle'`, `1` or `true`.",
        fields = { { 'kind', "'string' | 'integer' | 'boolean'" }, { 'text', 'string', "a string's value, or the spelling" } },
    },
    {
        tag = 'ClvTypeCode',
        doc = 'A backtick type such as `` `T` ``, which LuaLS names after a string argument.',
        fields = { { 'text', 'string' }, { 'pattern', 'string?', 'the name around it with `%s` in its place, as in `Foo.%s`' } },
    },
    {
        tag = 'ClvTypeApply',
        doc = '`base<args>`, such as `Seq<int53>`.',
        fields = { { 'base', 'node', 'a type node' }, { 'args', 'node[]', 'type nodes' } },
    },
    { tag = 'ClvTypeArray', doc = '`elem[]`.', fields = { { 'elem', 'node', 'a type node' } } },
    { tag = 'ClvTypeUnion', doc = '`A | B`, with two members or more.', fields = { { 'members', 'node[]', 'type nodes' } } },
    { tag = 'ClvTypeOptional', doc = '`T?`.', fields = { { 'inner', 'node', 'a type node' } } },
    {
        tag = 'ClvTypeFun',
        doc = '`fun<generics>(params): returns`, or `async fun…`.',
        fields = {
            { 'async', 'boolean' },
            { 'generics', 'node[]', 'ClvTypeGeneric nodes' },
            { 'params', 'node[]', 'ClvTypeParam nodes' },
            { 'returns', 'node[]', 'ClvTypeReturn nodes' },
        },
    },
    {
        tag = 'ClvTypeParam',
        doc = 'A parameter of a function type: `name?: type`. The type may be left out.',
        fields = { { 'name', 'string', 'a name or `...`' }, { 'optional', 'boolean' }, { 'type', 'node?', 'a type node' } },
    },
    {
        tag = 'ClvTypeReturn',
        doc = 'A result of a function type: `type`, or `name: type`.',
        fields = { { 'name', 'string?' }, { 'type', 'node', 'a type node' } },
    },
    { tag = 'ClvTypeTable', doc = 'A table type such as `{ x: T, [K]: V }`.', fields = { { 'fields', 'node[]', 'ClvTypeField nodes' } } },
    {
        tag = 'ClvTypeField',
        doc = 'A field of a table type, with a name or a key type in brackets.',
        fields = { { 'key', 'node?', 'a type node' }, { 'name', 'string?' }, { 'optional', 'boolean' }, { 'type', 'node', 'a type node' } },
    },
    { tag = 'ClvTypeTuple', doc = 'A tuple type such as `[A, B]`.', fields = { { 'items', 'node[]', 'type nodes' } } },
    { tag = 'ClvTypeGeneric', doc = 'A type parameter of a function type, class or alias: the `T` of `fun<T>`.', fields = { { 'name', 'string' } } },
    -- directives: each kind's tag after `---@` is in clavius.ir.support
    { tag = 'ClvMarker', doc = '`---@clavius` above a function: the function is verified.', fields = {} },
    { tag = 'ClvUnsafe', doc = '`---@unsafe`: the function is trusted to meet its contract.', fields = {} },
    { tag = 'ClvPre', doc = '`---@pre cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvPost', doc = '`---@post cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    {
        tag = 'ClvParam',
        doc = '`---@param name type`, `name?` or `...`.',
        fields = { { 'name', 'string' }, { 'optional', 'boolean' }, { 'type', 'node', 'a type node' } },
    },
    {
        tag = 'ClvReturn',
        doc = 'One value of a `---@return`, with its name if it has one.',
        fields = { { 'name', 'string?' }, { 'type', 'node', 'a type node' } },
    },
    { tag = 'ClvDecrease', doc = '`---@decrease a, b`, compared lexicographically.', fields = { { 'measures', 'node[]', 'expression nodes' } } },
    { tag = 'ClvInvariant', doc = '`---@invariant cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvMut', doc = '`---@mut p`.', fields = { { 'name', 'string' } } },
    { tag = 'ClvMove', doc = '`---@move p`.', fields = { { 'name', 'string' } } },
    {
        tag = 'ClvFrozen',
        doc = '`---@frozen p` on a parameter, or `---@frozen` on a class or local declaration.',
        fields = { { 'name', 'string?' } },
    },
    {
        tag = 'ClvLen',
        doc = '`---@len p n`: the slice parameter `p` holds `n` elements.',
        fields = { { 'param', 'string' }, { 'length', 'string' } },
    },
    { tag = 'ClvDisjoint', doc = '`---@disjoint a, b`.', fields = { { 'first', 'string' }, { 'second', 'string' } } },
    { tag = 'ClvEntry', doc = '`---@entry`: the host calls the function.', fields = {} },
    { tag = 'ClvExtern', doc = '`---@extern`: a host function or global in a `---@meta` file.', fields = {} },
    { tag = 'ClvNoCallback', doc = '`---@no_callback`.', fields = {} },
    { tag = 'ClvMayRaise', doc = '`---@may_raise`.', fields = {} },
    { tag = 'ClvRlimit', doc = '`---@rlimit N`.', fields = { { 'limit', 'integer' } } },
    { tag = 'ClvProofBy', doc = '`---@proof_by(theory)`.', fields = { { 'theory', "'nonlinear_arith' | 'bit_vector'" } } },
    { tag = 'ClvRevealWithFuel', doc = '`---@reveal_with_fuel(f, n)`.', fields = { { 'name', 'string' }, { 'fuel', 'integer' } } },
    { tag = 'ClvModuleInvariant', doc = '`---@module_invariant cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvClosureInvariant', doc = '`---@closure_invariant cond`.', fields = { { 'cond', 'node', 'an expression node' } } },
    { tag = 'ClvType', doc = '`---@type T1, T2`.', fields = { { 'types', 'node[]', 'type nodes' } } },
    {
        tag = 'ClvClass',
        doc = '`---@class (attrs) Name<T>: Parent, …`.',
        fields = {
            { 'exact', 'boolean' },
            { 'partial', 'boolean' },
            { 'name', 'string' },
            { 'generics', 'node[]', 'ClvTypeGeneric nodes' },
            { 'parents', 'node[]', 'type nodes' },
        },
    },
    {
        tag = 'ClvField',
        doc = '`---@field name T`, `name? T` or `[K] V`. LuaLS visibilities such as `private` are dropped.',
        fields = { { 'key', 'node?', 'a type node' }, { 'name', 'string?' }, { 'optional', 'boolean' }, { 'type', 'node', 'a type node' } },
    },
    {
        tag = 'ClvAlias',
        doc = '`---@alias Name<T> type`.',
        fields = { { 'name', 'string' }, { 'generics', 'node[]', 'ClvTypeGeneric nodes' }, { 'type', 'node', 'a type node' } },
    },
    { tag = 'ClvEnum', doc = '`---@enum (attrs) Name`.', fields = { { 'key', 'boolean' }, { 'partial', 'boolean' }, { 'name', 'string' } } },
    {
        tag = 'ClvGeneric',
        doc = 'One type parameter of `---@generic`, with an optional bound as in `T : value`.',
        fields = { { 'name', 'string' }, { 'bound', 'node?', 'a type node' } },
    },
    {
        tag = 'ClvCast',
        doc = 'One step of `---@cast name …`: `T` sets the type, `+T` adds a member and `-T` removes one. No type stands for `?`.',
        fields = { { 'name', 'string' }, { 'mode', "'set' | 'add' | 'remove'" }, { 'type', 'node?', 'a type node' } },
    },
    { tag = 'ClvAs', doc = 'The cast `--[[@as T]]`.', fields = { { 'type', 'node', 'a type node' } } },
    { tag = 'ClvVararg', doc = '`---@vararg T`.', fields = { { 'type', 'node', 'a type node' } } },
    { tag = 'ClvOverload', doc = '`---@overload fun(…)`.', fields = { { 'type', 'node', 'a type node' } } },
    {
        tag = 'ClvOperator',
        doc = '`---@operator add(Vec): Vec`, or `unm: Vec` with no operand.',
        fields = { { 'op', 'string' }, { 'operand', 'node?', 'a type node' }, { 'result', 'node', 'a type node' } },
    },
    { tag = 'ClvMeta', doc = '`---@meta name`, where the name may be left out.', fields = { { 'name', 'string?' } } },
    { tag = 'ClvModule', doc = "`---@module 'name'`.", fields = { { 'name', 'string' } } },
}

--- @type NodeSchema
return { doc = DOC, nodes = NODES }
