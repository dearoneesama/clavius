-- What Clavius verifies: the node kinds, operators, types, directives and library functions that marked
-- code may use. Marked code is a `---@clavius begin` … `end` region or a function marked `---@clavius`.
-- Anything else is reported as unsupported, or as banned when it is listed here among the features that
-- verified code must never use.

local M = {}

--- Source kinds that marked code may use.
--- @type table<string, boolean>
M.KINDS = {
    ClvRegion = true,
    Block = true,
    Local = true,
    LocalFunction = true,
    Function = true,
    Return = true,
    While = true,
    Repeat = true,
    Fornum = true,
    Break = true,
    Set = true,
    Call = true,
    If = true,
    IfArm = true,
    Binder = true,
    Id = true,
    Literal = true,
    BinOp = true,
    UnOp = true,
    Paren = true,
    ClvSpec = true,
    ClvLemma = true,
    ClvProof = true,
    ClvGhost = true,
    ClvAssert = true,
    ClvAssume = true,
}

--- Source kinds that marked code must never use.
--- @type table<string, boolean>
M.BANNED_KINDS = { Goto = true, Label = true }

--- Binary operators that marked code may use.
--- @type table<string, boolean>
M.BINOPS = {
    add = true,
    sub = true,
    mul = true,
    eq = true,
    ne = true,
    lt = true,
    le = true,
    gt = true,
    ge = true,
    ['and'] = true,
    ['or'] = true,
}

--- Unary operators that marked code may use.
--- @type table<string, boolean>
M.UNOPS = { unm = true, ['not'] = true }

--- Types that marked code may use.
--- @type table<string, boolean>
M.TYPES = { int53 = true, boolean = true }

--- Library functions that marked code may call, and `assume`, which only proof code may call.
--- @type table<string, boolean>
M.CALLS = { assert = true, assume = true, error = true }

--- Directive kinds that marked code may use above a function.
--- @type table<string, boolean>
M.FUNCTION_DIRECTIVES = {
    ClvMarker = true,
    ClvUnsafe = true,
    ClvPre = true,
    ClvPost = true,
    ClvParam = true,
    ClvReturn = true,
    ClvDecrease = true,
    ClvRevealWithFuel = true,
}

--- Directive kinds that a spec function may have.
--- @type table<string, boolean>
M.SPEC_DIRECTIVES = { ClvParam = true, ClvReturn = true, ClvDecrease = true }

--- Directive kinds that a lemma may have.
--- @type table<string, boolean>
M.LEMMA_DIRECTIVES = { ClvParam = true, ClvReturn = true, ClvPre = true, ClvPost = true, ClvDecrease = true, ClvRevealWithFuel = true }

--- Directive kinds that marked code may use above a loop.
--- @type table<string, boolean>
M.LOOP_DIRECTIVES = { ClvInvariant = true, ClvDecrease = true }

--- The tag after `---@` of each directive kind.
--- @type table<string, string>
M.DIRECTIVE_TAGS = {
    ClvMarker = 'clavius',
    ClvUnsafe = 'unsafe',
    ClvPre = 'pre',
    ClvPost = 'post',
    ClvParam = 'param',
    ClvReturn = 'return',
    ClvDecrease = 'decrease',
    ClvInvariant = 'invariant',
    ClvMut = 'mut',
    ClvMove = 'move',
    ClvFrozen = 'frozen',
    ClvLen = 'len',
    ClvDisjoint = 'disjoint',
    ClvEntry = 'entry',
    ClvExtern = 'extern',
    ClvNoCallback = 'no_callback',
    ClvMayRaise = 'may_raise',
    ClvRlimit = 'rlimit',
    ClvProofBy = 'proof_by',
    ClvRevealWithFuel = 'reveal_with_fuel',
    ClvModuleInvariant = 'module_invariant',
    ClvClosureInvariant = 'closure_invariant',
    ClvType = 'type',
    ClvClass = 'class',
    ClvField = 'field',
    ClvAlias = 'alias',
    ClvEnum = 'enum',
    ClvGeneric = 'generic',
    ClvCast = 'cast',
    ClvAs = 'as',
    ClvVararg = 'vararg',
    ClvOverload = 'overload',
    ClvOperator = 'operator',
    ClvMeta = 'meta',
    ClvModule = 'module',
}

--- Globals that marked code must never use. For a library table, that covers every field in it.
--- @type table<string, boolean>
M.BANNED = {
    pcall = true,
    xpcall = true,
    load = true,
    loadstring = true,
    loadfile = true,
    dofile = true,
    getfenv = true,
    setfenv = true,
    rawget = true,
    rawset = true,
    rawequal = true,
    getmetatable = true,
    collectgarbage = true,
    gcinfo = true,
    module = true,
    newproxy = true,
    debug = true,
    coroutine = true,
    _G = true,
}

--- Every global that LuaJIT 2.1 defines.
--- @type table<string, boolean>
M.GLOBALS = {
    _G = true,
    _VERSION = true,
    assert = true,
    bit = true,
    collectgarbage = true,
    coroutine = true,
    debug = true,
    dofile = true,
    error = true,
    gcinfo = true,
    getfenv = true,
    getmetatable = true,
    io = true,
    ipairs = true,
    jit = true,
    load = true,
    loadfile = true,
    loadstring = true,
    math = true,
    module = true,
    newproxy = true,
    next = true,
    os = true,
    package = true,
    pairs = true,
    pcall = true,
    print = true,
    rawequal = true,
    rawget = true,
    rawset = true,
    require = true,
    select = true,
    setfenv = true,
    setmetatable = true,
    string = true,
    table = true,
    tonumber = true,
    tostring = true,
    type = true,
    unpack = true,
    xpcall = true,
}

--- What a global name is to marked code:
--- - `supported`: a function in `CALLS`;
--- - `banned`: a feature that verified code must never use, such as `pcall` or `debug.traceback`;
--- - `library`: a part of the library that Clavius has no rule for, such as `print` or `math.floor`;
--- - `global`: a global outside the library. Verified code must never use one.
--- @alias GlobalUse 'supported' | 'banned' | 'library' | 'global'

--- Says what a global, or a field of one, is to marked code.
--- @param base string the global's name
--- @param path string `base`, or `base.field` for a field such as `math.floor`
--- @return GlobalUse
function M.global_use(base, path)
    if M.CALLS[path] then
        return 'supported'
    elseif M.BANNED[base] then
        return 'banned'
    elseif M.GLOBALS[base] then
        return 'library'
    end
    return 'global'
end

return M
