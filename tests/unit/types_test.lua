local driver = require 'clavius.driver'
local markers = require 'support.markers'
local types = require 'clavius.passes.types'

describe('types', function()
    it('types number literals by their spelling', function()
        local cases = {
            { '0', 'int53' },
            { '007', 'int53' },
            { '0xff', 'int53' },
            { '0X1F', 'int53' },
            { '9007199254740992', 'int53' },
            { '0x20000000000000', 'int53' },
            { '0x0020000000000000', 'int53' },
            { '9007199254740993', 'f64' },
            { '0x20000000000001', 'f64' },
            { '1.0', 'f64' },
            { '1e3', 'f64' },
            { '.5', 'f64' },
            { '0x1p4', 'f64' },
            { '1LL', 'i64' },
            { '1ULL', 'u64' },
            { '1llu', 'u64' },
            { '1i', 'complex' },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], types.number_type(c[1]), c[1])
        end
    end)

    it('gives each local the type of its initializer', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, 1 < 2
            local y = x
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' then
                found[#found + 1] = ('%s %s'):format(res.names[id], info.types[id])
            end
        end
        assert.are.same({ 'x$1 int53', 'p$2 boolean', 'y$3 int53' }, found)
    end)

    it('types ghost locals and the arithmetic of ghost code and clauses as Int', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            ---@param n integer
            ---@pre n + 1 > 0
            ---@return integer
            local function f(n)
                return n + 1
            end
            local x = 1
            local y = x + 1
            ---@ghost local g = x
            ---@ghost local h = x + 1
            ---@ghost local q = x > 0
            --[[@proof
                local s = g + h
                for i = 1, 3 do
                end
            ]]
            ---@assert x + 1 > 0
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local binders = {}
        local sums = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' then
                binders[#binders + 1] = ('%s %s'):format(n.name, info.types[id])
            elseif n.tag == 'BinOp' and n.op == 'add' then
                sums[#sums + 1] = info.types[id]
            end
        end
        assert.are.same({
            'f nil',
            'n int53',
            'x int53',
            'y int53',
            'g Int',
            'h Int',
            'q boolean',
            's Int',
            'i Int',
        }, binders)
        -- `n + 1` in the pre, then in the body, `x + 1` for `y`, for `h`, `g + h`, `x + 1` in the assert
        assert.are.same({ 'Int', 'int53', 'int53', 'Int', 'Int', 'Int' }, sums)
    end)

    it('checks ghost code as exec code is checked, and keeps Int and Nat out of exec signatures', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local x = 1
            ---@ghost local g = x
            ---@ghost g = true --! E-type-mismatch
            ---@assert g --! E-unsupported-feature
            --[[@proof
                if g then --! E-unsupported-feature
                end
            ]]
            ---@clavius end
            ---@clavius
            ---@param n Nat
            --! E-type-mismatch
            ---@return Int
            --! E-type-mismatch
            local function f(n)
                return n
            end
            ]=]
        )
    end)

    it('rejects unsupported types', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local a = 1.5 --! E-unsupported-type
            local b = 1LL --! E-unsupported-type
            local c = 1ULL --! E-unsupported-type
            local d = 1i --! E-unsupported-type
            local e = 9007199254740993 --! E-unsupported-type
            local f = 'text' --! E-unsupported-type
            local g = nil --! E-unsupported-type
            local h = -0x20000000000001 --! E-unsupported-type
            ---@clavius end
            ]=]
        )
    end)

    it('checks operands and values against their types', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, true
            local a = x + p --! E-type-mismatch
            local b = p < x --! E-type-mismatch
            local c = -p --! E-type-mismatch
            local d = x == p --! E-type-mismatch
            x = p --! E-type-mismatch
            p = 1 --! E-type-mismatch
            local e = x * 2 - -x
            local f = x <= 3 and not p or x ~= 0
            local g = p == (x > 1)
            x = e
            p = f
            ---@clavius end
            ]=]
        )
    end)

    it('accepts only booleans as conditions', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local x, p = 1, true
            if x then end --! E-unsupported-feature
            assert(x) --! E-unsupported-feature
            local a = p and x --! E-unsupported-feature
            local b = x or p --! E-unsupported-feature
            local c = not x --! E-unsupported-feature
            if p then elseif x < 2 then end
            assert(p)
            local d = p and x < 2
            local e = x == 1 or not p
            local f = not (p and d)
            ---@clavius end
            ]=]
        )
    end)

    it('does not type the messages of assert and error', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            assert(true, 'message')
            error('message', 1.5)
            ---@clavius end
            ]=]
        )
    end)

    it('reports an error once, not again in what uses it', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local a = 1.5 --! E-unsupported-type
            local b = a + 1
            local c = b < 2 and true
            ---@clavius end
            ]=]
        )
    end)
    it('types parameters and values from `---@param` and `---@return`', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius
            ---@param n integer
            ---@param on boolean
            ---@return int53 sum
            local function f(n, on)
                return n
            end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local found = {}
        for id, ty in pairs(assert(c.info).types) do
            local n = c.src.nodes[id]
            if n.tag == 'Binder' or n.tag == 'ClvReturn' then
                found[#found + 1] = ('%s %s'):format(n.name, ty)
            end
        end
        table.sort(found)
        assert.are.same({ 'n int53', 'on boolean', 'sum int53' }, found)
    end)

    it('rejects types in signatures that this version does not support', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius
            ---@param s string
            --! E-unsupported-type
            ---@return Seq<int53>
            --! E-unsupported-type
            local function f(s, untyped) --! E-unsupported-type
                return 1
            end
            ]=]
        )
    end)

    it('checks returns, clauses and calls against the contracts', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius
            ---@param n integer
            ---@pre n
            --! E-unsupported-feature
            local function none(n)
                return n --! E-type-mismatch
            end
            ---@clavius
            ---@return boolean
            local function flag()
                if true then
                    return --! E-type-mismatch
                end
                return 1 --! E-type-mismatch
            end
            ---@clavius begin
            none(true) --! E-type-mismatch
            local x = none(1) --! E-type-mismatch
            local y = flag()
            ---@clavius end
            ]=]
        )
    end)

    it('checks measures, and calls to functions defined below against their signatures', function()
        markers.expect_diags(
            'types',
            [=[
            local g
            ---@clavius begin
            ---@param n integer
            ---@param on boolean
            ---@decrease n, on
            --! E-type-mismatch
            ---@return integer
            local function f(n, on)
                return g(on) --! E-type-mismatch E-type-mismatch
            end
            ---@param n integer
            ---@return boolean
            function g(n)
                return n > 0
            end
            local x = g(1)
            ---@clavius end
            ]=]
        )
    end)

    it('checks loop conditions, bounds, invariants and measures', function()
        local c = markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            local n = 1
            local on = true
            ---@invariant n
            --! E-unsupported-feature
            ---@decrease on
            --! E-type-mismatch
            while n do end --! E-unsupported-feature
            ---@invariant on
            ---@decrease n, on
            --! E-type-mismatch
            repeat local m = n until m --! E-unsupported-feature
            for i = on, 2, 1.5 do end --! E-type-mismatch E-unsupported-type
            ---@invariant i
            --! E-unsupported-feature
            for i = 1, n do
                local k = i
            end
            ---@clavius end
            ]=]
        )
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' and (n.name == 'i' or n.name == 'k') then
                found[#found + 1] = ('%s %s'):format(res.names[id], info.types[id])
            end
        end
        assert.are.same({ 'i$4 int53', 'i$5 int53', 'k$6 int53' }, found)
    end)
    it('gives ghost locals and spec arithmetic the exact type Int', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param n Nat
            ---@return Nat
            local function same(n) return n end
            ]]
            local x = 1
            ---@ghost local g = x + 1
            ---@ghost local h = same(x)
            ---@ghost local p = g > 0
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' or (n.tag == 'BinOp' and n.op == 'add') then
                found[#found + 1] = ('%s %s'):format(res.names[id] or n.tag, info.types[id])
            end
        end
        assert.are.same({ 'same$1 nil', 'n$2 Nat', 'x$4 int53', 'BinOp Int', 'g$5 Int', 'h$6 Int', 'p$7 boolean' }, found)
    end)

    it('keeps Int and Nat out of exec signatures, and converts between integer types', function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param n Nat
            ---@param b boolean
            ---@return Int
            local function s(n, b) return n end
            ]]
            ---@param n Int --! E-type-mismatch
            local function f(n) end
            ---@param m integer
            ---@post s(m, true) >= 0
            ---@post s(true, true) >= 0 --! E-type-mismatch
            local function g(m) end
            ---@clavius end
            ]=]
        )
    end)

    it("infers a quantifier's bound variables as booleans or Ints from their uses", function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param n Nat
            ---@param b boolean
            ---@return Int
            local function s(n, b) return n end
            ]]
            ---@assert forall(function(i, b) return s(i, b) >= 0 end)
            ---@assert forall(function(p, q) return implies(p, q) or (p == (1 < 2)) end)
            ---@assert exists(function(i, j) return i + 1 == j end)
            ---@assert forall(function(k) local d = k * 2 return d == k + k end)
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' and res.names[id]:match '^[ibpqjkd]%$' then
                found[#found + 1] = ('%s %s'):format(res.names[id], info.types[id])
            end
        end
        assert.are.same(
            { 'b$3 boolean', 'i$5 Int', 'b$6 boolean', 'p$7 boolean', 'q$8 boolean', 'i$9 Int', 'j$10 Int', 'k$11 Int', 'd$12 Int' },
            found
        )
    end)

    it('types a bound variable compared with a boolean that its spelling alone does not show', function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param i Int
            ---@return boolean
            local function p(i) return i > 0 end
            ]]
            local t = true
            ---@param flag boolean
            ---@pre forall(function(z) return z == flag end)
            local function g(flag) end
            ---@assert forall(function(x) return x == p(1) end)
            ---@assert forall(function(y) return y == (1 < 2) end)
            ---@assert forall(function(w) return w ~= t end)
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' and res.names[id]:match '^[xyzw]%$' then
                found[#found + 1] = ('%s %s'):format(res.names[id]:sub(1, 1), info.types[id])
            end
        end
        assert.are.same({ 'z boolean', 'x boolean', 'y boolean', 'w boolean' }, found)
    end)

    it("infers through a body's locals and through `==` between bound variables", function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param i Int
            ---@return Int
            local function f(i) return i end
            ]]
            ---@assert forall(function(a) local d = a return f(d) >= f(d) end)
            ---@assert forall(function(x, y) return implies(x == y and x > 0, y > 0) end)
            ---@assert forall(function(u, v) return implies(u == v, v) end)
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local found = {}
        for id, n in ipairs(c.src.nodes) do
            if n.tag == 'Binder' and res.names[id]:match '^[axyuv]%$' then
                found[#found + 1] = ('%s %s'):format(res.names[id]:sub(1, 1), info.types[id])
            end
        end
        assert.are.same({ 'a Int', 'x Int', 'y Int', 'u boolean', 'v boolean' }, found)
    end)

    it("gives `choose` its bound variable's type, which a ghost local of an integer widens to Int", function()
        local c = driver.run_until(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param i Int
            ---@return Int
            local function f(i) return i end

            ---@param n Nat
            ---@return boolean
            local function big(n) return n > 10 end
            ]]
            --[[@ghost
                local w = choose(function(i) return f(i) > 0 end)
                local b = choose(function(x) return x end)
                local v = choose(big)
            ]]
            ---@clavius end
            ]=],
            1
        )
        assert.are.same({}, c.diags)
        local info = assert(c.info)
        local res = assert(c.res)
        local calls = {}
        local locals = {}
        for id, n in ipairs(c.src.nodes) do
            if res.prelude[id] == 'choose' then
                calls[#calls + 1] = info.types[id]
            elseif n.tag == 'Binder' and res.names[id]:match '^[wbv]%$' then
                locals[#locals + 1] = ('%s %s'):format(res.names[id]:sub(1, 1), info.types[id])
            end
        end
        assert.are.same({ 'Int', 'boolean', 'Nat' }, calls)
        -- a ghost local with an integer value is always an `Int`, however v would carry the fact it >= 0
        assert.are.same({ 'w Int', 'b boolean', 'v Int' }, locals)
    end)

    it("reports a bound variable that its uses don't type, and a body that isn't a boolean", function()
        markers.expect_diags(
            'types',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param i Int
            ---@return Int
            local function f(i) return i end
            ]]
            ---@assert forall(function(i, j) return f(i) > 0 end) --! E-unsupported-type
            ---@assert forall(function(a, b) return a == b end) --! E-unsupported-type E-unsupported-type
            ---@assert forall(function(i) return f(i) end) --! E-type-mismatch
            -- a use as a boolean wins, so the use as an integer is the error
            ---@assert forall(function(i) return f(i) > 0 and i end) --! E-type-mismatch
            -- `a == b` makes them one type, so `b`'s use as a boolean makes `a + 1` the error
            ---@assert forall(function(a, b) return implies(a == b and b, a + 1 > 0) end) --! E-type-mismatch
            ---@assert implies(1, true) --! E-unsupported-feature
            ---@assert forall(f) --! E-type-mismatch
            --[[@proof local z = choose(f) ]] --! E-type-mismatch
            ---@clavius end
            ]=]
        )
    end)
end)
