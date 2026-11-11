-- Where everything is. Eight lanes start along the top of the map, one for each seat, and merge
-- like a tournament bracket: two into one in the four pair zones, two into one again in the two
-- half zones, and the last two in the final zone, which ends at the core (a rocket silo).
--
-- Each lane's top is its seat's own zone: only that player builds there. Everything below is
-- shared. Towers go on the felt beside the path; traps go on the path itself.

local floor = math.floor
local abs = math.abs
local min = math.min
local max = math.max

local Public = {}

Public.seats = 8

Public.tiles = {
    felt = 'green-refined-concrete',
    own = 'cyan-refined-concrete',
    path = 'refined-concrete',
    spawn = 'red-refined-concrete',
    core = 'black-refined-concrete',
    edge = 'black-refined-concrete'
}

local lane_pitch = 44
local half_width = 1.5

-- the x a seat's lane starts at, and the x its pair, half and the final zone are centred on
local function seat_x(seat)
    return (seat - 4.5) * lane_pitch
end

local function pair_x(seat)
    local pair = math.ceil(seat / 2)
    return (pair - 2.5) * 2 * lane_pitch
end

local function half_x(seat)
    return seat <= 4 and -2 * lane_pitch or 2 * lane_pitch
end

-- the zones, as { x1, y1, x2, y2 } (tiles; x2 and y2 not included)
local own_top, own_bottom = -152, -86
local pair_bottom = -26
local half_bottom = 40
local final_bottom = 104
Public.core = { x = 0, y = 110 }
Public.plaza = { x = 0, y = 124 }

--- The corners of a seat's path, from its spawn to the core.
function Public.corners(seat)
    local c, p, h = seat_x(seat), pair_x(seat), half_x(seat)
    local points = {
        -- the seat's own zone
        { c - 14, own_top + 1 },
        { c - 14, -140 },
        { c + 14, -140 },
        { c + 14, -126 },
        { c - 14, -126 },
        { c - 14, -112 },
        { c + 14, -112 },
        { c + 14, -98 },
        { c, -98 },
        -- into the pair zone, meeting the other lane of the pair
        { c, -80 },
        { p, -80 },
        { p, -70 },
        { p - 30, -70 },
        { p - 30, -56 },
        { p + 30, -56 },
        { p + 30, -42 },
        { p, -42 },
        -- into the half zone, meeting the other pair
        { p, -20 },
        { h, -20 },
        { h, -8 },
        { h - 34, -8 },
        { h - 34, 12 },
        { h + 34, 12 },
        { h + 34, 26 },
        { h, 26 },
        -- into the final zone, meeting the other half
        { h, 46 },
        { 0, 46 },
        { 0, 56 },
        { -40, 56 },
        { -40, 74 },
        { 40, 74 },
        { 40, 90 },
        { 0, 90 },
        { 0, Public.core.y - 6 }
    }
    local result = {}
    for i, point in ipairs(points) do
        -- tile centres, so a 3 wide path covers whole tiles
        result[i] = { x = point[1] + 0.5, y = point[2] + 0.5 }
    end
    return result
end

--- Points every `hop` tiles along a seat's path, the last being the end by the core.
function Public.waypoints(seat, hop)
    local corners = Public.corners(seat)
    local points = {}
    for i = 1, #corners - 1 do
        local a, b = corners[i], corners[i + 1]
        local length = max(abs(b.x - a.x), abs(b.y - a.y))
        local steps = max(1, math.ceil(length / hop))
        for step = 0, steps - 1 do
            local t = step / steps
            points[#points + 1] = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
        end
    end
    points[#points + 1] = corners[#corners]
    return points
end

function Public.spawn_position(seat)
    return Public.corners(seat)[1]
end

-- Every path tile, worked out once: tile key -> true.
local path_tiles = {}
local function key(x, y)
    return (x + 0) .. ',' .. (y + 0)
end
for seat = 1, Public.seats do
    local corners = Public.corners(seat)
    for i = 1, #corners - 1 do
        local a, b = corners[i], corners[i + 1]
        for x = floor(min(a.x, b.x) - half_width + 0.5), floor(max(a.x, b.x) + half_width - 0.5) do
            for y = floor(min(a.y, b.y) - half_width + 0.5), floor(max(a.y, b.y) + half_width - 0.5) do
                path_tiles[key(x, y)] = true
            end
        end
    end
end

--- Is the tile at x, y (any point in it) on a path.
function Public.on_path(x, y)
    return path_tiles[key(floor(x), floor(y))] == true
end

--- Which zone a point is in: the seat number for a seat's own zone, 'shared' for the zones
--- below, 'core' around the core, or nil outside the map.
function Public.zone(x, y)
    if y >= own_top and y < own_bottom then
        for seat = 1, Public.seats do
            local c = seat_x(seat)
            if x >= c - 20 and x < c + 20 then
                return seat
            end
        end
        return nil
    end
    if y >= own_bottom and y < pair_bottom then
        for seat = 1, Public.seats, 2 do
            local p = pair_x(seat)
            if x >= p - 42 and x < p + 42 then
                return 'shared'
            end
        end
        return nil
    end
    if y >= pair_bottom and y < half_bottom then
        if abs(x) < 4 * lane_pitch - 4 then
            return 'shared'
        end
        return nil
    end
    if y >= half_bottom and y < final_bottom then
        if abs(x) < 2 * lane_pitch + 4 then
            return 'shared'
        end
        return nil
    end
    if y >= final_bottom and y < Public.plaza.y + 8 and abs(x) < 24 then
        return 'core'
    end
    return nil
end

--- The map: a shape function for map_gen/shared/generate.lua (x and y are a tile's centre).
function Public.shape(x, y)
    local zone = Public.zone(x, y)
    if zone == nil then
        -- a rim round the zones
        for dx = -1, 1 do
            for dy = -1, 1 do
                if Public.zone(x + dx, y + dy) ~= nil then
                    return Public.tiles.edge
                end
            end
        end
        return false
    end
    if Public.on_path(x, y) then
        local spawn = false
        for seat = 1, Public.seats do
            local s = Public.spawn_position(seat)
            if abs(x - s.x) < 2 and abs(y - s.y) < 4 then
                spawn = true
            end
        end
        return spawn and Public.tiles.spawn or Public.tiles.path
    end
    if zone == 'core' then
        return Public.tiles.core
    end
    if type(zone) == 'number' then
        return Public.tiles.own
    end
    return Public.tiles.felt
end

--- Can a player in this seat (nil for none) build on every tile of this box: felt in their own
--- zone or a shared one, or path for a trap.
---@param seat integer?
---@param box BoundingBox
---@param on_path boolean true for a trap, which goes on the path
function Public.can_build(seat, box, on_path)
    local left_top = box.left_top or box[1]
    local right_bottom = box.right_bottom or box[2]
    local x1, y1 = left_top.x or left_top[1], left_top.y or left_top[2]
    local x2, y2 = right_bottom.x or right_bottom[1], right_bottom.y or right_bottom[2]
    for tx = floor(x1), math.ceil(x2) - 1 do
        for ty = floor(y1), math.ceil(y2) - 1 do
            local zone = Public.zone(tx + 0.5, ty + 0.5)
            if zone == nil or zone == 'core' then
                return false
            end
            if type(zone) == 'number' and zone ~= seat then
                return false
            end
            if Public.on_path(tx + 0.5, ty + 0.5) ~= on_path then
                return false
            end
        end
    end
    return true
end

--- Where a seat's player starts: by the top of their own zone.
function Public.seat_position(seat)
    return { x = seat_x(seat) + 6, y = own_top + 4 }
end

--- The area the map covers, for generating it.
function Public.area()
    return { { -4 * lane_pitch - 4, own_top - 4 }, { 4 * lane_pitch + 4, Public.plaza.y + 12 } }
end

return Public
