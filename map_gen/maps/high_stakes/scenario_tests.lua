-- Tests for the High Stakes table: the plots' paths, biters walking them to the vaults, towers
-- shooting them, and towers placed for players. Discovered when the High Stakes scenario runs.
--
-- A headless run has no players, so a seated player is stood in for by their seat data alone
-- (a player index no real player has): the chips are what the tests watch.

local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Cards = require 'map_gen.maps.high_stakes.cards'
local Game = require 'map_gen.maps.high_stakes.game'
local Layout = require 'map_gen.maps.high_stakes.layout'
local RS = require 'map_gen.shared.redmew_surface'
local Settings = require 'map_gen.maps.high_stakes.settings'
local State = require 'map_gen.maps.high_stakes.state'
local Towers = require 'map_gen.maps.high_stakes.towers'
local Waves = require 'map_gen.maps.high_stakes.waves'

-- Seats a stand-in player and clears their plot afterwards.
local function sit(context, seat)
    local state = State.get()
    local index = 1000 + seat
    local data = { index = index, seat = seat, chips = Settings.starting_chips, tips = 0, folds_left = Settings.max_folds, wins = 0, selected = {}, out = false }
    state.seats[seat] = index
    state.players[index] = data
    state.pending[seat] = {}
    context:add_teardown(function()
        Waves.clear(seat)
        Towers.remove(seat)
        state.seats[seat] = nil
        state.players[index] = nil
        state.pending[seat] = nil
    end)
    return data
end

local function creeps_in(seat)
    return Waves.creeps_by_seat()[seat] or {}
end

Declare.module({ 'map_gen', 'High Stakes', 'table' }, function()
    Declare.module_startup(function()
        local surface = RS.get_surface()
        surface.request_to_generate_chunks({ 0, 0 }, 3)
        surface.force_generate_chunk_requests()
    end)

    Declare.test('every plot has a path from its entrance to its vault', function()
        -- Arrange
        local surface = RS.get_surface()

        for seat = 1, Settings.seats do
            -- Act
            local points = Layout.waypoints(seat)

            -- Assert: every tile along the way is path
            for i = 1, #points - 1 do
                local a, b = points[i], points[i + 1]
                local steps = math.ceil(math.max(math.abs(b.x - a.x), math.abs(b.y - a.y)))
                for step = 0, steps do
                    local x = a.x + (b.x - a.x) * step / steps
                    local y = a.y + (b.y - a.y) * step / steps
                    local tile = surface.get_tile(x, y)
                    Assert.equal(Layout.tiles.path, tile.name, 'seat ' .. seat .. ': the tile at ' .. x .. ', ' .. y)
                end
            end
            Assert.equal(seat, Layout.to_plot(points[#points]), 'the path ends in its own plot')
        end
    end)

    Declare.test('every plot has its vault', function()
        -- Arrange
        local surface = RS.get_surface()

        for seat = 1, Settings.seats do
            -- Act
            local position = Layout.vault_position(seat)

            -- Assert
            local count = surface.count_entities_filtered { name = 'market', area = { { position.x - 2, position.y - 2 }, { position.x + 2, position.y + 2 } } }
            Assert.equal(1, count, 'vaults in plot ' .. seat)
        end
    end)

    Declare.test('a biter nobody shoots keeps to the path, reaches the vault and steals chips', function(context)
        -- Arrange: a south plot, mirrored, and a north one
        local seats = { 5, 2 }
        local data = {}
        for i, seat in ipairs(seats) do
            data[i] = sit(context, seat)
        end
        local wave = Settings.waves[1]
        local creeps = {}
        local off_path = {}

        -- Act
        context:next(function()
            for i, seat in ipairs(seats) do
                creeps[i] = Waves.spawn(RS.get_surface(), seat, 1)
            end
        end):wait_until(60 * 120, function()
            local walking = false
            for _, creep in pairs(creeps) do
                if creep.entity.valid then
                    walking = true
                    local seat, x, y = Layout.to_plot(creep.entity.position)
                    if seat ~= creep.seat or Layout.plot_tile(x, y) ~= 'path' then
                        off_path[#off_path + 1] = string.format('seat %d at %.1f, %.1f (tick %d)', creep.seat, x or -1, y or -1, game.tick)
                    end
                end
            end
            return not walking
        end, function()
            local creep = creeps[1].entity.valid and creeps[1] or creeps[2]
            return 'a biter is still walking, at ' .. serpent.line(creep.entity.position)
        end):next(function()
            -- Assert
            Assert.equal(0, #off_path, 'times a biter was off the path, first ' .. tostring(off_path[1]))
            for i, seat in ipairs(seats) do
                Assert.equal(Settings.starting_chips - wave.loot, data[i].chips, 'seat ' .. seat .. "'s chips after its biter reached the vault")
            end
        end)
    end)

    Declare.test('a tower kills the biters walking past and its player gets the bounty', function(context)
        -- Arrange: a straight flush on the felt between the first two rows
        local seat = 7
        local data = sit(context, seat)
        local cards = { Cards.card(5, 1), Cards.card(6, 1), Cards.card(7, 1), Cards.card(8, 1), Cards.card(9, 1) }
        local spec = Towers.spec(cards, Cards.evaluate(cards))
        local tower = Towers.create(RS.get_surface(), seat, spec, Layout.to_world(seat, 8.5, 12.5))
        Assert.is_true(tower ~= nil, 'the tower was created')
        local wave = Settings.waves[1]

        -- Act
        context:next(function()
            Waves.spawn(RS.get_surface(), seat, 1)
            Waves.spawn(RS.get_surface(), seat, 1)
        end):wait_until(60 * 90, function()
            return #creeps_in(seat) == 0
        end, 'the biters are still alive'):next(function()
            -- Assert
            Assert.equal(Settings.starting_chips + 2 * wave.bounty, data.chips, 'chips after both biters died')
        end)
    end)

    Declare.test('a tower nobody placed goes on the felt in its plot', function(context)
        -- Arrange
        local seat = 6
        sit(context, seat)
        local cards = { Cards.card(9, 1), Cards.card(9, 2), Cards.card(4, 3), Cards.card(4, 4), Cards.card(4, 1) }
        local spec = Towers.spec(cards, Cards.evaluate(cards))
        State.get().pending[seat] = { spec }

        -- Act
        Game.place_pending(seat)

        -- Assert
        Assert.equal(0, #State.get().pending[seat], 'towers still waiting')
        Assert.equal(1, Towers.count(seat), 'towers in the plot')
        for _, t in pairs(State.get().towers) do
            if t.seat == seat then
                Assert.equal(spec.entity, t.entity.name, 'the tower looks like a full house')
                Assert.is_true(Layout.is_buildable(seat, t.entity.bounding_box), 'the tower stands on felt: ' .. serpent.line(t.entity.position))
            end
        end
    end)
end)
