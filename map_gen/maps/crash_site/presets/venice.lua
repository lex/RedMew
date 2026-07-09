local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local pic = require 'map_gen.data.presets.venice'
local world_map, bounds = Info.picture(pic, {
    x_offset = 0, y_offset = 180, scale = 0.75, width = 4000, height = 4000
})

local config = {
    scenario_name = 'crashsite-venice',
    map_gen_settings = {
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    grid_number_of_blocks = 15,
    mini_grid_number_of_blocks = 29,
    bounds_shape = bounds
}

Info.set_info('Crashsite Venice', { intro = '- A Venice map version of Crash Site.' })

return Info.composite(world_map, Scenario.init(config))
