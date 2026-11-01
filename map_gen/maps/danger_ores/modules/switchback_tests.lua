-- In-game tests for Switchback's belt rule (switchback.lua), on the Switchback map, on a scratch
-- surface: the rules read belts as the game shapes them, a belt making a straight run too long is
-- taken back, undergrounds end a run, a turn into a run that's too long is undone, and a belt
-- straightened by a removal is taken up. With blueprints banned, what is built from a blueprint
-- in the hand is removed.
--
-- Builds are raised the way Factorio raises them. A robot build is "built" by a stand-in
-- construction robot whose cargo captures the refund. Bending a belt built by hand needs a real
-- player, so those tests are in a module of their own that headless runs skip.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Helper = require 'utils.test.helper'
local EventFactory = require 'utils.test.event_factory'
local DOC = require 'map_gen.maps.danger_ores.configuration'
local Rules = require 'map_gen.maps.danger_ores.modules.switchback_rules'
local Switchback = require 'map_gen.maps.danger_ores.modules.switchback'

local N, E, S = 0, 4, 8
local BELT = 'transport-belt'
local AREA = {{-30, -30}, {30, 30}}

local function build(surface, name, x, y, direction, extra)
    local spec = {name = name, position = {x + 0.5, y + 0.5}, direction = direction, force = 'player'}
    for k, v in pairs(extra or {}) do
        spec[k] = v
    end
    local entity = surface.create_entity(spec)
    Assert.valid(entity, 'the test ' .. name .. ' at ' .. x .. ',' .. y .. ' was not built')
    return entity
end

local function line(surface, x, y, count)
    local belts = {}
    for i = 0, count - 1 do
        belts[#belts + 1] = build(surface, BELT, x + i, y, E)
    end
    return belts
end

local function clear(surface)
    for _, entity in pairs(surface.find_entities_filtered({area = AREA})) do
        if entity.valid and entity.type ~= 'character' then
            entity.destroy()
        end
    end
end

local function shape_of(entity)
    return entity.belt_shape == 'straight' and 'straight' or 'curved'
end

Declare.module({'map_gen', 'danger ores', 'switchback'}, function()
    local surface, robot

    Declare.module_startup(function(context)
        surface = Helper.create_test_surface(context)
        context:next(function()
            robot = surface.create_entity({name = 'construction-robot', position = {-20, -20}, force = 'player'})
        end)
    end)

    Declare.module_teardown(function()
        if surface and surface.valid then
            game.delete_surface(surface)
        end
    end)

    -- Raises the robot build event for `entity`. @return what the robot got back, if anything
    local function robot_builds(entity)
        local refunded
        local fake_robot = Helper.fake_lua_object(robot, {
            valid = true,
            logistic_network = {cells = {{owner = {name = 'roboport'}}}},
            get_inventory = function()
                return {
                    insert = function(stack)
                        refunded = stack
                        return stack.count or 1
                    end
                }
            end
        })
        EventFactory.raise({name = defines.events.on_robot_built_entity, tick = game.tick, robot = fake_robot, entity = entity})
        return refunded
    end

    Declare.test('the rules read belts as the game shapes them', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange: a belt facing east at each case's (x, 0), with what feeds it
        local cases = {
            {'fed from nowhere', 0, function() end},
            {'fed from one side', 4, function(x)
                build(surface, BELT, x, -1, S)
            end},
            {'fed from both sides', 8, function(x)
                build(surface, BELT, x, -1, S)
                build(surface, BELT, x, 1, N)
            end},
            {'fed from behind and a side', 12, function(x)
                build(surface, BELT, x - 1, 0, E)
                build(surface, BELT, x, -1, S)
            end},
            {'fed from behind by an underground exit and from a side', 16, function(x)
                build(surface, 'underground-belt', x - 1, 0, E, {type = 'output'})
                build(surface, BELT, x, -1, S)
            end},
            {'fed from a side by an underground exit', 20, function(x)
                build(surface, 'underground-belt', x, -1, S, {type = 'output'})
            end},
            {'fed from a side by a splitter', 24, function(x)
                -- a splitter facing south over (x, -1) and (x + 1, -1)
                surface.create_entity({name = 'splitter', position = {x + 1, -0.5}, direction = S, force = 'player'})
            end},
            {'fed from behind by a splitter and from a side', 28, function(x)
                -- a splitter facing east over (x - 1, -1) and (x - 1, 0)
                surface.create_entity({name = 'splitter', position = {x - 0.5, 0}, direction = E, force = 'player'})
                build(surface, BELT, x, -1, S)
            end}
        }
        local belts = {}
        for i, case in pairs(cases) do
            belts[i] = build(surface, BELT, case[2], 0, E)
            case[3](case[2])
        end

        for i, case in pairs(cases) do
            -- Act
            local shape = Rules.shape(Switchback.world(surface), case[2], 0)

            -- Assert
            Assert.equal(shape_of(belts[i]), shape, 'a belt ' .. case[1])
        end
    end)

    Declare.test('a robot can build a third straight belt but not a fourth', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange
        line(surface, 0, 0, 2)
        local third = build(surface, BELT, 2, 0, E)
        local refunded_third = robot_builds(third)
        local fourth = build(surface, BELT, 3, 0, E)

        -- Act
        local refunded = robot_builds(fourth)

        -- Assert
        Assert.is_true(third.valid and refunded_third == nil, 'the third belt in a row was taken back')
        Assert.is_true(not fourth.valid, 'the fourth belt in a row is still there')
        Assert.is_true(refunded ~= nil, 'the fourth belt was not handed back')
        Assert.equal(BELT, refunded.name, 'item handed back')
    end)

    Declare.test('a belt joining two runs into one that is too long is taken back', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange: two belts, a gap, two belts
        line(surface, 0, 0, 2)
        line(surface, 3, 0, 2)
        local gap = build(surface, BELT, 2, 0, E)

        -- Act
        robot_builds(gap)

        -- Assert
        Assert.is_true(not gap.valid, 'the belt joining two runs into five is still there')
    end)

    Declare.test('underground belts end a run', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange: three belts, an underground pair, three belts
        line(surface, 0, 0, 3)
        build(surface, 'underground-belt', 3, 0, E, {type = 'input'})
        build(surface, 'underground-belt', 6, 0, E, {type = 'output'})
        line(surface, 7, 0, 2)
        local last = build(surface, BELT, 9, 0, E)

        -- Act
        local refunded = robot_builds(last)

        -- Assert
        Assert.is_true(last.valid and refunded == nil, 'the third belt after an underground pair was taken back')
    end)

    Declare.test('turning a belt into a run that is too long is undone', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange: three belts, then one turning north
        line(surface, 0, 0, 3)
        local turn = build(surface, BELT, 3, 0, N)

        -- Act: turn it east, in line with the others
        turn.rotate()
        EventFactory.raise({name = defines.events.on_player_rotated_entity, tick = game.tick, entity = turn, previous_direction = N})

        -- Assert
        Assert.equal(N, turn.direction, 'direction of the belt turned in line')
    end)

    Declare.test('removing the belt that curved another takes up the belt it straightens', function(context)
        context:add_teardown(function()
            clear(surface)
        end)

        -- Arrange: a belt curved by one feeding it from the side, then three straight belts
        local curved = build(surface, BELT, 0, 0, E)
        local feeder = build(surface, BELT, 0, -1, S)
        local rest = line(surface, 1, 0, 3)
        Assert.equal('curved', shape_of(curved), 'shape of the belt fed from the side')
        local near = {area = {{-3, -3}, {3, 3}}, name = 'item-on-ground'}
        local before = surface.count_entities_filtered(near)

        -- Act
        EventFactory.raise({name = defines.events.on_robot_mined_entity, tick = game.tick, entity = feeder})
        feeder.destroy()

        context:timeout(2, function()
            -- Assert
            Assert.is_true(not curved.valid, 'the belt straightened into a run of four is still there')
            for i, belt in pairs(rest) do
                Assert.is_true(belt.valid, 'belt ' .. i .. ' of the run after it was taken up')
            end
            Assert.equal(1, surface.count_entities_filtered(near) - before, 'belts dropped where it was')
        end)
    end)
end)

Declare.module({'map_gen', 'danger ores', 'switchback', 'by hand'}, function()
    Declare.tags('skip-headless')

    local surface, teardown

    Declare.module_startup(function(context)
        teardown = Helper.startup_test_surface(context)
        context:next(function()
            surface = context.player.surface
        end)
    end)

    Declare.module_teardown(function()
        teardown()
    end)

    local function hand_builds(player, entity)
        EventFactory.raise({name = defines.events.on_built_entity, tick = game.tick, entity = entity, player_index = player.index})
    end

    local function set_belts(context, player, count)
        local inventory = player.get_main_inventory()
        inventory.clear()
        player.clear_cursor()
        if count > 0 then
            inventory.insert({name = BELT, count = count})
        end
        context:add_teardown(function()
            inventory.clear()
            clear(surface)
        end)
    end

    Declare.test('a fourth belt built by hand bends round, with two belts from the inventory', function(context)
        -- Arrange
        local player = context.player
        set_belts(context, player, 10)
        line(surface, 0, 5, 3)
        local fourth = build(surface, BELT, 3, 5, E)

        -- Act
        hand_builds(player, fourth)
        local next_belt = build(surface, BELT, 4, 5, E)
        hand_builds(player, next_belt)

        -- Assert
        Assert.is_true(fourth.valid, 'the fourth belt was taken away rather than bent')
        Assert.is_true(fourth.belt_shape ~= 'straight', 'the fourth belt is still straight')
        local beside = surface.find_entities_filtered({position = {3.5, 4.5}, name = BELT})[1]
        local back = surface.find_entities_filtered({position = {4.5, 4.5}, name = BELT})[1]
        Assert.is_true(beside ~= nil and beside.direction == E, 'no belt beside the bend carrying on east')
        Assert.is_true(back ~= nil and back.direction == S, 'no belt turning back into the line')
        Assert.is_true(next_belt.valid and next_belt.belt_shape ~= 'straight', 'the belt after the bend is not fed from the bend')
        Assert.equal(8, player.get_item_count(BELT), 'belts left in the inventory')
    end)

    Declare.test('without belts to spare, a fourth belt built by hand is handed back', function(context)
        -- Arrange
        local player = context.player
        set_belts(context, player, 1)
        line(surface, 0, 5, 3)
        local fourth = build(surface, BELT, 3, 5, E)

        -- Act
        hand_builds(player, fourth)

        -- Assert
        Assert.is_true(not fourth.valid, 'the fourth belt is still there')
        Assert.equal(2, player.get_item_count(BELT), 'belts in the inventory: the one there and the one handed back')
    end)

    Declare.test('with no room either side, a fourth belt built by hand is handed back', function(context)
        -- Arrange
        local player = context.player
        set_belts(context, player, 10)
        line(surface, 0, 5, 3)
        build(surface, 'iron-chest', 3, 4)
        build(surface, 'iron-chest', 3, 6)
        local fourth = build(surface, BELT, 3, 5, E)

        -- Act
        hand_builds(player, fourth)

        -- Assert
        Assert.is_true(not fourth.valid, 'the fourth belt is still there')
        Assert.equal(11, player.get_item_count(BELT), 'belts in the inventory')
    end)

    Declare.test('a fourth ghost placed by hand bends round with ghosts', function(context)
        -- Arrange
        local player = context.player
        set_belts(context, player, 0)
        line(surface, 0, 5, 3)
        local ghost = build(surface, 'entity-ghost', 3, 5, E, {inner_name = BELT})

        -- Act
        hand_builds(player, ghost)

        -- Assert
        Assert.is_true(ghost.valid, 'the fourth ghost was taken away rather than bent')
        Assert.equal(N, ghost.direction, 'direction of the fourth ghost')
        local ghosts = surface.find_entities_filtered({area = {{3, 4}, {5, 5}}, ghost_name = BELT})
        Assert.equal(2, #ghosts, 'ghosts beside the bend')
    end)

    if DOC.switchback.no_blueprints then
        Declare.test('what a player builds from a blueprint in their hand is removed', function(context)
            -- Arrange: a blueprint of a chest in the player's hand
            local player = context.player
            set_belts(context, player, 0)
            context:add_teardown(function()
                player.clear_cursor()
            end)
            local cursor = player.cursor_stack
            cursor.set_stack({name = 'blueprint'})
            cursor.set_blueprint_entities({{entity_number = 1, name = 'iron-chest', position = {0.5, 0.5}}})
            local area = {{2, 6}, {12, 12}}

            -- Act
            player.build_from_cursor({position = {6.5, 8.5}})

            -- Assert
            local ghosts = surface.count_entities_filtered({area = area, ghost_name = 'iron-chest'})
            local chests = surface.count_entities_filtered({area = area, name = 'iron-chest'})
            Assert.equal(0, ghosts + chests, 'chests and ghosts of chests built from the blueprint')
        end)

        Declare.test('what a player builds from their hand without a blueprint stays', function(context)
            -- Arrange
            local player = context.player
            set_belts(context, player, 0)
            local chest = build(surface, 'iron-chest', 6, 8)

            -- Act
            hand_builds(player, chest)

            -- Assert
            Assert.is_true(chest.valid, 'the chest built by hand was removed')
        end)
    end
end)
