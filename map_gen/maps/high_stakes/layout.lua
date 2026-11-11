-- Where everything is: eight plots, four north and four south of a hall in the middle. Each plot
-- is one player's: biters enter at its far end and walk a long path to the vault by the hall.
-- The path weaves: four rows across the plot, then three columns back through them, so a tower
-- on the felt between them sees each biter go by several times.
--
-- A plot has its own coordinates: x from 0 to plot_width across, y from 0 at the far end to
-- plot_height at the hall. North plots lie as they are; south plots are mirrored top to bottom,
-- so their far end is south.

local floor = math.floor
local abs = math.abs

local Public = {}

local plot_width = 44
local plot_height = 62
local gap = 4
local pitch = plot_width + gap
local hall_half = 8
local columns = 4

Public.plot_width = plot_width
Public.plot_height = plot_height
Public.hall_half = hall_half

Public.tiles = {
    felt = 'green-refined-concrete',
    path = 'refined-concrete',
    hall = 'red-refined-concrete',
    edge = 'black-refined-concrete',
    vault = 'yellow-refined-concrete'
}

-- the path's corners, in plot coordinates: biters walk from the first to the last
local path = {
    { 4.5, 0.5 },
    -- the rows
    { 4.5, 6.5 },
    { 36.5, 6.5 },
    { 36.5, 18.5 },
    { 4.5, 18.5 },
    { 4.5, 30.5 },
    { 36.5, 30.5 },
    { 36.5, 42.5 },
    { 4.5, 42.5 },
    -- the columns
    { 4.5, 50.5 },
    { 12.5, 50.5 },
    { 12.5, 2.5 },
    { 20.5, 2.5 },
    { 20.5, 50.5 },
    { 28.5, 50.5 },
    { 28.5, 2.5 },
    -- and round the side to the vault
    { 40.5, 2.5 },
    { 40.5, 54.5 },
    { 22.5, 54.5 }
}
Public.path = path
local path_half_width = 1.5

-- the vault sits at the path's end
local vault = { 22.5, 58.5 }

-- a plot's left edge and whether it is mirrored
local function plot_origin(seat)
    local column = (seat - 1) % columns
    local south = seat > columns
    local left = -pitch * columns / 2 + gap / 2 + column * pitch
    return left, south
end

--- World position of a point in a seat's plot.
function Public.to_world(seat, x, y)
    local left, south = plot_origin(seat)
    if south then
        return { x = left + x, y = hall_half + plot_height - y }
    end
    return { x = left + x, y = -hall_half - plot_height + y }
end

--- The seat whose plot this world position is in, and the position in plot coordinates.
---@return integer? seat
---@return number? x
---@return number? y
function Public.to_plot(position)
    local px, py = position.x, position.y
    local south
    local y
    if py < -hall_half and py >= -hall_half - plot_height then
        south = false
        y = py + hall_half + plot_height
    elseif py > hall_half and py <= hall_half + plot_height then
        south = true
        y = hall_half + plot_height - py
    else
        return nil
    end
    local offset = px + pitch * columns / 2 - gap / 2
    local column = floor(offset / pitch)
    if column < 0 or column >= columns then
        return nil
    end
    local x = offset - column * pitch
    if x < 0 or x >= plot_width then
        return nil
    end
    return column + 1 + (south and columns or 0), x, y
end

local function on_path(x, y)
    for i = 1, #path - 1 do
        local a, b = path[i], path[i + 1]
        local x1, x2 = math.min(a[1], b[1]), math.max(a[1], b[1])
        local y1, y2 = math.min(a[2], b[2]), math.max(a[2], b[2])
        if x >= x1 - path_half_width and x <= x2 + path_half_width and y >= y1 - path_half_width and y <= y2 + path_half_width then
            return true
        end
    end
    return false
end

local function in_vault(x, y)
    return abs(x - vault[1]) <= 2 and abs(y - vault[2]) <= 2
end

--- What a tile in plot coordinates is: 'path', 'vault', 'felt' or nil outside the plot.
function Public.plot_tile(x, y)
    if x < 0 or x >= plot_width or y < 0 or y >= plot_height then
        return nil
    end
    if on_path(x, y) then
        return 'path'
    end
    if in_vault(x, y) then
        return 'vault'
    end
    return 'felt'
end

--- The map: a shape function for map_gen/shared/generate.lua (x and y are a tile's centre).
function Public.shape(x, y)
    local seat, px, py = Public.to_plot({ x = x, y = y })
    if seat then
        return Public.tiles[Public.plot_tile(px, py)]
    end
    local width = pitch * columns / 2
    if abs(x) < width and abs(y) < hall_half then
        return Public.tiles.hall
    end
    -- a rim around the plots and the hall
    if abs(x) < width + 1 and abs(y) < hall_half + plot_height + 1 then
        return Public.tiles.edge
    end
    return false
end

--- The corners biters walk through in a seat's plot, as world positions.
function Public.waypoints(seat)
    local points = {}
    for i, point in ipairs(path) do
        points[i] = Public.to_world(seat, point[1], point[2])
    end
    return points
end

function Public.vault_position(seat)
    return Public.to_world(seat, vault[1], vault[2])
end

--- Can a tower with this bounding box (world coordinates) stand in the seat's plot: every tile
--- it covers is the seat's felt.
---@param seat integer
---@param box BoundingBox
function Public.is_buildable(seat, box)
    local left_top = box.left_top or box[1]
    local right_bottom = box.right_bottom or box[2]
    local x1, y1 = left_top.x or left_top[1], left_top.y or left_top[2]
    local x2, y2 = right_bottom.x or right_bottom[1], right_bottom.y or right_bottom[2]
    for tx = floor(x1), math.ceil(x2) - 1 do
        for ty = floor(y1), math.ceil(y2) - 1 do
            local tile_seat, px, py = Public.to_plot({ x = tx + 0.5, y = ty + 0.5 })
            if tile_seat ~= seat or Public.plot_tile(px, py) ~= 'felt' then
                return false
            end
        end
    end
    return true
end

-- points every tile along the path, in plot coordinates
local path_points = {}
for i = 1, #path - 1 do
    local a, b = path[i], path[i + 1]
    local length = abs(b[1] - a[1]) + abs(b[2] - a[2])
    for step = 0, length - 1 do
        local t = step / length
        path_points[#path_points + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
    end
end

-- spots for a tower of a size and range, in plot coordinates, best first; the same in every plot
local spot_cache = {}

local function plot_spots(width, height, range)
    local key = width .. 'x' .. height .. ':' .. range
    local spots = spot_cache[key]
    if spots then
        return spots
    end
    spots = {}
    local half_w, half_h = width / 2, height / 2
    local range_squared = range * range
    for y = 0, plot_height - height do
        for x = 0, plot_width - width do
            local felt = true
            for tx = x, x + width - 1 do
                for ty = y, y + height - 1 do
                    if Public.plot_tile(tx + 0.5, ty + 0.5) ~= 'felt' then
                        felt = false
                        break
                    end
                end
                if not felt then
                    break
                end
            end
            if felt then
                local px, py = x + half_w, y + half_h
                local covered = 0
                for _, point in ipairs(path_points) do
                    local dx, dy = point[1] - px, point[2] - py
                    if dx * dx + dy * dy <= range_squared then
                        covered = covered + 1
                    end
                end
                spots[#spots + 1] = { px, py, covered }
            end
        end
    end
    table.sort(spots, function(a, b)
        if a[3] ~= b[3] then
            return a[3] > b[3]
        end
        if a[2] ~= b[2] then
            return a[2] < b[2]
        end
        return a[1] < b[1]
    end)
    spot_cache[key] = spots
    return spots
end

--- Felt spots in a seat's plot for a tower of this size (in tiles) and range, the ones that see
--- the most path first: where a tower nobody placed goes. Each is the tower's centre, on the tile
--- grid.
function Public.best_spots(seat, width, height, range)
    local result = {}
    for i, spot in ipairs(plot_spots(width, height, range)) do
        result[i] = Public.to_world(seat, spot[1], spot[2])
    end
    return result
end

--- The area every plot and the hall cover, for charting and generating it.
function Public.area()
    local width = pitch * columns / 2 + 2
    local height = hall_half + plot_height + 2
    return { { -width, -height }, { width, height } }
end

return Public
