local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-only-construction-bots',
    map_gen_settings = {
        MGSP.grass_only,
        MGSP.enable_water,
        MGSP.water_very_low,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    disabled_outpost_types = { 'mini_t1_robotics_factory' },
    disabled_technologies = { 'logistic-robotics', 'logistic-system' }
}

Info.set_info('Crashsite - Only Construction Bots', {
    extra = { '- Only construction bots are available on this map.' }
})

return Scenario.init(config)
