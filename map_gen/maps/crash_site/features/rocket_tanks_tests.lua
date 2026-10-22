-- DEMO for #1628: a module whose startup fails, on every Crash Site map. Not for merging.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'

Declare.module({'map_gen', 'maps', 'crash_site', 'features', 'rocket tanks'}, function()
    Declare.module_startup(function()
        error('demo: the test surface could not be created')
    end)

    Declare.test('demo: a test whose module failed to start', function()
        Assert.is_true(true)
    end)
end)
