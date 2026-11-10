-- Core node types. `schema/gen.lua` turns this into src/clavius/ir/core_nodes.lua.
-- The field format is described in schema/source.lua.

--- @type NodeType[]
return {
    { tag = 'Unit', doc = 'One independent proof.', fields = { { 'name', 'string' }, { 'body', 'node[]' } } },
    { tag = 'Assign', doc = '`target := value`.', fields = { { 'target', 'string' }, { 'value', 'node' } } },
    {
        tag = 'Assume',
        doc = 'An assumption with its justification.',
        fields = { { 'assumption', 'integer', 'assumption id' }, { 'cond', 'node' } },
    },
    {
        tag = 'Check',
        doc = 'A proof obligation.',
        fields = { { 'obligation', 'integer', 'obligation id' }, { 'cond', 'node' } },
    },
    { tag = 'Var', doc = 'A variable.', fields = { { 'name', 'string' } } },
    { tag = 'Int', doc = 'An integer literal.', fields = { { 'text', 'string' } } },
    { tag = 'App', doc = 'A function application.', fields = { { 'fn', 'string' }, { 'args', 'node[]' } } },
}
