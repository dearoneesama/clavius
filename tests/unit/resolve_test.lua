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
        if n.tag == 'Id' then
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
            local b = 1 % 2 --! E-unsupported-feature
            local c = 2 ^ 2 --! E-unsupported-feature
            local d = 1 .. 2 --! E-unsupported-feature
            local e = #t --! E-unsupported-feature
            local f = {} --! E-unsupported-feature
            local g = function() end --! E-unsupported-feature
            local function h() end --! E-unsupported-feature
            while t < 2 do t = t + 1 end --! E-unsupported-feature
            repeat t = t + 1 until t > 2 --! E-unsupported-feature
            for i = 1, 2 do t = i end --! E-unsupported-feature
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
            while y do local z = 1 / w end --! E-unsupported-feature
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
            local x = 1
            ---@clavius end
            ---@clavius begin
            local y = x --! E-unsupported-feature
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
end)
