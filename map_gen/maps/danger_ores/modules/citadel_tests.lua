-- DEMO for #1628: a test that errors at run time, on Citadel only. Not for merging.
local Declare = require 'utils.test.declare'

Declare.module({'map_gen', 'maps', 'danger_ores', 'modules', 'citadel'}, function()
    Declare.test('demo: a test that errors', function()
        local gate = nil
        return gate.position
    end)
end)
