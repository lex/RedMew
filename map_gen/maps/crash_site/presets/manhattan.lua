local b = require 'map_gen.shared.builders'
local MGSP = require 'resources.map_gen_settings'
local degrees = require 'utils.math'.degrees
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

-- Manhattan crops and rotates its picture, so it builds world_map/bounds itself and
-- only reuses the shared compositing tail.
local pic = require 'map_gen.data.presets.manhattan'
local world_map = b.picture(pic)
world_map = b.choose(b.rectangle(pic.width, pic.height - 4), world_map, b.empty_shape)

local x_offset, y_offset = 0, -400
world_map = b.translate(world_map, x_offset, y_offset)
world_map = b.rotate(world_map, degrees(-270))

local scale = 1.6
world_map = b.scale(world_map, scale)

local bounds = b.rectangle(pic.height * scale, pic.width * scale)
bounds = b.translate(bounds, y_offset * scale, -x_offset * scale)

local config = {
    scenario_name = 'crashsite-manhattan',
    map_gen_settings = {
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    grid_number_of_blocks = 33,
    mini_grid_number_of_blocks = 65,
    bounds_shape = bounds
}

Info.set_info('Crashsite Manhattan', { intro = '- A Manhattan map version of Crash Site.' })

return Info.composite(world_map, Scenario.init(config))
