local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-raining-bullets',
    map_gen_settings = {
        MGSP.grass_only,
        MGSP.enable_water,
        MGSP.water_very_low,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    disabled_technologies = {
        'laser', 'personal-laser-defense-equipment', 'discharge-defense-equipment',
        'laser-turret',
        'laser-shooting-speed-1', 'laser-shooting-speed-2', 'laser-shooting-speed-3',
        'laser-shooting-speed-4', 'laser-shooting-speed-5', 'laser-shooting-speed-6',
        'laser-shooting-speed-7',
        'laser-weapons-damage-1', 'laser-weapons-damage-2', 'laser-weapons-damage-3',
        'laser-weapons-damage-4', 'laser-weapons-damage-5', 'laser-weapons-damage-6',
        'laser-weapons-damage-7',
        'distractor', 'destroyer'
    }
}

Info.set_info('Crashsite - Raining Bullets', {
    extra = { '- Laser and other energy based weapon technology has been disabled.' }
})

return Scenario.init(config)
