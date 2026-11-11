-- High Stakes: a tower defence played with cards. Each round every player gets five cards, swaps
-- some once, and plays their best poker hand: it becomes a tower in their own plot. Then a wave
-- of biters walks every plot's path to its vault, stealing chips from any player it reaches.
-- After thirty waves the richest player wins.

local Event = require 'utils.event'
local Game = require 'map_gen.maps.high_stakes.game'
local Gui = require 'map_gen.maps.high_stakes.gui'
local Layout = require 'map_gen.maps.high_stakes.layout'
local MSP = require 'resources.map_settings'
local RS = require 'map_gen.shared.redmew_surface'
local ScenarioInfo = require 'features.gui.info'
local State = require 'map_gen.maps.high_stakes.state'
local Towers = require 'map_gen.maps.high_stakes.towers'
local Waves = require 'map_gen.maps.high_stakes.waves'

ScenarioInfo.set_map_name('High Stakes')
ScenarioInfo.set_map_description([[
A tower defence played with cards. Every round you get five cards, swap up to four of them once, and play your best poker hand: it becomes a tower in your own plot. Then biters walk every plot's path to its vault, stealing chips from any player they reach.

After thirty waves the richest player wins.
]])
ScenarioInfo.set_map_extra_info([[
[font=default-bold]A round[/font]
- Open your hand with the [img=virtual-signal/signal-heart] button. Click the cards you don't want and press Swap: once a hand, up to four cards.
- Press Play, then place the tower you get on the green felt in your plot. A tower you don't place goes next to the path by itself when the hand ends.
- The best hand at the table wins chips.
- Then the wave: each biter you kill pays chips, each one that reaches your vault steals some. Every sixth wave is a boss. With no chips left, you're out.

[font=default-bold]The hands[/font], worst to best: high card, pair, two pair, three of a kind, straight, flush, full house, four of a kind, straight flush. Better hands hit harder, faster and further.

[font=default-bold]The suits[/font] are Factorio's: [img=virtual-signal/signal-damage] crosshair, [img=virtual-signal/signal-lightning] lightning, [img=virtual-signal/signal-fire] fire and [img=virtual-signal/signal-explosion] explosion. A high card attacks the way its suit says: quick shots, a chain of lightning, a burn, or a blast.

[font=default-bold]Folding[/font] skips your tower and your wave: three times a game.

[font=default-bold]Tipping[/font] the dealer costs 10 chips and makes your next hand more likely to be a good one: the more tips, the better.
]])
ScenarioInfo.set_new_info([[
2026-11-11:
  - Added High Stakes
]])

local Config = storage.config
Config.market.enabled = false
Config.player_rewards.enabled = false
Config.player_create.starting_items = {}
Config.turret_active_delay.enabled = false
Config.evolution_progress.enabled = false
Config.apocalypse.enabled = false
Config.production_hud.enabled = false
Config.paint.enabled = false
Config.dump_offline_inventories.enabled = false

local area = Layout.area()
-- nothing but plain ground under the table's tiles: no ore, trees, rocks, biters, water or decoratives
RS.set_map_gen_settings({
    {
        default_enable_all_autoplace_controls = false,
        autoplace_settings = {
            entity = { treat_missing_as_default = false, settings = {} },
            decorative = { treat_missing_as_default = false, settings = {} },
            tile = { treat_missing_as_default = false, settings = { ['grass-1'] = {} } }
        },
        width = (area[2][1] - area[1][1]) + 64,
        height = (area[2][2] - area[1][2]) + 64
    }
})
RS.set_map_settings({ MSP.pollution_off, MSP.enemy_evolution_off, MSP.enemy_expansion_off })

-- how often towers shoot and biters burn, in ticks
local interval = Towers.interval

local function set_up_table()
    local state = State.get()
    if state.table_ready then
        return
    end
    state.table_ready = true
    local surface = RS.get_surface()
    surface.always_day = true
    -- the whole table, generated now so the vaults have somewhere to stand
    surface.request_to_generate_chunks({ 0, 0 }, 3)
    surface.force_generate_chunk_requests()
    game.forces.enemy.set_cease_fire('player', true)
    game.forces.player.set_cease_fire('enemy', true)
    for seat = 1, 8 do
        local vault = surface.create_entity { name = 'market', position = Layout.vault_position(seat), force = 'neutral' }
        if vault then
            vault.destructible = false
            vault.minable_flag = false
            vault.operable = false
        end
    end
end

Event.on_nth_tick(interval, function(event)
    local tick = event.tick
    set_up_table()
    Game.update(tick)
    Waves.update(tick, interval, Towers.wreck)
    Towers.update(tick)
end)

Event.on_nth_tick(30, function()
    local state = State.get()
    -- a new hand opens every seated player's panel, once
    local hand_started = state.phase == State.phases.hand and state.panels_opened ~= state.round
    if hand_started then
        state.panels_opened = state.round
    end
    Gui.update_all(hand_started)
end)

Event.add(defines.events.on_ai_command_completed, Waves.on_ai_command_completed)
Event.add(defines.events.on_entity_died, Waves.on_entity_died)
Event.add(defines.events.on_built_entity, Game.on_built_entity)

Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if Game.seat(player) then
        Gui.show(player)
    else
        player.print({ 'high_stakes.message_watching' })
    end
end)

return Layout.shape
