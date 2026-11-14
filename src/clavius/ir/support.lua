-- What Clavius verifies: the node kinds, operators, types and library functions that the code in a
-- `---@clavius begin` … `end` region may use. Anything else is reported as unsupported, or as banned
-- when it is listed here among the features that verified code must never use.

local M = {}

--- Source kinds that regions may use.
--- @type table<string, boolean>
M.KINDS = {
    ClvRegion = true,
    Block = true,
    Local = true,
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
}

--- Source kinds that regions must never use.
--- @type table<string, boolean>
M.BANNED_KINDS = { Goto = true, Label = true }

--- Binary operators that regions may use.
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

--- Unary operators that regions may use.
--- @type table<string, boolean>
M.UNOPS = { unm = true, ['not'] = true }

--- Types that regions may use.
--- @type table<string, boolean>
M.TYPES = { int53 = true, boolean = true }

--- Library functions that regions may call.
--- @type table<string, boolean>
M.CALLS = { assert = true, error = true }

--- Globals that regions must never use. For a library table, that covers every field in it.
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

--- What a global name is to a region:
--- - `supported`: a library function in `CALLS`;
--- - `banned`: a feature that verified code must never use, such as `pcall` or `debug.traceback`;
--- - `library`: a part of the library that Clavius has no rule for, such as `print` or `math.floor`;
--- - `global`: a global outside the library. Verified code must never use one.
--- @alias GlobalUse 'supported' | 'banned' | 'library' | 'global'

--- Says what a global, or a field of one, is to a region.
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
