-- DEMO for #1628: a module whose startup fails, on Archipelago only. Not for merging.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'

Declare.module({'map_gen', 'maps', 'danger_ores', 'modules', 'archipelago'}, function()
    Declare.module_startup(function()
        error('demo: this startup fails on purpose')
    end)

    Declare.test('demo: a test in the module whose startup failed', function()
        Assert.is_true(true)
    end)
end)
