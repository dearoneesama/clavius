local markers = require 'support.markers'

describe('termination', function()
    it('needs a measure on every `while` and `repeat` loop in marked code', function()
        markers.expect_diags(
            'termination',
            [=[
            local n = 1
            while n > 0 do n = n - 1 end
            ---@unsafe
            local function g()
                while true do end
            end
            ---@clavius begin
            local m = 3
            while m > 0 do m = m - 1 end --! E-misplaced-directive
            repeat m = m + 1 until m > 5 --! E-misplaced-directive
            ---@decrease m
            while m > 0 do m = m - 1 end
            for i = 1, 3 do end
            ---@clavius end
            ---@clavius
            local function f()
                local k = 0
                while k < 3 do k = k + 1 end --! E-misplaced-directive
            end
            ]=]
        )
    end)
end)
