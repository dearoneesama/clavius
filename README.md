# clavius

Clavius is a tool to check that LuaJIT programs are correct. One states what their code should do as LuaLS-style
comment annotations, and Clavius checks, without running the code, that it does so on every possible
execution. Clavius handles a subset of LuaJIT, and it can prove facts that LuaJIT itself never checks, such
as that integer arithmetic stays within ±2^53, where doubles hold every integer exactly.

## Usage

Clavius checks only marked code. A pair of `---@clavius begin` and `---@clavius end` marks a region, or `---@clavius` above a single `local function` marks that function. Code outside them isn't checked and may use all of Lua.

```lua
--- bucket.lua
local CAPACITY = 100
local RATE = 5

--- A rate limiter that allows bursts of CAPACITY requests and refills RATE a second.
---@clavius
---@param tokens integer
---@param elapsed integer seconds since the last refill
---@pre tokens >= 0 and tokens <= CAPACITY
---@pre elapsed >= 0 and elapsed <= 3600
---@post result >= tokens and result <= CAPACITY
---@return integer
local function refill(tokens, elapsed)
    local added = elapsed * RATE
    if added > CAPACITY then
        return CAPACITY
    end
    return tokens + added
end

return {
    refill = refill
}
```

```bash
$ clavius verify bucket.lua
bucket.lua:17:5: post: the function may return here without satisfying its postcondition `result >= tokens and result <= CAPACITY` [O4]
```

Clavius cannot prove the postcondition, implying there is a bug in the implementation. Changing `added > CAPACITY` to `tokens + added > CAPACITY` fixes it and the error disappears.

### Library and host functions

Marked code may call the standard library functions that Clavius ships specs for, such as `math.min`, and `math.floor(a / b)` and `%` are integer division and remainder. Functions that the host provides are declared in a `---@meta` file with a contract, and the file is given with `--meta`:

```lua
--- game.meta.lua
---@meta

---@extern
---@param hp integer
---@param dmg integer
---@pre hp >= 0 and dmg >= 0
---@post result >= 0 and result <= hp
---@return integer
function host.damage(hp, dmg) end
```

```bash
$ clavius verify --meta game.meta.lua --trust-report game.lua
```

Clavius trusts these contracts without proof, and `--trust-report` lists every one that a run relied on.

### Supported feature matrix

Clavius is being developed, so this table may change over time and may not reflect the current state accurately.

|Lua/Clavius features|Supported?|
|-|-|
|Number as safe integer|Yes|
|Booleans|Yes|
|Function contracts (`---@pre` and `---@post`)|Yes|
|`---@unsafe` functions and trust reports|Yes|
|Nil, optional types and Lua truthiness|-|
|Floats|-|
|Strings|-|
|Arrays|-|
|Maps|-|
|Structures|-|
|LuaLS Unions, enums and casts|-|
|LuaLS Generics|-|
|Loops with invariants (`---@invariant`) and termination measures (`---@decrease`)|Limited: numeric `for`'s step must be literal, and `---@decrease` takes one expression|
|Custom iterators|-|
|Recursion with Clavius' termination measures|-|
|Varargs and multiple return values|-|
|Module state and closures|-|
|Standard library calls, including integer division (`math.floor(a / b)`) and modulo (`%`)|Limited: `math.min`, `math.max` and `math.abs` on integers, with two arguments for `min` and `max`|
|Host functions|Yes: `---@extern` functions in a `---@meta` file given with `--meta`|
|Multiple files and modules|-|
|OOP and classes|-|
|Clavius ownership modes|-|
|Quantifiers|-|
|Ghost code and spec functions|-|
|Nonlinear arithmetic|-|
|Reporting counterexamples for failed checks|-|
|Bit operations|-|
|LuaJIT FFI|-|
|LuaJIT Complex numbers|-|
|LuaJIT 3.0 syntax backports|-|
|Coroutines|-|
|Error handling with `pcall`|-|
|Metatables beyond classes, weak tables and finalizers|-|
|Globals, `goto`, `load`, `setfenv`, `rawget`, `getmetatable`, `debug` and the like|-|

## Getting started

Before cloning the repository, you need the following prerequisites:
* [LuaJIT](https://luajit.org/) 2.1
* [LuaRocks](https://luarocks.org/)
* [Boogie](https://github.com/boogie-org/boogie) as the verification backend
* [Z3](https://github.com/Z3Prover/z3) as the SMT solver used by Boogie

Clavius runs the executable named by `BOOGIE`/`boogie` from `PATH`. Boogie runs the Z3 named
by `Z3`/`z3` from `PATH`.

Then install the dependencies and run Clavius:

```bash
luarocks --tree lua_modules install --only-deps clavius-dev-1.rockspec
./bin/clavius verify <program>.lua
```
[This folder](./tests/e2e/verify/) contains some example programs.

### For developing

Install the development dependencies:
```bash
make dev
```

Run tests and lint:
```bash
make test # UPDATE_SNAPSHOTS=1 rewrites tests
make e2e
make lint
```

## Architecture

Clavius is a compiler that checks the source file, translates its marked code into a Boogie program
(`.bpl`), and has Boogie verify that program with the Z3 SMT solver.

```
program.lua
    │
    ▼
 parse ─────── parses annotated source code into a Clavius AST using luacheck
    │
    ▼
 resolve ───── resolves symbols and declarations, and checks for unsupported code
    │
    ▼
 types ─────── typechecking
    │
    ▼
 effects ───── finds locals each loop writes, which its encoding havocs
    │
    ▼
 termination ─ checks that every applicable loops have a termination measure
    │
    ▼
 elaborate ─── converts the Clavius AST into Core IL: an intermediate
    │          representation for command (Assign, Assume, Check, Havoc, etc.)
    |          sequences and source code mappings.
    ▼
 validate ──── tries to spot inconsistencies in the Core IL
    │
    ▼
 lower ─────── converts the Core IL into a Boogie program
    │
    ▼
 Boogie ────── constructs verification conditions and find counterexamples
    │
    ▼
 report ────── failing ids back to messages
```

`clavius dump` command prints the program after any stage up to `validate`,
and `clavius lower` command prints the Boogie program for a core program.

