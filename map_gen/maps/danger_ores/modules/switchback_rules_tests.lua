-- In-game tests for Switchback's belt geometry (switchback_rules.lua), on the Switchback map: how
-- long a straight run is, where it ends, which belts curve, and that a bend keeps a line going
-- with no run too long. They run on belts laid out in a table, with no surface.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Rules = require 'map_gen.maps.danger_ores.modules.switchback_rules'

local N, E, S, W = 0, 4, 8, 12
local LIMIT = 3

-- adding 0 turns -0 (0 times a negative number, in Factorio's Lua) into 0, so it has the same key
local function key(x, y)
    return (x + 0) .. ',' .. (y + 0)
end

--- A world from {x, y, direction, kind} entries: kind 'belt' (the default), 'in' for an
-- underground entrance and 'out' for an exit.
local function grid(entries)
    local tiles = {}
    local function place(x, y, direction, kind)
        local piece
        if (kind or 'belt') == 'belt' then
            piece = Rules.belt(x, y, direction)
        else
            local dx, dy = Rules.vector(direction)
            piece = {belt = false, direction = direction, outputs = kind == 'out' and {{x + dx, y + dy}} or {}}
        end
        tiles[key(x, y)] = piece
    end
    for _, e in pairs(entries) do
        place(e[1], e[2], e[3], e[4])
    end
    local function world(x, y)
        return tiles[key(x, y)]
    end
    return world, place
end

--- Lays a belt the way a drag does, `count` tiles from (0, 0) along `direction`, bending to
-- `side` whenever a belt would make its run too long.
local function drag(direction, count, side)
    local world, place = grid({})
    local dx, dy = Rules.vector(direction)
    for i = 0, count - 1 do
        local x, y = i * dx, i * dy
        place(x, y, direction)
        if Rules.run_length(world, x, y, LIMIT) > LIMIT then
            local bend = Rules.bend(x, y, direction, side)
            place(x, y, bend.turn)
            for _, b in pairs(bend.belts) do
                place(b[1], b[2], b[3])
            end
        end
    end
    return world
end

--- Follows the belts from (x, y) to (tx, ty). @return whether the items get there
local function reaches(world, x, y, tx, ty)
    for _ = 1, 1000 do
        if x == tx and y == ty then
            return true
        end
        local piece = world(x, y)
        if not piece or #piece.outputs == 0 then
            return false
        end
        x, y = piece.outputs[1][1], piece.outputs[1][2]
    end
    return false
end

Declare.module({'map_gen', 'danger ores', 'switchback', 'rules'}, function()
    Declare.test('four belts in a row are a run of four, counted from any of them', function()
        -- Arrange
        local world = grid({{0, 0, E}, {1, 0, E}, {2, 0, E}, {3, 0, E}})

        for x = 0, 3 do
            -- Act
            local length = Rules.run_length(world, x, 0)

            -- Assert
            Assert.equal(4, length, 'run through belt ' .. x)
        end
    end)

    Declare.test('a turn ends a run, and the turning belt is not part of it', function()
        -- Arrange: three belts east, then a turn north
        local world = grid({{0, 0, E}, {1, 0, E}, {2, 0, E}, {3, 0, N}, {3, -1, N}})

        -- Act
        local before = Rules.run_length(world, 0, 0)
        local turn_shape = Rules.shape(world, 3, 0)
        local after = Rules.run_length(world, 3, -1)

        -- Assert
        Assert.equal(3, before, 'run before the turn')
        Assert.equal('curved', turn_shape, 'shape of the turning belt')
        Assert.equal(1, after, 'run after the turn')
    end)

    Declare.test('a belt curves only when fed from one side and not from behind', function()
        local cases = {
            {'fed from nowhere', {{0, 0, E}}, 'straight'},
            {'fed from one side', {{0, 0, E}, {0, -1, S}}, 'curved'},
            {'fed from both sides', {{0, 0, E}, {0, -1, S}, {0, 1, N}}, 'straight'},
            {'fed from behind and a side', {{0, 0, E}, {-1, 0, E}, {0, -1, S}}, 'straight'},
            {'facing a belt head on', {{0, 0, E}, {-1, 0, W}, {0, -1, S}}, 'curved'},
            {'fed from behind by an underground exit', {{0, 0, E}, {-1, 0, E, 'out'}, {0, -1, S}}, 'straight'},
            {'behind an underground entrance, which feeds nothing', {{0, 0, E}, {-1, 0, E, 'in'}, {0, -1, S}}, 'curved'}
        }
        for _, case in pairs(cases) do
            -- Arrange
            local world = grid(case[2])

            -- Act
            local shape = Rules.shape(world, 0, 0)

            -- Assert
            Assert.equal(case[3], shape, 'a belt ' .. case[1])
        end
    end)

    Declare.test('an underground belt ends a run, and the belts after it start a new one', function()
        -- Arrange: three belts, an underground pair, three belts
        local world = grid({
            {0, 0, E}, {1, 0, E}, {2, 0, E},
            {3, 0, E, 'in'}, {6, 0, E, 'out'},
            {7, 0, E}, {8, 0, E}, {9, 0, E}
        })

        -- Act
        local before = Rules.run_length(world, 0, 0)
        local after = Rules.run_length(world, 7, 0)

        -- Assert
        Assert.equal(3, before, 'run before the underground')
        Assert.equal(3, after, 'run after the underground')
    end)

    Declare.test('a dragged line bends so that no run is too long and the items still get to its end', function()
        local count = 25
        for _, direction in pairs({N, E, S, W}) do
            for _, side in pairs({-1, 1}) do
                -- Act
                local world = drag(direction, count, side)

                -- Assert
                local dx, dy = Rules.vector(direction)
                local what = 'a line dragged in direction ' .. direction .. ', bent to side ' .. side
                for x = -2 * count, 2 * count do
                    for y = -2 * count, 2 * count do
                        local length = Rules.run_length(world, x, y)
                        Assert.is_true(length <= LIMIT, what .. ' has a run of ' .. length .. ' at ' .. x .. ',' .. y)
                    end
                end
                local ex, ey = (count - 1) * dx, (count - 1) * dy
                Assert.is_true(reaches(world, 0, 0, ex, ey), what .. ' does not carry items from its start to ' .. ex .. ',' .. ey)
            end
        end
    end)
end)
