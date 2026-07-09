-- Shared helpers for crash-site presets. Every preset sets the same map description and
-- the same core "how this scenario works" info lines, and the picture-based presets
-- (Venice, World, UK, Manhattan) composite a picture over the crash-site map with an
-- identical function. This module holds both once.
local b = require 'map_gen.shared.builders'
local ScenarioInfo = require 'features.gui.info'

local type = type
local water_tiles = b.water_tiles
local path_tiles = b.path_tiles

local Public = {}

local DEFAULT_DESCRIPTION = 'Capture outposts and defend against the biters.'

-- The core scenario-explainer lines shared by every crash-site map.
local CORE_INFO = {
    '- Outposts have enemy turrets defending them.',
    '- Outposts have loot and provide a steady stream of resources.',
    '- Outpost markets to purchase items and outpost upgrades.',
    '- Capturing outposts increases evolution.',
    '- Reduced damage by all player weapons, turrets, and ammo.',
    '- Biters have more health and deal more damage.',
    '- Biters and spitters spawn on death of entities.'
}

-- Normalize a string / array / nil into an array of lines.
local function as_lines(v)
    if v == nil then
        return {}
    elseif type(v) == 'string' then
        return { v }
    end
    return v
end

-- Set a crash-site preset's GUI info: map name, description and the extra-info panel.
-- opts.description overrides the shared default; opts.intro is a line (or array of lines)
-- prepended before the core lines (the "A Venice map version of Crash Site." style);
-- opts.extra is a line (or array) appended after the core (map-specific notes).
function Public.set_info(name, opts)
    opts = opts or {}
    ScenarioInfo.set_map_name(name)
    ScenarioInfo.set_map_description(opts.description or DEFAULT_DESCRIPTION)

    local lines = {}
    for _, line in ipairs(as_lines(opts.intro)) do
        lines[#lines + 1] = line
    end
    for _, line in ipairs(CORE_INFO) do
        lines[#lines + 1] = line
    end
    for _, line in ipairs(as_lines(opts.extra)) do
        lines[#lines + 1] = line
    end
    ScenarioInfo.add_map_extra_info('\n    ' .. table.concat(lines, '\n    ') .. '\n    ')
end

local function get_tile_name(tile)
    if type(tile) == 'table' then
        return tile.tile
    else
        return tile
    end
end

-- Build the world_map and bounds for the common picture presets: translate the picture
-- by (x_offset, y_offset), scale it, and bound it with a scaled rectangle. transform:
-- {x_offset, y_offset, scale, width, height} (width/height are the pre-scale size).
-- Returns world_map, bounds. Presets whose picture needs cropping/rotation (e.g.
-- Manhattan) build their own world_map/bounds and just call composite().
function Public.picture(picture, transform)
    local x_offset = transform.x_offset or 0
    local y_offset = transform.y_offset or 0
    local scale = transform.scale or 1

    local world_map = b.picture(picture)
    world_map = b.translate(world_map, x_offset, y_offset)
    world_map = b.scale(world_map, scale)

    local bounds = b.rectangle(transform.width * scale, transform.height * scale)
    bounds = b.translate(bounds, x_offset * scale, y_offset * scale)

    return world_map, bounds
end

-- Composite a picture over a crash-site map: the picture supplies the world terrain,
-- the crash-site map (from Scenario.init) supplies outposts/paths on top. Returns the
-- map function. Mirrors the tail every picture preset carried verbatim.
function Public.composite(world_map, crashsite)
    return function(x, y, world)
        local tile = world_map(x, y, world)
        if not tile then
            return tile
        end

        local world_tile_name = get_tile_name(tile)
        if not world_tile_name or water_tiles[world_tile_name] then
            return tile
        end

        local crashsite_tile = crashsite(x, y, world)
        local crashsite_tile_name = get_tile_name(crashsite_tile)
        if path_tiles[crashsite_tile_name] then
            return crashsite_tile
        end

        if type(crashsite_tile) == 'table' then
            crashsite_tile.tile = world_tile_name
            return crashsite_tile
        end

        return tile
    end
end

return Public
