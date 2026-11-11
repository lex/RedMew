-- The game: seats and chips, and the rounds: a hand, then a wave, thirty times. Whoever has the
-- most chips after the last wave wins, and a new game starts.

local Cards = require 'map_gen.maps.high_stakes.cards'
local Layout = require 'map_gen.maps.high_stakes.layout'
local RS = require 'map_gen.shared.redmew_surface'
local Settings = require 'map_gen.maps.high_stakes.settings'
local State = require 'map_gen.maps.high_stakes.state'
local Towers = require 'map_gen.maps.high_stakes.towers'
local Waves = require 'map_gen.maps.high_stakes.waves'

local phases = State.phases

local Public = {}

-- Called when what a player's panel shows has changed: with a player index, or nil for everyone.
local refresh = function(_) end

function Public.set_refresh(fn)
    refresh = fn
end

local function surface()
    return RS.get_surface()
end

local function random(m, n)
    return math.random(m, n)
end

--- A player's seat data, or nil if they aren't seated.
function Public.get_player(player_index)
    return State.get().players[player_index]
end

--- Players still in the game who are online.
local function active_players()
    local list = {}
    for _, data in pairs(State.get().players) do
        local player = game.get_player(data.index)
        if not data.out and player and player.connected then
            list[#list + 1] = data
        end
    end
    return list
end

local function seconds_left()
    return math.max(0, math.ceil((State.get().phase_end - game.tick) / 60))
end
Public.seconds_left = seconds_left

-- Seats -------------------------------------------------------------------------------------

local function free_seat()
    local seats = State.get().seats
    for seat = 1, Settings.seats do
        if not seats[seat] then
            return seat
        end
    end
    return nil
end

--- Can a newcomer sit down now.
function Public.can_join()
    local state = State.get()
    return state.phase ~= phases.over and state.round <= Settings.last_round_to_join and free_seat() ~= nil
end

local function go_to_seat(player, seat)
    local character = player.character
    if not character then
        return
    end
    local target = Layout.to_world(seat, 8, 58)
    local position = surface().find_non_colliding_position('character', target, 8, 0.5) or target
    character.teleport(position, surface())
end

--- Seats the player if a seat is free and the game isn't too far along. Does nothing for a
--- player who's already seated.
---@return boolean seated
function Public.seat(player)
    local state = State.get()
    if state.players[player.index] then
        return true
    end
    if not Public.can_join() then
        return false
    end
    local seat = free_seat()
    state.seats[seat] = player.index
    state.players[player.index] = {
        index = player.index,
        seat = seat,
        chips = Settings.starting_chips,
        tips = 0,
        folds_left = Settings.max_folds,
        wins = 0,
        hand = nil,
        selected = {},
        swapped = false,
        played = false,
        folded = false,
        out = false
    }
    state.pending[seat] = state.pending[seat] or {}
    go_to_seat(player, seat)
    game.print({ 'high_stakes.seated', player.name, seat })
    refresh(nil)
    return true
end

-- Chips -------------------------------------------------------------------------------------

local function flying_text(data, text, position, color)
    local player = game.get_player(data.index)
    if player and player.connected then
        player.create_local_flying_text { text = text, position = position, color = color }
    end
end

local function knock_out(data)
    data.out = true
    data.chips = 0
    Waves.clear(data.seat)
    State.get().to_spawn[data.seat] = 0
    Towers.remove(data.seat)
    State.get().pending[data.seat] = {}
    local player = game.get_player(data.index)
    game.print({ 'high_stakes.player_out', player and player.name or '?' })
end

local function seat_player(seat)
    local index = State.get().seats[seat]
    return index and State.get().players[index]
end

local function on_kill(creep)
    local data = seat_player(creep.seat)
    if not data or data.out then
        return
    end
    data.chips = data.chips + creep.bounty
    if creep.entity.valid then
        flying_text(data, { '', '+', creep.bounty }, creep.entity.position, { 0.4, 1, 0.4 })
    end
    refresh(nil)
end

local function on_leak(creep)
    local data = seat_player(creep.seat)
    if not data or data.out then
        return
    end
    data.chips = math.max(0, data.chips - creep.loot)
    if creep.entity.valid then
        flying_text(data, { '', '-', creep.loot }, creep.entity.position, { 1, 0.3, 0.3 })
    end
    if data.chips <= 0 then
        knock_out(data)
    end
    refresh(nil)
end

Waves.set_handlers(on_kill, on_leak)

--- Gives the dealer a tip: the next hand is more likely to be a good one.
---@return boolean tipped
function Public.tip(player_index)
    local data = Public.get_player(player_index)
    if not data or data.out or data.chips < Settings.tip_cost or data.tips >= Cards.max_tips then
        return false
    end
    data.chips = data.chips - Settings.tip_cost
    data.tips = data.tips + 1
    refresh(player_index)
    return true
end

-- The hand ----------------------------------------------------------------------------------

local function deal(data)
    data.deck = Cards.new_deck(random)
    local rigged = Cards.rigged_hand_type(data.tips, random)
    data.tips = 0
    if rigged then
        data.hand = Cards.deal_rigged(data.deck, rigged, random)
    else
        data.hand = {}
        for i = 1, 5 do
            data.hand[i] = table.remove(data.deck)
        end
    end
    data.selected = {}
    data.swapped = false
    data.played = false
    data.folded = false
    data.last_hand = nil
end

local function in_hand(data)
    local state = State.get()
    return state.phase == phases.hand and data.hand and not data.played and not data.folded and not data.out
end
Public.in_hand = in_hand

--- Marks a card to swap, or unmarks it.
function Public.toggle_card(player_index, card_index)
    local data = Public.get_player(player_index)
    if not data or not in_hand(data) or data.swapped then
        return
    end
    if data.selected[card_index] then
        data.selected[card_index] = nil
    elseif table_size(data.selected) < Settings.max_swap then
        data.selected[card_index] = true
    end
    refresh(player_index)
end

--- Swaps the marked cards for new ones, once a hand.
---@return boolean swapped
function Public.swap(player_index)
    local data = Public.get_player(player_index)
    if not data or not in_hand(data) or data.swapped or next(data.selected) == nil then
        return false
    end
    for i in pairs(data.selected) do
        data.hand[i] = table.remove(data.deck)
    end
    data.selected = {}
    data.swapped = true
    refresh(player_index)
    return true
end

local function give_tower(data, spec)
    local state = State.get()
    local pending = state.pending[data.seat]
    pending[#pending + 1] = spec
    local player = game.get_player(data.index)
    if player and player.connected then
        player.insert { name = spec.entity, count = 1 }
        player.print({ 'high_stakes.place_tower', Towers.hand_name(spec.type) })
    end
end

--- Plays the hand: its best poker hand becomes the player's tower.
---@return boolean played
function Public.play(player_index)
    local data = Public.get_player(player_index)
    if not data or not in_hand(data) then
        return false
    end
    local hand = Cards.evaluate(data.hand)
    data.played = true
    data.selected = {}
    data.last_hand = { score = Cards.score(hand), type = hand.type, text = Cards.hand_text(data.hand, hand) }
    give_tower(data, Towers.spec(data.hand, hand))
    refresh(player_index)
    return true
end

--- Folds the hand: no tower this round, and no wave either. A player has three for the game.
---@return boolean folded
function Public.fold(player_index)
    local data = Public.get_player(player_index)
    if not data or not in_hand(data) or data.folds_left <= 0 then
        return false
    end
    data.folds_left = data.folds_left - 1
    data.folded = true
    data.selected = {}
    local player = game.get_player(player_index)
    game.print({ 'high_stakes.folded', player.name })
    refresh(player_index)
    return true
end

-- Towers waiting to be placed ----------------------------------------------------------------

local function remove_item(player, name)
    if not (player and player.valid) then
        return
    end
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == name then
        cursor.count = cursor.count - 1
        return
    end
    player.remove_item { name = name, count = 1 }
end

--- Places the seat's towers that are still waiting, wherever there's room nearest the path.
function Public.place_pending(seat)
    local state = State.get()
    local pending = state.pending[seat]
    if not pending or #pending == 0 then
        return
    end
    local s = surface()
    local data = seat_player(seat)
    local player = data and game.get_player(data.index)
    for i = #pending, 1, -1 do
        local spec = pending[i]
        local prototype = prototypes.entity[spec.entity]
        for _, position in ipairs(Layout.best_spots(seat, prototype.tile_width, prototype.tile_height, spec.range)) do
            if s.can_place_entity { name = spec.entity, position = position, force = 'player' } then
                if Towers.create(s, seat, spec, position) then
                    table.remove(pending, i)
                    remove_item(player, spec.entity)
                    if player and player.connected then
                        player.print({ 'high_stakes.tower_placed_for_you', Towers.hand_name(spec.type) })
                    end
                end
                break
            end
        end
    end
end

--- A player built one of the turrets towers look like: make it their waiting tower, if it's on
--- their felt.
function Public.on_built_entity(event)
    local entity = event.entity
    if not (entity and entity.valid) or entity.type == 'entity-ghost' then
        return
    end
    local player = game.get_player(event.player_index)
    local data = Public.get_player(event.player_index)
    local pending = data and State.get().pending[data.seat]
    local index
    for i, spec in ipairs(pending or {}) do
        if spec.entity == entity.name then
            index = i
            break
        end
    end
    if not index then
        -- not a tower the player is owed: nothing else can be built here
        entity.destroy()
        return
    end
    if not Layout.is_buildable(data.seat, entity.bounding_box) then
        local name = entity.name
        entity.destroy()
        player.insert { name = name, count = 1 }
        player.print({ 'high_stakes.tower_needs_felt' })
        return
    end
    local spec = table.remove(pending, index)
    Towers.register(entity, data.seat, spec)
    refresh(event.player_index)
end

-- Rounds ------------------------------------------------------------------------------------

local function set_phase(phase, seconds)
    local state = State.get()
    state.phase = phase
    state.phase_end = game.tick + math.floor(seconds * 60)
    refresh(nil)
end

function Public.start_hand()
    local state = State.get()
    -- whoever is watching sits down, while there are seats and it's early enough
    for _, player in pairs(game.connected_players) do
        if not state.players[player.index] and state.round < Settings.last_round_to_join then
            Public.seat(player)
        end
    end
    local players = active_players()
    if #players == 0 then
        set_phase(phases.waiting, 0)
        return
    end
    state.round = state.round + 1
    for _, data in pairs(state.players) do
        data.hand = nil
        data.played = false
        data.folded = false
        data.last_hand = nil
    end
    for _, data in pairs(players) do
        deal(data)
    end
    set_phase(phases.hand, Settings.hand_seconds)
    game.print({ 'high_stakes.round_start', state.round, #Settings.waves })
end

local function names(list)
    local result = { '' }
    for i, data in ipairs(list) do
        if i > 1 then
            result[#result + 1] = ', '
        end
        local player = game.get_player(data.index)
        result[#result + 1] = player and player.name or '?'
    end
    return result
end

-- the best hands of the round win chips
local function pay_winners()
    local state = State.get()
    local best, winners = -1, {}
    for _, data in pairs(state.players) do
        local hand = data.last_hand
        if hand and not data.out then
            if hand.score > best then
                best, winners = hand.score, { data }
            elseif hand.score == best then
                winners[#winners + 1] = data
            end
        end
    end
    if #winners == 0 then
        state.last_winners = nil
        return
    end
    local bonus = Settings.hand_bonus(state.round)
    for _, data in pairs(winners) do
        data.chips = data.chips + bonus
        data.wins = data.wins + 1
    end
    local hand = winners[1].last_hand
    state.last_winners = { score = best }
    game.print({ 'high_stakes.round_winner', names(winners), Towers.hand_name(hand.type), hand.text, bonus, #winners })
end

local function start_wave()
    local state = State.get()
    local wave = Settings.waves[state.round]
    state.to_spawn = {}
    local any = false
    for _, data in pairs(state.players) do
        if data.played and not data.out then
            state.to_spawn[data.seat] = wave.boss and 1 or Settings.wave_size
            any = true
        end
    end
    state.next_spawn = game.tick
    set_phase(phases.wave, Settings.max_wave_seconds)
    local health = math.floor(Settings.biter_health(wave))
    if wave.boss then
        game.print({ 'high_stakes.boss_wave_start', state.round, health, wave.loot })
    else
        game.print({ 'high_stakes.wave_start', state.round, Settings.wave_size, health, wave.loot })
    end
    if not any then
        state.phase_end = game.tick
    end
end

function Public.end_hand()
    local state = State.get()
    for _, data in pairs(state.players) do
        if in_hand(data) then
            Public.play(data.index)
        end
    end
    for seat in pairs(state.seats) do
        Public.place_pending(seat)
    end
    pay_winners()
    start_wave()
end

local function richest()
    local best, winners = -1, {}
    for _, data in pairs(State.get().players) do
        if data.chips > best then
            best, winners = data.chips, { data }
        elseif data.chips == best then
            winners[#winners + 1] = data
        end
    end
    return winners, best
end

local function game_over()
    local winners, chips = richest()
    if #winners > 0 and chips > 0 then
        game.print({ 'high_stakes.game_over', names(winners), chips, #winners })
    else
        game.print({ 'high_stakes.game_over_nobody' })
    end
    set_phase(phases.over, Settings.game_over_seconds)
    game.print({ 'high_stakes.new_game_in', Settings.game_over_seconds })
end

local function everyone_out()
    local any_seated = false
    for _, data in pairs(State.get().players) do
        any_seated = true
        if not data.out then
            return false
        end
    end
    return any_seated
end

function Public.end_wave()
    local state = State.get()
    Waves.clear()
    state.to_spawn = {}
    if state.round >= #Settings.waves or everyone_out() then
        game_over()
        return
    end
    set_phase(phases.break_, Settings.break_seconds)
end

--- Clears the table and seats everyone online for a new game.
function Public.new_game()
    Waves.clear()
    Towers.remove()
    local tower_items = {}
    for _, stats in pairs(Settings.towers) do
        tower_items[stats.entity] = true
    end
    for _, player in pairs(game.players) do
        for name in pairs(tower_items) do
            player.remove_item { name = name, count = 1000 }
        end
        local cursor = player.cursor_stack
        if cursor and cursor.valid_for_read and tower_items[cursor.name] then
            cursor.clear()
        end
    end
    State.reset()
    game.print({ 'high_stakes.new_game', State.get().game })
    for _, player in pairs(game.connected_players) do
        Public.seat(player)
    end
    refresh(nil)
end

local function spawn_wave_biters(tick)
    local state = State.get()
    if tick < (state.next_spawn or 0) then
        return
    end
    state.next_spawn = tick + Settings.spawn_interval
    local s = surface()
    for seat, left in pairs(state.to_spawn) do
        if left > 0 then
            state.to_spawn[seat] = left - 1
            Waves.spawn(s, seat, state.round)
        end
    end
end

local function spawning_done()
    for _, left in pairs(State.get().to_spawn) do
        if left > 0 then
            return false
        end
    end
    return true
end

--- Runs the rounds; call every few ticks.
function Public.update(tick)
    local state = State.get()
    local phase = state.phase
    if phase == phases.waiting then
        if #active_players() > 0 then
            Public.start_hand()
        end
    elseif phase == phases.hand then
        if tick >= state.phase_end then
            Public.end_hand()
        else
            -- everyone has folded, or played and placed their tower: no need to wait
            local waiting = false
            for _, data in pairs(active_players()) do
                if in_hand(data) or #state.pending[data.seat] > 0 then
                    waiting = true
                    break
                end
            end
            if not waiting then
                Public.end_hand()
            end
        end
    elseif phase == phases.wave then
        spawn_wave_biters(tick)
        if tick >= state.phase_end or (spawning_done() and Waves.count() == 0) then
            Public.end_wave()
        end
    elseif phase == phases.break_ then
        if tick >= state.phase_end then
            Public.start_hand()
        end
    elseif phase == phases.over then
        if tick >= state.phase_end then
            Public.new_game()
        end
    end
end

return Public
