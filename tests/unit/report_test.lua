local arena = require 'clavius.ir.arena'
local diag = require 'clavius.ir.diag'
local driver = require 'clavius.driver'
local messages = require 'clavius.report.messages'
local stringx = require 'pl.stringx'

describe('report.messages', function()
    it('formats failing obligations in source order', function()
        local text = stringx.dedent [=[
            ---@clavius begin
            local x = 1
            --[[é你]] local y = x +
                1
            if y > 1 then error() end assert(y > x, 'm')
            ---@clavius end
        ]=]
        local c = driver.run_until('validate', text, 1)
        assert.are.same({}, c.diags)
        local prog = assert(c.prog)
        -- columns count code points: `é` and `日` take five bytes and two columns
        assert.are.same({
            '3:20: range: x + 1 may leave ±2^53 [O1]',
            '5:15: unreachable: this `error` may be reached [O2]',
            '5:27: assert: this assertion may fail [O3]',
        }, messages.failures({ 3, 2, 1 }, prog.obligations, c.src, c.files))
    end)

    it('quotes the condition of a failing contract clause', function()
        local text = stringx.dedent [=[
            ---@clavius
            ---@param n integer
            ---@pre n > 0
            ---@post n > 1
            local function f(n) end
            ---@clavius begin
            f(0)
            ---@clavius end
        ]=]
        local c = driver.run_until('validate', text, 1)
        assert.are.same({}, c.diags)
        local prog = assert(c.prog)
        assert.are.same({
            '5:7: post: the function may return here without satisfying its postcondition `n > 1` [O1]',
            '7:1: pre: this call may not satisfy its precondition `n > 0` [O2]',
        }, messages.failures({ 1, 2 }, prog.obligations, c.src, c.files))
    end)

    it('names the divisor and the inexact remainder, and quotes a library spec from its own file', function()
        local text = stringx.dedent [=[
            ---@clavius begin
            local z = 0
            local a = 5 % z
            ---@clavius end
            ---@clavius begin
            local b = math.floor(5 / 0)
            ---@clavius end
            ---@clavius begin
            local c = 9007199254740992 % -3
            ---@clavius end
            ---@clavius begin
            host.f(-1)
            ---@clavius end
        ]=]
        local meta = stringx.dedent [=[
            ---@meta
            ---@extern
            ---@param n integer
            ---@pre   n >= 0
            function host.f(n) end
        ]=]
        local c = driver.run_until('validate', text, 1, { { name = 'host.lua', text = meta } })
        assert.are.same({}, c.diags)
        local prog = assert(c.prog)
        local ids = {}
        for id, o in ipairs(prog.obligations) do
            if o.kind == 'div_zero' or o.kind == 'mod_range' or o.kind == 'pre' then
                ids[#ids + 1] = id
            end
        end
        assert.are.same({
            '3:11: div_zero: the divisor of `5 % z` may be 0 [O1]',
            '3:11: mod_range: `5 % z` may be computed inexactly, since the dividend minus the remainder may leave ±2^53 [O2]',
            '6:11: div_zero: the divisor of `math.floor(5 / 0)` may be 0 [O3]',
            '9:11: div_zero: the divisor of `9007199254740992 % -3` may be 0 [O4]',
            '9:11: mod_range: `9007199254740992 % -3` may be computed inexactly, since the dividend minus the remainder may leave ±2^53 [O5]',
            '12:1: pre: this call may not satisfy its precondition `n >= 0` [O6]',
        }, messages.failures(ids, prog.obligations, c.src, c.files))
    end)

    it("quotes a loop's invariant and measure, and names its counter, bound and step", function()
        local text = stringx.dedent [=[
            ---@clavius begin
            local i = 0
            ---@invariant i  >=  0
            ---@decrease 3 - i,  0
            while i < 3 do i = i + 1 end
            for k = 1, 2 do end
            for k = 1, 2, i do end
            ---@clavius end
        ]=]
        local c = driver.run_until('validate', text, 1)
        assert.are.same({}, c.diags)
        local prog = assert(c.prog)
        local kinds = {}
        for id, o in ipairs(prog.obligations) do
            if o.kind ~= 'range' then
                kinds[#kinds + 1] = id
            end
        end
        assert.are.same({
            '5:1: decrease: an iteration may start with the measure `3 - i, 0` negative, or may not decrease it [O4]',
            '5:1: invariant_entry: the loop invariant `i >= 0` may not hold when the loop starts [O1]',
            '5:1: invariant_preserved: the loop invariant `i >= 0` may not hold again after an iteration [O3]',
            "6:1: for_bound: this loop's limit plus its step may leave ±2^53 [O5]",
            "6:1: invariant_entry: the loop counter's range may not hold when the loop starts [O6]",
            "6:1: invariant_preserved: the loop counter's range may not hold again after an iteration [O7]",
            "7:1: for_bound: this loop's limit plus its step may leave ±2^53 [O9]",
            "7:1: for_step: this loop's step may be 0 [O8]",
            "7:1: invariant_entry: the loop counter's range may not hold when the loop starts [O10]",
            "7:1: invariant_preserved: the loop counter's range may not hold again after an iteration [O11]",
        }, messages.failures(kinds, prog.obligations, c.src, c.files))
    end)

    it("quotes the callee's measure at a call in a cycle of recursive calls", function()
        local text = stringx.dedent [=[
            local g
            ---@clavius begin
            ---@param n integer
            ---@decrease n,  1
            local function f(n) g(n) end
            ---@param n integer
            ---@decrease n - 1, 0
            function g(n) f(n) end
            ---@clavius end
        ]=]
        local c = driver.run_until('validate', text, 1)
        assert.are.same({}, c.diags)
        local prog = assert(c.prog)
        assert.are.same({
            '5:21: decrease: this call may not decrease the measure `n - 1, 0`, or the measure may be negative on entry [O1]',
            '8:15: decrease: this call may not decrease the measure `n, 1`, or the measure may be negative on entry [O2]',
        }, messages.failures({ 1, 2 }, prog.obligations, c.src, c.files))
    end)

    it('orders diagnostics by position, then code', function()
        local text = 'abc\ndef\n'
        local diags = {
            diag.at_span('E-banned-goto', arena.span(1, 5, 7), {}),
            diag.at_span('E-type-mismatch', arena.span(1, 2, 2), { 'int53', 'boolean' }),
            diag.at_span('E-banned-call', arena.span(1, 2, 3), { 'pcall' }),
        }
        assert.are.same({
            "1:2: E-banned-call: `pcall` can't be used in verified code",
            '1:2: E-type-mismatch: expected int53, found boolean',
            "2:1: E-banned-goto: `goto` and labels can't be used in verified code",
        }, messages.diags(diags, {}, text))
    end)

    it('prints names from the program as they are', function()
        local d = diag.at_span('E-banned-global', arena.span(1, 1, 1), { 'call' })
        assert.are.equal("1:1: E-banned-global: the global `call` can't be used in verified code", messages.diag(d, {}, 'x'))
    end)

    it('names features in plain words', function()
        local d = diag.at_span('E-unsupported-feature', arena.span(1, 1, 1), { 'Forin' })
        local expected = "1:1: E-unsupported-feature: a generic `for` loop isn't supported in this version; leave this code unmarked"
        assert.are.equal(expected, messages.diag(d, {}, 'x'))
    end)
end)
