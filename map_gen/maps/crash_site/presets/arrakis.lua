require 'map_gen.maps.crash_site.features.sandworms'

local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-arrakis',
    map_gen_settings = {
        MGSP.sand_only,
        MGSP.water_none,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.tree_none,
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

Info.set_info('Crashsite Arrakis', {
    description = 'Capture outposts and defend against the biters. Even drier than desert, sandworms roam the desert and will attack roboports on sight.',
    intro = {
        '- Arrakis is even drier than crash site Desert.',
        '- Sandworms are attracted to the vibration caused by roboports and will spawn intermittently to neutralise this threat to their peace.',
        '- Cars have repair beams.'
    }
})

return Scenario.init(config)
