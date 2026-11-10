-- Source node types: Lua nodes and Clavius source nodes. `schema/gen.lua` turns this into
-- src/clavius/ir/source_nodes.lua.
--
-- Each field is { name, type, doc }. The type is `node`, `node?`, `node[]`, or an atom: `string`,
-- `integer`, `boolean`, or a union of string literals. Fields are listed in evaluation order.

--- @type NodeType[]
return {
    { tag = 'Block', doc = 'A statement list.', fields = { { 'stats', 'node[]' } } },
    {
        tag = 'Local',
        doc = '`local names = values`. The values come first, because they are evaluated before the names are bound.',
        fields = { { 'values', 'node[]' }, { 'names', 'node[]', 'Binder nodes' } },
    },
    { tag = 'Binder', doc = 'A name in a binding position.', fields = { { 'name', 'string' } } },
    { tag = 'Id', doc = 'A name that is read.', fields = { { 'name', 'string' } } },
    {
        tag = 'Literal',
        doc = 'A literal value.',
        fields = {
            { 'kind', "'nil' | 'true' | 'false' | 'number' | 'string'" },
            { 'text', 'string', "source spelling, e.g. '1LL'" },
        },
    },
    {
        tag = 'If',
        doc = '`if` with its `elseif` arms.',
        fields = { { 'arms', 'node[]', 'IfArm nodes, one per `if` and `elseif`' }, { 'else_block', 'node?' } },
    },
    { tag = 'IfArm', doc = 'One condition and its body.', fields = { { 'cond', 'node' }, { 'body', 'node' } } },
}
