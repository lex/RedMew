-- The game: seats and gold, the team's lives, and the waves. Players buy towers, place them,
-- upgrade and sell them; the waves come one after another until the last is cleared (a win) or
-- the lives run out (a loss), and then a new game starts.

local Creeps = require 'map_gen.maps.convergence.creeps'
local Layout = require 'map_gen.maps.convergence.layout'
local RS = require 'map_gen.shared.redmew_surface'
local Settings = require 'map_gen.maps.convergence.settings'
local State = require 'map_gen.maps.convergence.state'
local Towers = require 'map_gen.maps.convergence.towers'

local phases = State.phases

local Public = {}

-- Called when what players' panels show has changed: with a player index, or nil for everyone.
local refresh = function(_) end

function Public.set_refresh(fn)
    refresh = fn
end

local function surface()
    return RS.get_surface()
end

function Public.get_player(player_index)
    return State.get().players[player_index]
end

function Public.seconds_left()
    return math.max(0, math.ceil((State.get().phase_end - game.tick) / 60))
end

local function set_phase(phase, seconds)
    local state = State.get()
    state.phase = phase
    state.phase_end = game.tick + math.floor(seconds * 60)
    refresh(nil)
end

-- Seats -------------------------------------------------------------------------------------

local function free_seat()
    local seats = State.get().seats
    for seat = 1, Layout.seats do
        if not seats[seat] then
            return seat
        end
    end
    return nil
end

--- Gives the player a seat (their own lane and zone) if one is free. Every player gets gold
--- and can build in the shared zones, seated or not.
function Public.join(player)
    local state = State.get()
    local data = state.players[player.index]
    if not data then
        data = {
            index = player.index,
            gold = Settings.starting_gold + state.paid,
            kills = 0,
            spent = 0
        }
        state.players[player.index] = data
        state.pending[player.index] = {}
    end
    if not data.seat and state.phase ~= phases.over then
        local seat = free_seat()
        if seat then
            data.seat = seat
            state.seats[seat] = player.index
            game.print({ 'convergence.seated', player.name, seat })
            if player.character then
                local target = Layout.seat_position(seat)
                local position = surface().find_non_colliding_position('character', target, 8, 0.5) or target
                player.character.teleport(position, surface())
            end
        end
    end
    refresh(nil)
    return data
end

-- Gold and lives ----------------------------------------------------------------------------

local function on_kill(creep)
    local data = creep.killer and State.get().players[creep.killer]
    if data then
        data.gold = data.gold + creep.bounty
        data.kills = data.kills + 1
        local player = game.get_player(data.index)
        if player and player.connected and creep.entity.valid then
            player.create_local_flying_text { text = { '', '+', creep.bounty }, position = creep.entity.position, color = { 1, 0.85, 0.2 } }
        end
    end
end

local function on_leak(creep)
    local state = State.get()
    state.lives = math.max(0, state.lives - (creep.boss and 5 or 1))
    game.print({ 'convergence.leaked', state.lives })
    refresh(nil)
end

Creeps.set_handlers(on_kill, on_leak)

-- Buying and building -----------------------------------------------------------------------

--- Buys a tower of a line: takes the gold and gives the player the item to place it with.
---@return boolean bought
function Public.buy(player_index, line_name)
    local data = Public.get_player(player_index)
    local line = Settings.lines[line_name]
    local player = game.get_player(player_index)
    if not data or not line or not player or State.get().phase == phases.over then
        return false
    end
    local cost = line.levels[1].cost
    if data.gold < cost then
        return false
    end
    if player.insert { name = line.entity, count = 1 } == 0 then
        return false
    end
    data.gold = data.gold - cost
    data.spent = data.spent + cost
    local pending = State.get().pending[player_index]
    pending[#pending + 1] = line_name
    refresh(player_index)
    return true
end

local function refund_item(player, name)
    if player and player.valid then
        player.insert { name = name, count = 1 }
    end
end

--- A player placed one of the entities towers look like: make it the tower they bought, if
--- it's somewhere they can build that line.
function Public.on_built_entity(event)
    local entity = event.entity
    if not (entity and entity.valid) or entity.type == 'entity-ghost' then
        return
    end
    local player = game.get_player(event.player_index)
    local line_name = Towers.line_of_entity[entity.name]
    local pending = State.get().pending[event.player_index] or {}
    local index
    for i, name in ipairs(pending) do
        if name == line_name then
            index = i
            break
        end
    end
    if not index then
        -- nothing else can be built here
        entity.destroy()
        return
    end
    local data = Public.get_player(event.player_index)
    local line = Settings.lines[line_name]
    if not Layout.can_build(data.seat, entity.bounding_box, line.trap == true) then
        local name = entity.name
        entity.destroy()
        refund_item(player, name)
        player.print(line.trap and { 'convergence.trap_needs_path' } or { 'convergence.tower_needs_felt' })
        return
    end
    table.remove(pending, index)
    local tower = Towers.register(entity, line_name, event.player_index)
    data.selected = tower.id
    Towers.show_range(tower, player)
    refresh(event.player_index)
end

--- Picks a tower for a player's panel to show (they pointed at it, or opened it).
function Public.select(player, entity)
    local tower = entity and entity.valid and entity.unit_number and Towers.get(entity.unit_number)
    local data = Public.get_player(player.index)
    if not tower or not data or data.selected == tower.id then
        return
    end
    data.selected = tower.id
    Towers.show_range(tower, player)
    refresh(player.index)
end

--- The tower a player's panel shows, if it still stands.
function Public.selected_tower(player_index)
    local data = Public.get_player(player_index)
    local tower = data and data.selected and Towers.get(data.selected)
    if tower and tower.entity.valid then
        return tower
    end
    return nil
end

--- Upgrades the player's selected tower, if it's theirs and they have the gold.
function Public.upgrade(player_index)
    local data = Public.get_player(player_index)
    local tower = Public.selected_tower(player_index)
    if not data or not tower or tower.owner ~= player_index then
        return false
    end
    local cost = Towers.upgrade_cost(tower)
    if not cost or data.gold < cost then
        return false
    end
    data.gold = data.gold - cost
    data.spent = data.spent + cost
    Towers.upgrade(tower)
    refresh(player_index)
    return true
end

--- Sells the player's selected tower, if it's theirs.
function Public.sell(player_index)
    local data = Public.get_player(player_index)
    local tower = Public.selected_tower(player_index)
    if not data or not tower or tower.owner ~= player_index then
        return false
    end
    data.gold = data.gold + Towers.sell_value(tower)
    Towers.remove(tower)
    data.selected = nil
    refresh(player_index)
    return true
end

-- Waves -------------------------------------------------------------------------------------

-- seats whose players are here: their lanes get biters
local function active_seats()
    local seats = {}
    for seat, index in pairs(State.get().seats) do
        local player = game.get_player(index)
        if player and player.connected then
            seats[#seats + 1] = seat
        end
    end
    return seats
end

--- Sends the next wave.
function Public.send_wave()
    local state = State.get()
    state.wave = state.wave + 1
    local wave = Settings.waves[state.wave]
    state.to_spawn = {}
    for _, seat in pairs(active_seats()) do
        state.to_spawn[seat] = wave.count
    end
    state.next_spawn = game.tick
    set_phase(phases.wave, 0)
    local kind = wave.boss and 'boss' or wave.air and 'air' or wave.shielded and 'shielded' or wave.regen and 'regen' or 'normal'
    game.print({ 'convergence.wave_' .. kind, state.wave, #Settings.waves, math.floor(Settings.biter_health(state.wave)) })
end

--- Lets the next wave come now, during the break.
function Public.call_wave(player_index)
    local state = State.get()
    if state.phase ~= phases.break_ then
        return false
    end
    local player = game.get_player(player_index)
    game.print({ 'convergence.called', player and player.name or '?' })
    Public.send_wave()
    return true
end

local function game_over(won)
    local state = State.get()
    state.won = won
    Creeps.clear()
    state.to_spawn = {}
    game.print(won and { 'convergence.won', state.wave } or { 'convergence.lost', state.wave })
    game.print({ 'convergence.new_game_in', Settings.game_over_seconds })
    set_phase(phases.over, Settings.game_over_seconds)
end

local function end_wave()
    local state = State.get()
    local bonus = Settings.wave_bonus(state.wave)
    state.paid = state.paid + bonus
    for _, data in pairs(state.players) do
        data.gold = data.gold + bonus
    end
    if state.wave >= #Settings.waves then
        game_over(true)
        return
    end
    game.print({ 'convergence.wave_cleared', state.wave, bonus })
    set_phase(phases.break_, Settings.break_seconds)
end

--- Clears the map and starts a new game, seating everyone who's here.
function Public.new_game()
    Creeps.clear()
    Towers.remove_all()
    for _, player in pairs(game.players) do
        for _, line in pairs(Settings.lines) do
            player.remove_item { name = line.entity, count = 1000 }
        end
        local cursor = player.cursor_stack
        if cursor and cursor.valid_for_read and Towers.line_of_entity[cursor.name] then
            cursor.clear()
        end
    end
    State.reset()
    game.print({ 'convergence.new_game', State.get().game })
    for _, player in pairs(game.connected_players) do
        Public.join(player)
    end
end

local function spawn_biters(tick)
    local state = State.get()
    if tick < state.next_spawn then
        return
    end
    state.next_spawn = tick + Settings.spawn_interval
    for seat, left in pairs(state.to_spawn) do
        if left > 0 then
            state.to_spawn[seat] = left - 1
            Creeps.spawn(surface(), seat, state.wave)
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

--- Runs the game; call every few ticks.
function Public.update(tick)
    local state = State.get()
    local phase = state.phase
    if phase == phases.waiting then
        if #active_seats() > 0 then
            set_phase(phases.break_, Settings.first_wave_seconds)
            game.print({ 'convergence.first_wave_in', Settings.first_wave_seconds })
        end
    elseif phase == phases.break_ then
        if tick >= state.phase_end then
            if #active_seats() == 0 then
                set_phase(phases.waiting, 0)
            else
                Public.send_wave()
            end
        end
    elseif phase == phases.wave then
        spawn_biters(tick)
        if state.lives <= 0 then
            game_over(false)
        elseif spawning_done() and Creeps.count() == 0 then
            end_wave()
        end
    elseif phase == phases.over then
        if tick >= state.phase_end then
            Public.new_game()
        end
    end
end

return Public
