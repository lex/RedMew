-- Convergence: a co-op tower defence. Each player's lane starts at the top of the map, and the
-- lanes merge two by two on their way down to the core. Biters come in waves down every lane;
-- the team buys, places and upgrades towers to stop them, and each one that reaches the core
-- costs a life. Clear all sixty waves to win.

local Creeps = require 'map_gen.maps.convergence.creeps'
local Event = require 'utils.event'
local Game = require 'map_gen.maps.convergence.game'
local Gui = require 'map_gen.maps.convergence.gui'
local Layout = require 'map_gen.maps.convergence.layout'
local MSP = require 'resources.map_settings'
local RS = require 'map_gen.shared.redmew_surface'
local ScenarioInfo = require 'features.gui.info'
local State = require 'map_gen.maps.convergence.state'
local Towers = require 'map_gen.maps.convergence.towers'

ScenarioInfo.set_map_name('Convergence')
ScenarioInfo.set_map_description([[
A co-op tower defence. Every player's lane starts at the top of the map, and the lanes merge two by two on their way down to the core. Biters come down every lane in waves; build and upgrade towers to stop them. Each biter that reaches the core costs the team a life.

Clear all sixty waves to win.
]])
ScenarioInfo.set_map_extra_info([[
[font=default-bold]Building[/font]
- Open the panel with the [img=item/gun-turret] button. Buy a tower in its shop and place it: in your own zone (the blue felt round the top of your lane) or anywhere on the green felt below, which everyone shares. Traps go on the path itself.
- Point at a tower (or click it) to pick it in the panel, and upgrade or sell it there.
- Kills pay gold to whoever's tower made them, and every cleared wave pays everyone.

[font=default-bold]Towers[/font]
- Gun and laser towers hit everything; flamers burn biters on the ground; flak only hits the air.
- Cryo radars slow everything round them, beacons make nearby towers hit harder, and traps burn what walks over them.

[font=default-bold]Waves[/font]
- Every seventh wave flies: only guns, lasers, cryo and flak reach it.
- Every fifth wave is shielded: slows and traps don't touch it.
- Some waves heal, and every fifteenth sends bosses, which cost five lives each.
- When a wave is cleared, the next comes after a break, or at once if someone calls it.
]])
ScenarioInfo.set_new_info([[
2026-11-11:
  - Added Convergence
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
-- nothing but plain ground under the map's tiles: no ore, trees, rocks, biters, water or decoratives
RS.set_map_gen_settings({
    {
        default_enable_all_autoplace_controls = false,
        autoplace_settings = {
            entity = { treat_missing_as_default = false, settings = {} },
            decorative = { treat_missing_as_default = false, settings = {} },
            tile = { treat_missing_as_default = false, settings = { ['grass-1'] = {} } }
        },
        width = 2 * math.max(-area[1][1], area[2][1]) + 64,
        height = 2 * math.max(-area[1][2], area[2][2]) + 64
    }
})
RS.set_map_settings({ MSP.pollution_off, MSP.enemy_evolution_off, MSP.enemy_expansion_off })
RS.set_spawn_position(Layout.plaza)

local function set_up_map()
    local state = State.get()
    if state.map_ready then
        return
    end
    state.map_ready = true
    local surface = RS.get_surface()
    surface.always_day = true
    surface.request_to_generate_chunks({ 0, 0 }, 6)
    surface.force_generate_chunk_requests()
    game.forces.enemy.set_cease_fire('player', true)
    game.forces.player.set_cease_fire('enemy', true)
    -- the lanes are long: walk faster
    game.forces.player.character_running_speed_modifier = 1
    local core = surface.create_entity { name = 'rocket-silo', position = Layout.core, force = 'neutral' }
    if core then
        core.destructible = false
        core.minable_flag = false
        core.operable = false
    end
end

local interval = Towers.interval

Event.on_nth_tick(interval, function(event)
    local tick = event.tick
    set_up_map()
    Game.update(tick)
    Creeps.update(tick, interval)
    Towers.update(tick)
end)

Event.add(defines.events.on_tick, function(event)
    Creeps.fly(event.tick)
end)

Event.on_nth_tick(30, function()
    Gui.update_all()
end)

-- pointing at a tower picks it in the panel
Event.on_nth_tick(10, function()
    for _, player in pairs(game.connected_players) do
        local selected = player.selected
        if selected and Towers.line_of_entity[selected.name] then
            Game.select(player, selected)
        end
    end
end)

-- clicking one does too, instead of opening the turret's own window
Event.add(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    if entity and entity.valid and entity.unit_number and Towers.get(entity.unit_number) then
        local player = game.get_player(event.player_index)
        player.opened = nil
        Game.select(player, entity)
        Gui.show(player)
    end
end)

Event.add(defines.events.on_ai_command_completed, Creeps.on_ai_command_completed)
Event.add(defines.events.on_entity_died, Creeps.on_entity_died)
Event.add(defines.events.on_built_entity, Game.on_built_entity)

Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    Game.join(player)
    Gui.show(player)
end)

return Layout.shape
