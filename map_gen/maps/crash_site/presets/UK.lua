local MGSP = require 'resources.map_gen_settings'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local pic = require 'map_gen.data.presets.UK'
local world_map, bounds = Info.picture(pic, {
    x_offset = -50, y_offset = 50, scale = 3, width = 2000, height = 2000
})

local config = {
    scenario_name = 'crashsite-UK',
    map_gen_settings = {MGSP.starting_area_very_low, MGSP.ore_oil_none, MGSP.enemy_none, MGSP.cliff_none},
    grid_number_of_blocks = 17,
    mini_grid_number_of_blocks = 33,
    bounds_shape = bounds
}

Info.set_info('Crashsite UK', { intro = '- A UK map version of Crash Site.' })

return Info.composite(world_map, Scenario.init(config))
