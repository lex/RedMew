--[[
    Paints the crash site's ground from a tile palette instead of relying on map gen autoplace.

    Space Age's planet tiles (fulgoran-*, lowland-*, wetland-*, ...) have autoplace probability
    expressions written against that planet's own named noise expressions. Forcing them through
    autoplace_settings on a hand-rolled map gen is unreliable, so the planet crash site maps let
    the map generator produce whatever it likes and then overwrite every tile here. The result is
    pure Lua and therefore behaves identically regardless of which planet is involved.

    A shape returns `true` for "plain ground, leave the map gen tile alone". Those are the tiles
    this replaces. Anything that already named a tile - outpost concrete, the spawn platform,
    water put down deliberately by a preset - is passed through untouched.
]]
local Perlin = require 'map_gen.shared.perlin_noise'

local floor = math.floor
local noise = Perlin.noise

local Public = {}

--- Build a terrain painter.
-- @param config <table>
--   ground <array<string>> tile names, ordered; low noise picks the first, high the last
--   scale <number> noise scale, smaller values give larger patches (default 1/64)
--   seed <number> noise seed (default 0)
--   contrast <number> spread of the ground palette. Perlin output clusters around 0 and rarely
--     reaches +-1, so without this the first and last tiles never appear (default 1.5)
--   wet <table> optional low-lying tiles, usually shallow water
--     tiles <array<string>> tile names to use below the threshold
--     threshold <number> noise value under which `wet.tiles` are used, -1..1 (default -0.35)
--     scale <number> noise scale for the wet mask (default 1/96)
--     seed <number> noise seed for the wet mask (default seed + 1000)
--     depth_gain <number> how fast the palette walks from the first tile to the last as the
--       noise gets further past the threshold. Perlin rarely reaches +-1, so a gain above 1 is
--       needed for the last entries to ever appear at all (default 2.5)
-- @return <function> takes a shape and returns a shape
function Public.painter(config)
    local ground = config.ground
    local ground_count = #ground
    local scale = config.scale or 1 / 64
    local seed = config.seed or 0
    local contrast = config.contrast or 1.5

    local wet = config.wet
    local wet_tiles, wet_count, wet_threshold, wet_scale, wet_seed, wet_gain, wet_range
    if wet then
        wet_tiles = wet.tiles
        wet_count = #wet_tiles
        wet_threshold = wet.threshold or -0.35
        wet_scale = wet.scale or 1 / 96
        wet_seed = wet.seed or (seed + 1000)
        wet_gain = wet.depth_gain or 2.5
        -- Distance from the threshold to the theoretical noise floor, used to normalise depth.
        wet_range = 1 + wet_threshold
    end

    --- Map a 0..1 position along a palette onto an array index.
    local function pick(list, count, fraction)
        local index = floor(fraction * count) + 1
        if index < 1 then
            return list[1]
        elseif index > count then
            return list[count]
        end
        return list[index]
    end

    local function tile_at(x, y)
        if wet then
            local wetness = noise(x * wet_scale, y * wet_scale, wet_seed)
            if wetness < wet_threshold then
                -- Re-use the wetness value for variety within the water so we do not pay for a
                -- second noise lookup per tile. 0 at the shoreline, 1 at the deepest point.
                local depth = ((wet_threshold - wetness) / wet_range) * wet_gain
                return pick(wet_tiles, wet_count, depth)
            end
        end

        return pick(ground, ground_count, 0.5 + noise(x * scale, y * scale, seed) * contrast * 0.5)
    end

    return function(shape)
        return function(x, y, world)
            local tile = shape(x, y, world)

            if tile == true then
                return tile_at(world.x, world.y)
            end

            if type(tile) == 'table' and tile.tile == true then
                tile.tile = tile_at(world.x, world.y)
            end

            return tile
        end
    end
end

return Public
