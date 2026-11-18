local driver = require 'clavius.driver'

--- Runs the stages up to `effects` on `text` and returns, for each loop in id order, its kind and the
--- unique names of the locals it writes.
--- @param text string
--- @return string[]
local function writes(text)
    local c = driver.run_until('effects', text, 1)
    assert.are.same({}, c.diags)
    local res = assert(c.res)
    local effects = assert(c.effects)
    local out = {}
    for id, n in ipairs(c.src.nodes) do
        if n.tag == 'While' or n.tag == 'Repeat' or n.tag == 'Fornum' then
            local names = { n.tag }
            for _, w in ipairs(effects.writes[id] or {}) do
                names[#names + 1] = res.names[w.root]
            end
            out[#out + 1] = table.concat(names, ' ')
        end
    end
    return out
end

describe('effects', function()
    it('gives each loop the locals declared outside it that its body assigns', function()
        local text = [=[
            ---@clavius begin
            local x, z = 0, 0
            while x < 1 do
                local y = 0
                while y < 1 do
                    if z < 1 then
                        x = 1
                    end
                    y = 2
                end
            end
            ---@clavius end
        ]=]
        -- the inner loop comes first, since children have smaller ids
        assert.are.same({ 'While x$1 y$3', 'While x$1' }, writes(text))
    end)
end)
