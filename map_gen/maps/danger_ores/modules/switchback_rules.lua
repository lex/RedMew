-- The geometry of Switchback's belt rule, with no Factorio API in it: which belts are straight,
-- how long a straight run is, and the bend that turns a run aside.
--
-- A world is a function `world(x, y)` returning the piece on that tile, or nil:
--   { belt = true for a transport belt (false for undergrounds, splitters...),
--     direction = 0 (north), 4 (east), 8 (south) or 12 (west),
--     outputs = { {x, y}, ... } the tiles it moves items onto }
-- Only transport belts count toward a run. Anything else ends it, though it still feeds the
-- belts it outputs onto, which decides their shape.
local Public = {}

local vectors = {
    [0] = {0, -1},
    [4] = {1, 0},
    [8] = {0, 1},
    [12] = {-1, 0}
}

--- @return the unit vector of a direction
function Public.vector(direction)
    local v = vectors[direction]
    return v[1], v[2]
end

--- @return the direction turned a quarter to the left (-1) or to the right (1)
function Public.turn(direction, side)
    return (direction + side * 4) % 16
end

local function outputs_onto(piece, x, y)
    for _, o in pairs(piece.outputs) do
        if o[1] == x and o[2] == y then
            return true
        end
    end
    return false
end

--- A belt is straight when something feeds it from behind, or when it is fed from the side by
-- none or by both sides; fed from one side only, it curves.
-- @return 'straight', 'curved', or nil when the tile holds no transport belt
function Public.shape(world, x, y)
    local piece = world(x, y)
    if not (piece and piece.belt) then
        return nil
    end
    local direction = piece.direction
    local dx, dy = Public.vector(direction)

    local behind = world(x - dx, y - dy)
    if behind and behind.direction == direction and outputs_onto(behind, x, y) then
        return 'straight'
    end

    local sides = 0
    for _, side in pairs({-1, 1}) do
        local sx, sy = Public.vector(Public.turn(direction, side))
        local feeder = world(x + sx, y + sy)
        if feeder and feeder.direction == Public.turn(direction, -side) and outputs_onto(feeder, x, y) then
            sides = sides + 1
        end
    end
    return sides == 1 and 'curved' or 'straight'
end

local function straight_belt(world, x, y, direction)
    local piece = world(x, y)
    return piece and piece.belt and piece.direction == direction and Public.shape(world, x, y) == 'straight'
end

--- The straight belts in a row through (x, y): each feeding the next, all straight. Stops
-- counting past `cap`, so a long run costs no more than a short one.
-- @return the number of belts, 0 when the tile holds no straight belt
function Public.run_length(world, x, y, cap)
    local piece = world(x, y)
    if not (piece and piece.belt and Public.shape(world, x, y) == 'straight') then
        return 0
    end
    cap = cap or math.huge
    local direction = piece.direction
    local dx, dy = Public.vector(direction)
    local count = 1

    -- backwards: a straight belt behind, facing the same way, feeds this one
    local bx, by = x - dx, y - dy
    while count <= cap and straight_belt(world, bx, by, direction) do
        count = count + 1
        bx, by = bx - dx, by - dy
    end

    -- forwards: a belt ahead facing the same way is fed from behind, so it is straight
    local fx, fy = x + dx, y + dy
    while count <= cap and straight_belt(world, fx, fy, direction) do
        count = count + 1
        fx, fy = fx + dx, fy + dy
    end

    return count
end

--- @return the first of `tiles` ({x, y}) on a straight run longer than `limit`, or nil
function Public.too_long(world, tiles, limit)
    for _, t in pairs(tiles) do
        if Public.run_length(world, t[1], t[2], limit) > limit then
            return t
        end
    end
    return nil
end

--- The bend that takes a straight belt at (x, y), facing `direction`, out to one side and back:
-- the belt turns to that side, a belt beside it carries on, and a third turns back onto the
-- tile after it, where the line goes on.
--
--     → → → ↑ → ↓ → → →  becomes, seen from above, for an east-facing line bent to the left:
--
--           → ↓
--     → → → ↑ → → →
--
-- @param side -1 for left, 1 for right
-- @return { turn = the belt's new direction, belts = { {x, y, direction}, {x, y, direction} } }
function Public.bend(x, y, direction, side)
    local out = Public.turn(direction, side)
    local dx, dy = Public.vector(direction)
    local sx, sy = Public.vector(out)
    return {
        turn = out,
        belts = {
            {x + sx, y + sy, direction},
            {x + sx + dx, y + sy + dy, Public.turn(out, 2)}
        }
    }
end

--- A piece for a transport belt on (x, y) facing `direction`.
function Public.belt(x, y, direction)
    local dx, dy = Public.vector(direction)
    return {belt = true, direction = direction, outputs = {{x + dx, y + dy}}}
end

return Public
