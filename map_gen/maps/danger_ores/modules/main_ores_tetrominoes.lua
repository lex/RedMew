local b = require 'map_gen.shared.builders'
local Layout = require 'map_gen.maps.danger_ores.modules.tetromino_layout'
local palette = require 'map_gen.maps.danger_ores.config.tetromino_shapes'

local floor = math.floor

local CHUNK_SIZE = 32
local SUPER_TILE = 32 -- in chunks; the layout repeats every SUPER_TILE chunks (~1 km)

return function(config)
    local main_ores = config.main_ores

    return function(tile_builder, ore_builder, spawn_shape, water_shape, random_gen)
        local shapes = {}
        for _, ore_data in ipairs(main_ores) do
            local land = tile_builder(ore_data.tiles)
            local ratios = ore_data.ratios
            local weighted = b.prepare_weighted_array(ratios)
            local ore = ore_builder(ore_data.name, ore_data.start, ratios, weighted)
            shapes[#shapes + 1] = b.apply_entity(land, ore)
        end

        local ore_grid = Layout.generate {
            size = SUPER_TILE,
            palette = palette,
            num_ores = #shapes,
            random = random_gen,
        }

        local function tetrominoes(x, y, world)
            local cx = floor(x / CHUNK_SIZE) % SUPER_TILE
            local cy = floor(y / CHUNK_SIZE) % SUPER_TILE
            local index = ore_grid[cx][cy]
            return shapes[index](x, y, world)
        end

        return b.any { spawn_shape, water_shape, tetrominoes }
    end
end
