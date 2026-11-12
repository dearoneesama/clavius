-- Core node types. `schema/gen.lua` turns this into src/clavius/ir/core_nodes.lua.
-- The field format is described in schema/source.lua.

local OPS = "'+' | '-' | '*' | '<' | '<=' | '>' | '>=' | '==' | '!=' | 'and' | 'or' | '=>'"

--- @type NodeType[]
return {
    {
        tag = 'Unit',
        doc = 'One independent proof: its variables and its statements.',
        fields = { { 'name', 'string' }, { 'vars', 'node[]', 'VarDecl nodes' }, { 'body', 'node[]', 'statements' } },
    },
    {
        tag = 'VarDecl',
        doc = "A unit's variable. It starts with an arbitrary value of its sort.",
        fields = { { 'name', 'string' }, { 'sort', "'int' | 'bool'" } },
    },
    { tag = 'Assign', doc = '`target := value`.', fields = { { 'target', 'string' }, { 'value', 'node' } } },
    { tag = 'Havoc', doc = 'Gives `target` an arbitrary value of its sort.', fields = { { 'target', 'string' } } },
    {
        tag = 'Assume',
        doc = 'An assumption with its justification.',
        fields = { { 'assumption', 'integer', 'assumption id' }, { 'cond', 'node' } },
    },
    {
        tag = 'Check',
        doc = 'A proof obligation. The code after it may assume `cond`.',
        fields = { { 'obligation', 'integer', 'obligation id' }, { 'cond', 'node' } },
    },
    {
        tag = 'Branch',
        doc = 'Runs `then_body` if `cond` holds, `else_body` otherwise.',
        fields = { { 'cond', 'node' }, { 'then_body', 'node[]' }, { 'else_body', 'node[]' } },
    },
    {
        tag = 'Choice',
        doc = 'Runs one of two statement lists, chosen arbitrarily.',
        fields = { { 'first', 'node[]' }, { 'second', 'node[]' } },
    },
    {
        tag = 'Block',
        doc = 'A labeled statement list. An `Exit` with its label inside it jumps to its end.',
        fields = { { 'label', 'string' }, { 'body', 'node[]' } },
    },
    { tag = 'Exit', doc = 'Jumps to the end of the enclosing Block with this label.', fields = { { 'label', 'string' } } },
    { tag = 'Var', doc = 'A variable.', fields = { { 'name', 'string' } } },
    { tag = 'Int', doc = 'An integer literal.', fields = { { 'text', 'string', "decimal digits with an optional '-'" } } },
    { tag = 'Bool', doc = 'A boolean literal.', fields = { { 'value', 'boolean' } } },
    {
        tag = 'BinOp',
        doc = 'An integer or boolean operator. `=>` is implication.',
        fields = { { 'op', OPS }, { 'lhs', 'node' }, { 'rhs', 'node' } },
    },
    { tag = 'Not', doc = 'Boolean negation.', fields = { { 'arg', 'node' } } },
    {
        tag = 'Ite',
        doc = '`if cond then if_true else if_false`, as a term.',
        fields = { { 'cond', 'node' }, { 'if_true', 'node' }, { 'if_false', 'node' } },
    },
}
