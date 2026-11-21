-- Core node types. `schema/gen.lua` turns this into src/clavius/ir/core_nodes.lua and
-- src/clavius/sexpr/schema.lua. The field format is described in schema/source.lua.

local OPS = "'+' | '-' | '*' | 'div' | 'mod' | '<' | '<=' | '>' | '>=' | '==' | '!=' | 'and' | 'or' | '=>'"

local DOC = [[
A statement node is an Assign, Havoc, Assume, Check, Branch, Choice, Block or Exit node.
A term node is a Var, Int, Bool, BinOp, Not or Ite node.]]

--- @type NodeType[]
local NODES = {
    {
        tag = 'Unit',
        doc = 'One independent proof: its variables and its statements.',
        fields = { { 'name', 'string' }, { 'vars', 'node[]', 'VarDecl nodes' }, { 'body', 'node[]', 'statement nodes' } },
    },
    {
        tag = 'VarDecl',
        doc = "A unit's variable. It starts with an arbitrary value of its sort.",
        fields = { { 'name', 'string' }, { 'sort', "'int' | 'bool'" } },
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
        doc = 'An integer or boolean operator. `=>` is implication. `div` and `mod` are Euclidean: when rhs ~= 0, '
            .. '`lhs == (lhs div rhs) * rhs + lhs mod rhs` with the remainder in [0, |rhs|).',
        fields = { { 'op', OPS }, { 'lhs', 'node', 'a term node' }, { 'rhs', 'node', 'a term node' } },
    },
    { tag = 'Not', doc = 'Boolean negation.', fields = { { 'arg', 'node', 'a term node' } } },
    {
        tag = 'Ite',
        doc = '`if cond then if_true else if_false`, as a term.',
        fields = { { 'cond', 'node', 'a term node' }, { 'if_true', 'node', 'a term node' }, { 'if_false', 'node', 'a term node' } },
    },
}

--- @type NodeSchema
return { doc = DOC, nodes = NODES }
