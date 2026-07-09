local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-nobots',
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
    disabled_technologies = {
        'construction-robotics', 'logistic-robotics', 'logistic-system',
        'personal-roboport-equipment', 'personal-roboport-mk2-equipment',
        'worker-robots-storage-1', 'worker-robots-storage-2', 'worker-robots-storage-3',
        'worker-robots-speed-1', 'worker-robots-speed-2', 'worker-robots-speed-3',
        'worker-robots-speed-4', 'worker-robots-speed-5', 'worker-robots-speed-6'
    }
}

Info.set_info('Crashsite - No Bots', {
    extra = { '- Construction and logistic bots are disabled on this map.' }
})

return Scenario.init(config)
