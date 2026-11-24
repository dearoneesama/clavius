local driver = require 'clavius.driver'
local markers = require 'support.markers'

--- Resolves `text` and returns, for each Id in id order, its name and the unique name of its Binder, or
--- `global`.
--- @param text string
--- @return string[]
local function refs(text)
    local c = driver.run_until('resolve', text, 1)
    assert.are.same({}, c.diags)
    local res = assert(c.res)
    local out = {}
    for id, n in ipairs(c.src.nodes) do
        -- the shipped specs follow the file in the run's arena
        if n.tag == 'Id' and c.src.spans[id].file == c.file then
            local binder = res.decl[id]
            out[#out + 1] = ('%s %s'):format(n.name, binder and res.names[binder] or 'global')
        end
    end
    return out
end

describe('resolve', function()
    it('resolves each name to the nearest local before it', function()
        assert.are.same({ 'x x$1' }, refs 'local x = 1 local x = x')
        assert.are.same({ 'y global' }, refs 'do local y = 1 end local z = y')
        assert.are.same({ 'i global', 'i i$1' }, refs 'for i = i, 2 do local j = i end')
        assert.are.same({ 'i global', 'i global', 's s$1', 'i global' }, refs 'local s = 1 for i = i, i, s + i do end')
        assert.are.same({ 'k global', 'k k$1' }, refs 'for k in k do local j = k end')
        assert.are.same({ 'p p$2' }, refs 'local function f(p) return p end')
    end)

    it('lets a local function call itself, but not a function assigned to a local', function()
        assert.are.same({ 'f f$1' }, refs 'local function f() return f end')
        assert.are.same({ 'g global' }, refs 'local g = function() return g end')
    end)

    it("lets `until` see the locals of the loop's body", function()
        assert.are.same({ 'r r$1' }, refs 'repeat local r = 1 until r')
    end)

    it('treats a region as part of the enclosing scope', function()
        local text = [=[
            ---@clavius begin
            local x = 1
            ---@clavius end
            local y = x
        ]=]
        assert.are.same({ 'x x$1' }, refs(text))
    end)

    it('rejects unsupported kinds and operators', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local t = 1
            local a = 1 / 2 --! E-unsupported-feature
            local c = 2 ^ 2 --! E-unsupported-feature
            local d = 1 .. 2 --! E-unsupported-feature
            local e = #t --! E-unsupported-feature
            local f = {} --! E-unsupported-feature
            local g = function() end --! E-unsupported-feature
            for k in t do end --! E-unsupported-feature
            local k = ... --! E-unsupported-feature
            local l = t.x --! E-unsupported-feature
            return t --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
    end)

    it('reports only the outermost construct that it rejects', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            for k in y do local z = 1 / w end --! E-unsupported-feature
            local a = (1 / x) + 1 --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
    end)

    it('rejects unsupported forms', function()
        markers.expect_diags(
            'resolve',
            [=[
            local outer = 1
            ---@clavius begin
            local x, y = 1 --! E-unsupported-feature
            local z --! E-unsupported-feature
            x, y = 1 --! E-unsupported-feature
            x, x = 1, 2 --! E-unsupported-feature
            x = outer --! E-unsupported-feature
            outer = 1 --! E-unsupported-feature
            local a = assert --! E-unsupported-feature
            local b = assert(x) --! E-unsupported-feature
            assert() --! E-unsupported-feature
            assert(x, 'a', 'b') --! E-unsupported-feature
            assert(x, y) --! E-unsupported-feature
            error(x) --! E-unsupported-feature
            x:m() --! E-unsupported-feature
            local local_assert = 1
            local_assert(x) --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
    end)

    it('rejects every global but `assert` and `error`', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            print(1) --! E-unsupported-call
            local f = math.floor --! E-unsupported-call
            local s = string.len(1) --! E-unsupported-call
            pcall(1) --! E-banned-call
            debug.traceback() --! E-banned-call
            local g = _G --! E-banned-call
            local y = undefined + 1 --! E-banned-global
            undefined = 1 --! E-banned-global
            frob(1) --! E-banned-global
            ---@clavius end
            ]=]
        )
    end)

    it('bans goto and labels', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            goto done --! E-banned-goto
            ::done:: --! E-banned-goto
            ---@clavius end
            ]=]
        )
    end)

    it('rejects a local from another region', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local x = 1 + 1
            ---@clavius end
            ---@clavius begin
            local y = x --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
    end)

    it('lets marked code read constants: top-level literals that are never assigned', function()
        local c = markers.expect_diags(
            'resolve',
            [=[
            local MAX, NEG, FLAG = 10, -5, true
            local CHANGED = 1
            CHANGED = 2
            ---@clavius begin
            local a = MAX + NEG
            local b = FLAG
            local d = CHANGED --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
        local found = {}
        for b, value in pairs(assert(c.res).constants) do
            found[#found + 1] = ('%s %s'):format(c.src.nodes[b].name, c.src.nodes[value].tag)
        end
        table.sort(found)
        assert.are.same({ 'FLAG Literal', 'MAX Literal', 'NEG UnOp' }, found)
    end)

    it('resolves a contract over the parameters, and the value in a `---@post`', function()
        local text = [=[
            ---@clavius
            ---@param n integer
            ---@pre n > 0
            ---@post sum > n
            ---@return integer sum
            local function f(n)
                local sum = n + 1
                return sum
            end
            ---@clavius
            ---@post result
            ---@return boolean
            local function g()
                return true
            end
            ---@clavius
            ---@param result integer
            ---@post value > result
            ---@return integer value
            local function h(result)
                local value = result + 1
                local sum = value * 2
                local result = sum
                return result
            end
        ]=]
        assert.are.same({
            'n n$2',
            'sum sum$3',
            'n n$2',
            'n n$2',
            'sum sum$4',
            'result result$6',
            'value value$9',
            'result result$8',
            'result result$8',
            'value value$10',
            'sum sum$11',
            'result result$12',
        }, refs(text))
    end)

    it('rejects calls that functions in this version may not make', function()
        markers.expect_diags(
            'resolve',
            [=[
            local function unmarked(x) return x end
            ---@unsafe
            ---@param x integer
            local function trusted(x) return x end
            ---@unsafe
            local function swapped() end
            swapped = nil
            ---@clavius
            ---@param n integer
            local function f(n)
                local a = f(n)
                local b = unmarked(n) --! E-unsupported-feature
                local c = trusted(n, n) --! E-unsupported-feature
                local d = trusted(n)
                swapped() --! E-unsupported-feature
                local g = trusted --! E-unsupported-feature
                local function h() end --! E-unsupported-feature
                return a, b --! E-unsupported-feature
            end
            ---@clavius
            ---@param m integer
            ---@pre trusted(m) > 0
            --! E-unsupported-feature
            local function k(m) end
            ]=]
        )
    end)

    it('checks the directives of a function', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius
            ---@param y integer
            --! E-misplaced-directive
            ---@param x integer
            ---@param x integer
            --! E-misplaced-directive
            ---@return integer x
            --! E-misplaced-directive
            ---@mut x
            --! E-unsupported-directive
            local function f(x) return x end
            ---@clavius
            ---@unsafe
            --! E-misplaced-directive
            local function g() end
            -- the flags of trusted code sit on an `---@unsafe` function, never on a verified one
            ---@unsafe
            ---@no_callback
            ---@may_raise
            local function u() end
            ---@clavius
            ---@no_callback
            --! E-misplaced-directive
            ---@may_raise
            --! E-misplaced-directive
            local function v() end
            ---@clavius
            ---@return integer
            ---@return integer
            --! E-unsupported-feature
            local function h() return 1 end
            ---@clavius
            ---@param result integer
            ---@return integer
            --! E-misplaced-directive
            local function k(result) return result end
            ---@clavius
            ---@param n integer
            ---@decrease n, 1
            ---@decrease n
            --! E-misplaced-directive
            local function m(n) end
            ---@unsafe
            ---@param n integer
            ---@decrease n
            --! E-misplaced-directive
            local function u(n) end
            ]=]
        )
    end)

    it('resolves a measure over the parameters only', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius
            ---@param n integer
            ---@decrease n, result, k
            --! E-banned-global E-banned-global
            ---@return integer
            local function f(n)
                local k = n
                return k
            end
            ]=]
        )
    end)

    it('lets functions declared by a `local` without values call each other', function()
        local text = [=[
            local is_odd
            ---@clavius begin
            ---@param n integer
            local function is_even(n) return is_odd(n) end
            ---@param n integer
            function is_odd(n) return is_even(n) end
            local x = is_odd(1)
            ---@clavius end
        ]=]
        assert.are.same({
            'is_odd is_odd$1',
            'n n$3',
            'is_odd is_odd$1',
            'is_even is_even$2',
            'n n$4',
            'is_odd is_odd$1',
        }, refs(text))
    end)

    it('rejects forward-declared functions that may be called before they are defined', function()
        markers.expect_diags(
            'resolve',
            [=[
            local early
            ---@clavius
            ---@param n integer
            local function f(n)
                early(n) --! E-unsupported-feature
            end
            print(f)
            ---@clavius
            ---@param n integer
            function early(n) end

            local never
            local twice
            local late
            ---@clavius
            ---@param n integer
            local function g(n)
                never(n) --! E-unsupported-feature
                twice(n) --! E-unsupported-feature
                late(n)
            end
            ---@clavius
            ---@param n integer
            function twice(n) end
            ---@clavius
            ---@param n integer
            function late(n) end
            twice = nil
            ---@clavius begin
            local x --! E-unsupported-feature
            ---@clavius end
            ]=]
        )
    end)

    it("resolves a loop's annotations outside its body, and a numeric `for`'s with its variable", function()
        local text = [=[
            ---@clavius begin
            local n = 1
            ---@invariant n > 0
            ---@decrease n
            while n > 0 do local m = n end
            ---@invariant n > 0
            repeat local n = 2 until n > 1
            ---@invariant i > n
            for i = n, 2 do end
            ---@clavius end
        ]=]
        assert.are.same({
            'n n$1',
            'n n$1',
            'n n$1',
            'n n$1',
            'n n$1',
            'n n$3',
            'i i$4',
            'n n$1',
            'n n$1',
        }, refs(text))
    end)

    it("keeps a loop's body locals from its condition and annotations, but not from `until`", function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local n = 1
            ---@invariant m > 0
            --! E-banned-global
            ---@decrease m
            --! E-banned-global
            while m do --! E-banned-global
                local m = n
            end
            ---@invariant k > 0
            --! E-banned-global
            ---@decrease k
            --! E-banned-global
            repeat
                local k = n
            until k > 0
            ---@invariant j > 0
            --! E-banned-global
            ---@decrease i
            for i = 1, i do --! E-banned-global
                local j = i
            end
            ---@clavius end
            ]=]
        )
    end)

    it('rejects loop forms that do not verify', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local n = 3
            for i = 1, 2, n do end
            for i = 1, 2 do
                i = 2 --! E-unsupported-feature
            end
            ---@decrease n, n
            while n > 0 do n = n - 1 end
            ---@decrease n
            ---@decrease n
            --! E-misplaced-directive
            while n > 0 do n = n - 1 end
            ---@invariant f(n)
            --! E-unsupported-feature
            ---@decrease f(n)
            --! E-unsupported-feature
            while n > 0 do n = n - 1 end
            ---@clavius end
            ]=]
        )
    end)

    it('checks nothing outside regions', function()
        markers.expect_diags(
            'resolve',
            [=[
            local t = { 1 }
            print(#t, t[1] / 2, pcall(print), undefined)
            goto done
            ::done::
            ---@clavius begin
            local x = 1
            ---@clavius end
            print(x)
            ]=]
        )
    end)
    it('keeps exec code from ghost names, and ghost code from exec locals', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            local x = 1
            ---@ghost local g = x
            local y = g --! E-mode
            ---@ghost x = 2 --! E-mode
            ---@ghost g = g + x
            --[[@ghost
                local k = g
                g = k
            ]]
            local v = k --! E-mode
            --[[@proof local p = g ]]
            local z = p --! E-banned-global
            ---@ghost local assert = 1
            ---@ghost local math = 1
            assert(true) --! E-mode
            local w = math.floor(2) --! E-mode
            ---@clavius end
            ]=]
        )
    end)

    it('lets unmarked code see past ghost declarations', function()
        local text = [=[
            --[[@spec
            ---@return Int
            local function s() return 1 end
            ]]
            local t = s
        ]=]
        assert.are.same({ 's global' }, refs(text))
    end)

    it('lets each kind of code call only some kinds of functions', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            --[[@spec
            ---@param n Nat
            ---@return Nat
            local function s(n) return n end
            ]]
            --[[@lemma
            ---@param n Nat
            local function l(n) end
            ]]
            ---@param n integer
            ---@post result == s(n)
            ---@return integer
            local function f(n)
                local a = s(n) --! E-mode
                l(n) --! E-mode
                ---@proof l(s(n))
                return n
            end
            ---@param n integer
            ---@pre l(n)
            --! E-mode
            local function g(n) end
            --[[@proof f(1) ]] --! E-mode
            ---@clavius end
            ]=]
        )
    end)

    it('checks what blocks and spec functions hold', function()
        markers.expect_diags(
            'resolve',
            [=[
            --[[@spec
            local k = 1 --! E-mode
            ---@param n Nat
            ---@return Nat
            local function a(n)
                local m = n
                return m
            end
            ---@param n Nat
            ---@return Nat
            local function b(n) --! E-mode
                if n > 0 then return n end
            end
            ---@param n Nat
            ---@return Nat
            local function both(n)
                if n > 0 then
                    return n
                else
                    do
                        return 0
                    end
                end
            end
            ---@param n Nat
            ---@return Nat
            local function one(n) --! E-mode
                if n > 0 then
                    return n
                elseif n == 0 then
                    return 0
                else
                end
            end
            ---@param n Nat
            ---@pre n > 0
            --! E-misplaced-directive
            ---@return Nat
            local function c(n)
                assert(n > 0) --! E-mode
                return n
            end
            ]]
            --[[@lemma
            ---@unsafe
            --! E-misplaced-directive
            local function u() end
            ]]
            ]=]
        )
    end)

    it('checks what proof code holds, and where its control flow goes', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            --[[@lemma
            local function l() end
            ]]
            local x = 0
            ---@proof assert(x == 0) --! E-mode
            ---@ghost l() --! E-mode
            --[[@ghost
                local h = x
                l() --! E-mode
                h = h + 1
            ]]
            while x < 3 do
                --[[@proof break ]] --! E-mode
                --[[@proof while true do break end ]]
                x = x + 1
            end
            --[[@proof
                local function h() end --! E-mode
            ]]
            local function f()
                --[[@proof if true then return end ]] --! E-mode
            end
            ---@reveal_with_fuel l, 2
            --! E-misplaced-directive
            local function g() end
            ---@clavius end
            ]=]
        )
    end)

    it('lets only proof code call `assume`, with one condition', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@clavius begin
            --[[@lemma
            local function l()
                assume(false)
            end
            ]]
            local x = 0
            --[[@proof
                assume(x > 0)
                assume(x > 0, 'why') --! E-unsupported-feature
                local b = assume(x > 0) --! E-unsupported-feature
            ]]
            assume(x > 0) --! E-mode
            ---@clavius end
            ]=]
        )
    end)

    it('proves a function, lemma or region only in nonlinear arithmetic', function()
        markers.expect_diags(
            'resolve',
            [=[
            ---@proof_by nonlinear_arith
            ---@clavius begin
            ---@proof_by nonlinear_arith
            local function f() end
            ---@proof_by bit_vector
            --! E-unsupported-directive
            local function g() end
            ---@clavius end
            ---@proof_by bit_vector
            --! E-unsupported-directive
            ---@clavius begin
            local x = 1
            ---@clavius end
            ]=]
        )
    end)
end)
