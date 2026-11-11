-- Tests for Convergence: the lanes and how they merge, biters and robots walking them to the
-- core, towers shooting what they can reach, beacons, and upgrading and selling. Discovered when
-- the Convergence scenario runs.
--
-- A headless run has no players, so a player is stood in for by their game data alone (a player
-- index no real player has): their gold is what the tests watch.

local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Creeps = require 'map_gen.maps.convergence.creeps'
local Game = require 'map_gen.maps.convergence.game'
local Layout = require 'map_gen.maps.convergence.layout'
local RS = require 'map_gen.shared.redmew_surface'
local Settings = require 'map_gen.maps.convergence.settings'
local State = require 'map_gen.maps.convergence.state'
local Towers = require 'map_gen.maps.convergence.towers'

-- a stand-in player with gold, and their towers and the creeps cleared afterwards
local function stand_in(context, index, gold)
    local state = State.get()
    local data = { index = index, gold = gold or 0, kills = 0, spent = 0 }
    state.players[index] = data
    context:add_teardown(function()
        Creeps.clear()
        for _, tower in pairs(state.towers) do
            if tower.owner == index then
                Towers.remove(tower)
            end
        end
        state.players[index] = nil
        state.lives = Settings.lives
    end)
    return data
end

-- the first wave of each kind, so the tests read the kinds from the settings
local function first_wave(predicate)
    for i, wave in ipairs(Settings.waves) do
        if predicate(wave) then
            return i
        end
    end
end

local ground_wave = first_wave(function(w)
    return not w.air and not w.boss and not w.shielded and not w.regen
end)
local air_wave = first_wave(function(w)
    return w.air
end)
local shielded_wave = first_wave(function(w)
    return w.shielded and not w.air
end)

local function surface()
    return RS.get_surface()
end

-- a felt spot beside the path near the start of a seat's lane, for a tower of this size
local function felt_spot(seat, size)
    local start = Layout.corners(seat)[2]
    for dy = 0, 12 do
        for dx = -12, 12 do
            local x, y = math.floor(start.x) + dx + size / 2, math.floor(start.y) + dy + size / 2
            local box = { { x - size / 2, y - size / 2 }, { x + size / 2, y + size / 2 } }
            if Layout.can_build(seat, box, false) then
                return { x = x, y = y }
            end
        end
    end
end

-- waits for a seat's creeps to be gone, recording where each was off its path
local function walk(context, creeps, off_path)
    return context:wait_until(60 * 200, function()
        local walking = false
        for _, creep in pairs(creeps) do
            if creep.entity.valid then
                walking = true
                local p = creep.entity.position
                if not Layout.on_path(p.x, p.y) then
                    off_path[#off_path + 1] = string.format('%s at %.1f, %.1f (tick %d)', creep.entity.name, p.x, p.y, game.tick)
                end
            end
        end
        return not walking
    end, 'a creep is still on its way')
end

Declare.module({ 'map_gen', 'Convergence' }, function()
    Declare.module_startup(function()
        surface().request_to_generate_chunks({ 0, 0 }, 6)
        surface().force_generate_chunk_requests()
    end)

    Declare.test('every lane is path from its spawn to the core', function()
        for seat = 1, Layout.seats do
            -- Act
            local points = Layout.waypoints(seat, 1)

            -- Assert: path all the way, the spawn's marking included
            for _, point in ipairs(points) do
                local name = surface().get_tile(point.x, point.y).name
                Assert.is_true(name == Layout.tiles.path or name == Layout.tiles.spawn, 'seat ' .. seat .. ': the tile at ' .. point.x .. ', ' .. point.y .. ' is ' .. name)
            end
            Assert.equal('core', Layout.zone(points[#points].x, points[#points].y + 2), 'seat ' .. seat .. "'s lane ends at the core")
        end
    end)

    Declare.test('the lanes merge two by two', function()
        -- Act: the zone each lane leaves its own zone into, the half and the final one, by the
        -- corner where each joins the next
        local corners = {}
        for seat = 1, Layout.seats do
            corners[seat] = Layout.corners(seat)
        end

        -- Assert: pairs meet at corner 11, halves at 19, everyone at 27
        for seat = 1, Layout.seats do
            local pair = seat % 2 == 1 and seat + 1 or seat - 1
            Assert.table_equal(corners[pair][11], corners[seat][11], 'seat ' .. seat .. ' meets seat ' .. pair)
            Assert.table_equal(corners[1][27], corners[seat][27], 'seat ' .. seat .. ' reaches the final zone where seat 1 does')
        end
        Assert.table_equal(corners[1][19], corners[4][19], 'seats 1 and 4 share a half')
        Assert.is_true(corners[1][19].x ~= corners[5][19].x, 'seats 1 and 5 are in different halves')
    end)

    Declare.test('a biter nobody shoots keeps to its lane and costs a life at the core', function(context)
        -- Arrange
        stand_in(context, 1001)
        local creeps = {}
        local off_path = {}

        -- Act
        context:next(function()
            creeps[1] = Creeps.spawn(surface(), 3, ground_wave)
        end)
        walk(context, creeps, off_path):next(function()
            -- Assert
            Assert.equal(0, #off_path, 'times the biter was off the path, first ' .. tostring(off_path[1]))
            Assert.equal(Settings.lives - 1, State.get().lives, 'lives after the biter reached the core')
        end)
    end)

    Declare.test('a robot of an air wave flies its lane to the core', function(context)
        -- Arrange
        stand_in(context, 1002)
        local creeps = {}
        local off_path = {}

        -- Act
        context:next(function()
            creeps[1] = Creeps.spawn(surface(), 6, air_wave)
        end)
        walk(context, creeps, off_path):next(function()
            -- Assert
            Assert.equal(0, #off_path, 'times the robot was off the path, first ' .. tostring(off_path[1]))
            Assert.equal(Settings.lives - 1, State.get().lives, 'lives after the robot reached the core')
        end)
    end)

    Declare.test('a gun tower kills the biters walking past and its owner gets the bounty', function(context)
        -- Arrange: a gun tower raised to its top level beside lane 2
        local data = stand_in(context, 1003)
        local tower = Towers.create(surface(), 'gun', 1003, felt_spot(2, 2))
        Assert.is_true(tower ~= nil, 'the tower was built')
        tower.level = #Settings.lines.gun.levels
        local creeps = {}

        -- Act
        context:next(function()
            creeps[1] = Creeps.spawn(surface(), 2, ground_wave)
            creeps[2] = Creeps.spawn(surface(), 2, ground_wave)
        end):wait_until(60 * 30, function()
            return not creeps[1].entity.valid and not creeps[2].entity.valid
        end, 'the biters are still alive'):next(function()
            -- Assert
            Assert.equal(Settings.lives, State.get().lives, 'lives')
            Assert.equal(2 * Settings.waves[ground_wave].bounty, data.gold, 'gold from the two kills')
            Assert.equal(2, data.kills, 'kills')
        end)
    end)

    Declare.test('flak only hits the air', function(context)
        -- Arrange: top-level flak beside lane 4, a biter and a robot coming
        local data = stand_in(context, 1004)
        local tower = Towers.create(surface(), 'flak', 1004, felt_spot(4, 3))
        Assert.is_true(tower ~= nil, 'the tower was built')
        tower.level = #Settings.lines.flak.levels
        local creeps = {}

        -- Act
        context:next(function()
            creeps.ground = Creeps.spawn(surface(), 4, ground_wave)
            creeps.air = Creeps.spawn(surface(), 4, air_wave)
        end):wait_until(60 * 30, function()
            return not creeps.air.entity.valid
        end, 'the robot is still flying'):next(function()
            -- Assert
            Assert.equal(1, data.kills, 'kills: the robot')
            Assert.valid(creeps.ground.entity, 'the biter walks on')
            Assert.equal(creeps.ground.max_health, creeps.ground.health, "the biter's health")
        end)
    end)

    Declare.test("a trap burns biters on the path, but not a shielded wave's", function(context)
        -- Arrange: a top-level trap on lane 5's path, a short way in
        local data = stand_in(context, 1005)
        local point = Layout.waypoints(5, 1)[8]
        local tower = Towers.create(surface(), 'trap', 1005, point)
        Assert.is_true(tower ~= nil, 'the trap was placed')
        tower.level = #Settings.lines.trap.levels
        local creeps = {}

        -- Act
        context:next(function()
            creeps.plain = Creeps.spawn(surface(), 5, ground_wave)
            creeps.shielded = Creeps.spawn(surface(), 5, shielded_wave)
        end):wait_until(60 * 30, function()
            local p = creeps.shielded.entity.valid and creeps.shielded.entity.position
            return p and p.y > point.y + 10
        end, 'the shielded biter never got past the trap'):next(function()
            -- Assert
            Assert.is_true(not creeps.plain.entity.valid, 'the plain biter burned')
            Assert.equal(1, data.kills, 'kills')
            Assert.equal(creeps.shielded.max_health, creeps.shielded.health, "the shielded biter's health")
        end)
    end)

    Declare.test('a beacon makes the towers round it hit harder', function(context)
        -- Arrange
        stand_in(context, 1006)
        local gun = Towers.create(surface(), 'gun', 1006, felt_spot(7, 2))
        local far = Towers.create(surface(), 'gun', 1006, felt_spot(8, 2))

        -- Act
        local spot = gun.entity.position
        local beacon = Towers.create(surface(), 'beacon', 1006, surface().find_non_colliding_position('beacon', spot, 6, 1))

        -- Assert
        Assert.is_true(beacon ~= nil, 'the beacon was built')
        Assert.equal(Settings.lines.beacon.levels[1].aura, gun.aura, "the near tower's bonus")
        Assert.equal(0, far.aura, "the far tower's bonus")
    end)

    Declare.test('upgrading takes the gold and selling gives most of it back', function(context)
        -- Arrange
        local index = 1007
        local start = 10000
        local data = stand_in(context, index, start)
        local tower = Towers.create(surface(), 'laser', index, felt_spot(1, 2))
        data.selected = tower.id
        local levels = Settings.lines.laser.levels

        -- Act
        local upgraded = Game.upgrade(index)
        local level = tower.level
        local after_upgrade = data.gold
        local sold = Game.sell(index)

        -- Assert
        Assert.is_true(upgraded, 'upgraded')
        Assert.equal(2, level, 'level after the upgrade')
        Assert.equal(start - levels[2].cost, after_upgrade, 'gold after the upgrade')
        Assert.is_true(sold, 'sold')
        Assert.equal(after_upgrade + math.floor((levels[1].cost + levels[2].cost) * Settings.sell_share), data.gold, 'gold after selling')
        Assert.is_true(not tower.entity.valid, 'the tower is gone')
    end)
end)
