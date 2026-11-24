-- Core node types. `schema/gen.lua` turns this into src/clavius/ir/core_nodes.lua and
-- src/clavius/sexpr/schema.lua. The field format is described in schema/source.lua.

local OPS = "'+' | '-' | '*' | 'mod' | '<' | '<=' | '>' | '>=' | '==' | '!=' | 'and' | 'or' | '=>'"

local DOC = [[
A declaration is a SortDecl, FunDecl or Axiom node.
A statement node is an Assign, Havoc, Assume, Check, Branch, Choice, Block or Exit node.
A term node is a Var, Int, Bool, BinOp, Not, Ite, Let, App or Forall node.]]

--- @type NodeType[]
local NODES = {
    { tag = 'SortDecl', doc = 'A sort with no values of its own but those of its functions.', fields = { { 'name', 'string' } } },
    {
        tag = 'FunDecl',
        doc = 'A function of its parameters. One with no parameters is a constant.',
        fields = { { 'name', 'string' }, { 'params', 'node[]', 'VarDecl nodes' }, { 'sort', 'string', '`int`, `bool` or the name of a SortDecl' } },
    },
    { tag = 'Axiom', doc = 'A fact that every unit may assume.', fields = { { 'cond', 'node', 'a term node' } } },
    {
        tag = 'Unit',
        doc = 'One independent proof: its variables and its statements. A linear one leaves Z3 no nonlinear arithmetic.',
        fields = {
            { 'name', 'string' },
            { 'arith', "'linear' | 'nonlinear'" },
            { 'vars', 'node[]', 'VarDecl nodes' },
            { 'body', 'node[]', 'statement nodes' },
        },
    },
    {
        tag = 'VarDecl',
        doc = "A unit's variable. It starts with an arbitrary value of its sort.",
        fields = { { 'name', 'string' }, { 'sort', 'string', '`int`, `bool` or the name of a SortDecl' } },
    },
    { tag = 'Assign', doc = '`target := value`.', fields = { { 'target', 'string' }, { 'value', 'node', 'a term node' } } },
    { tag = 'Havoc', doc = 'Gives `target` an arbitrary value of its sort.', fields = { { 'target', 'string' } } },
    {
        tag = 'Assume',
        doc = 'An assumption with its justification.',
        fields = { { 'assumption', 'integer', 'assumption id' }, { 'cond', 'node', 'a term node' } },
    },
    {
        tag = 'Check',
        doc = 'A proof obligation. The code after it may assume `cond`.',
        fields = { { 'obligation', 'integer', 'obligation id' }, { 'cond', 'node', 'a term node' } },
    },
    {
        tag = 'Branch',
        doc = 'Runs `then_body` if `cond` holds, `else_body` otherwise.',
        fields = { { 'cond', 'node', 'a term node' }, { 'then_body', 'node[]', 'statement nodes' }, { 'else_body', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'Choice',
        doc = 'Runs one of two statement lists, chosen arbitrarily.',
        fields = { { 'first', 'node[]', 'statement nodes' }, { 'second', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'Block',
        doc = 'A labeled statement list. An `Exit` with its label inside it jumps to its end.',
        fields = { { 'label', 'string' }, { 'body', 'node[]', 'statement nodes' } },
    },
    { tag = 'Exit', doc = 'Jumps to the end of the enclosing Block with this label.', fields = { { 'label', 'string' } } },
    { tag = 'Var', doc = 'A variable.', fields = { { 'name', 'string' } } },
    { tag = 'Int', doc = 'An integer literal.', fields = { { 'text', 'string', "decimal digits with an optional '-'" } } },
    { tag = 'Bool', doc = 'A boolean literal.', fields = { { 'value', 'boolean' } } },
    {
        tag = 'BinOp',
        doc = 'An integer or boolean operator. `=>` is implication, and `mod` the Euclidean remainder, which lies in [0, |rhs|) when rhs ~= 0.',
        fields = { { 'op', OPS }, { 'lhs', 'node', 'a term node' }, { 'rhs', 'node', 'a term node' } },
    },
    { tag = 'Not', doc = 'Boolean negation.', fields = { { 'arg', 'node', 'a term node' } } },
    {
        tag = 'Ite',
        doc = '`if cond then if_true else if_false`, as a term.',
        fields = { { 'cond', 'node', 'a term node' }, { 'if_true', 'node', 'a term node' }, { 'if_false', 'node', 'a term node' } },
    },
    {
        tag = 'Let',
        doc = '`body` with the variable `name` bound to `value`.',
        fields = { { 'name', 'string' }, { 'value', 'node', 'a term node' }, { 'body', 'node', 'a term node' } },
    },
    { tag = 'App', doc = 'The function of a FunDecl applied to terms.', fields = { { 'fn', 'string' }, { 'args', 'node[]', 'term nodes' } } },
    {
        tag = 'Forall',
        doc = 'A term that holds for every value of its variables. It is used where a Trigger matches.',
        fields = { { 'vars', 'node[]', 'VarDecl nodes' }, { 'triggers', 'node[]', 'Trigger nodes' }, { 'body', 'node', 'a term node' } },
    },
    { tag = 'Trigger', doc = 'Terms that together instantiate a Forall.', fields = { { 'terms', 'node[]', 'term nodes' } } },
}

--- @type NodeSchema
return { doc = DOC, nodes = NODES }
