local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-desert',
    map_gen_settings = {
        MGSP.sand_only,
        MGSP.enable_water,
        MGSP.water_very_low,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none,
        {
            property_expression_names = {
                ['control-setting:moisture:bias'] = '-0.500000'
            },
            autoplace_controls = {
                trees = {
                    frequency = 6,
                    richness = 1,
                    size = 0.1666666716337204
                }
            }
        }
    }
}

Info.set_info('Crashsite Desert', {
    description = 'A desert version of Crash Site. Capture outposts and defend against the biters.',
    intro = 'A desert version of Crash Site, with sandy terrain, scattered oases and few trees.'
})

return Scenario.init(config)
