-- DEMO for #1628: a deliberately failing assertion, on Rivers only. Not for merging.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'

Declare.module({'map_gen', 'maps', 'danger_ores', 'modules', 'rivers'}, function()
    Declare.test('demo: an assertion that fails', function()
        local rivers = 2
        Assert.equal(3, rivers, 'rivers flowing out from spawn')
    end)

    Declare.test('demo: a test that passes', function()
        Assert.equal(2, 1 + 1)
    end)
end)
