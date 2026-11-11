-- The Convergence panel: the wave and the lives, the player's gold, the tower shop, the tower
-- they picked (point at one, or click it) with its upgrade and sell buttons, and the team.

local Event = require 'utils.event'
local Game = require 'map_gen.maps.convergence.game'
local Gui = require 'utils.gui'
local Settings = require 'map_gen.maps.convergence.settings'
local State = require 'map_gen.maps.convergence.state'
local Towers = require 'map_gen.maps.convergence.towers'
local Creeps = require 'map_gen.maps.convergence.creeps'

local phases = State.phases

local Public = {}

local main_button_name = Gui.uid_name()
local main_frame_name = Gui.uid_name()
-- a name for each line's shop button: siblings can't share one
local buy_button_names = {}
for _, name in ipairs(Settings.line_order) do
    buy_button_names[name] = Gui.uid_name()
end
local call_button_name = Gui.uid_name()
local upgrade_button_name = Gui.uid_name()
local sell_button_name = Gui.uid_name()

local function time_text(seconds)
    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

local function per_second(stats)
    return math.floor(stats.damage * 60 / stats.cooldown + 0.5)
end

-- what a level of a line does, for tooltips and the selected tower
local function stats_text(line_name, stats, aura)
    local line = Settings.lines[line_name]
    if line_name == 'beacon' then
        return { 'convergence.stats_beacon', math.floor(stats.aura * 100 + 0.5), stats.range }
    end
    local damage = per_second(stats)
    if aura and aura > 0 then
        damage = math.floor(damage * (1 + aura) + 0.5)
    end
    local text = { 'convergence.stats', damage, stats.range, { 'convergence.targets_' .. line.targets } }
    if line_name == 'cryo' then
        text = { '', text, ' ', { 'convergence.stats_slow', math.floor(stats.slow * 100 + 0.5) } }
    end
    return text
end

local function status_caption()
    local state = State.get()
    local phase = state.phase
    if phase == phases.break_ then
        return { 'convergence.status_break', state.wave + 1, time_text(Game.seconds_left()) }
    elseif phase == phases.wave then
        local left = Creeps.count()
        for _, n in pairs(state.to_spawn) do
            left = left + n
        end
        return { 'convergence.status_wave', state.wave, left }
    elseif phase == phases.over then
        return { state.won and 'convergence.status_won' or 'convergence.status_lost', time_text(Game.seconds_left()) }
    end
    return { 'convergence.status_waiting' }
end

local function add_section(content, caption)
    local frame = content.add { type = 'frame', style = 'inside_shallow_frame', direction = 'vertical' }
    local subheader = frame.add { type = 'frame', style = 'subheader_frame' }
    Gui.set_style(subheader, { horizontally_stretchable = true })
    local title = subheader.add { type = 'label', style = 'subheader_caption_label', caption = caption }
    local body = frame.add { type = 'flow', direction = 'vertical' }
    Gui.set_style(body, { padding = 8, vertical_spacing = 8 })
    return body, title, subheader
end

local function draw(content)
    local refs = {}

    local status, title, subheader = add_section(content, '')
    refs.status = title
    Gui.add_pusher(subheader)
    refs.call = subheader.add { type = 'button', name = call_button_name, style = 'tool_button', caption = { 'convergence.call' }, tooltip = { 'convergence.call_tooltip' } }
    Gui.set_style(refs.call, { width = 0, minimal_width = 60 })
    local row = status.add { type = 'flow', direction = 'horizontal' }
    Gui.set_style(row, { horizontal_spacing = 24 })
    refs.lives = row.add { type = 'label', caption = '' }
    refs.gold = row.add { type = 'label', caption = '' }
    Gui.set_style(refs.lives, { font = 'default-bold' })
    Gui.set_style(refs.gold, { font = 'default-bold' })

    local shop = add_section(content, { 'convergence.shop' })
    local slots = shop.add { type = 'frame', style = 'slot_button_deep_frame' }
    local t = slots.add { type = 'table', column_count = #Settings.line_order, style = 'filter_slot_table' }
    refs.buy = {}
    for _, name in ipairs(Settings.line_order) do
        local line = Settings.lines[name]
        local button = t.add { type = 'sprite-button', name = buy_button_names[name], sprite = 'item/' .. line.entity, style = 'slot_button', number = line.levels[1].cost }
        refs.buy[name] = button
    end
    local hint = shop.add { type = 'label', caption = { 'convergence.shop_hint' } }
    Gui.set_style(hint, { single_line = false, width = 420 })

    local selected, selected_title = add_section(content, { 'convergence.tower' })
    refs.tower_title = selected_title
    refs.tower_stats = selected.add { type = 'label', caption = '' }
    Gui.set_style(refs.tower_stats, { single_line = false, width = 420 })
    local actions = selected.add { type = 'flow', direction = 'horizontal' }
    Gui.set_style(actions, { horizontal_spacing = 8 })
    refs.upgrade = actions.add { type = 'button', name = upgrade_button_name, style = 'confirm_button', caption = '' }
    refs.sell = actions.add { type = 'button', name = sell_button_name, style = 'red_button', caption = '' }
    Gui.set_style(refs.upgrade, { minimal_width = 160 })
    Gui.set_style(refs.sell, { minimal_width = 120 })

    refs.team = add_section(content, { 'convergence.team' })
    return refs
end

local function update_team(parent)
    parent.clear()
    local list = {}
    for _, data in pairs(State.get().players) do
        list[#list + 1] = data
    end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then
            return a.kills > b.kills
        end
        return a.index < b.index
    end)
    local t = parent.add { type = 'table', column_count = 4, draw_horizontal_line_after_headers = true }
    Gui.set_style(t, { horizontal_spacing = 16, vertical_spacing = 4 })
    for _, key in pairs({ 'column_player', 'column_lane', 'column_gold', 'column_kills' }) do
        t.add { type = 'label', style = 'caption_label', caption = { 'convergence.' .. key } }
    end
    for _, data in ipairs(list) do
        local player = game.get_player(data.index)
        local name = t.add { type = 'label', caption = player and player.name or '?' }
        if player then
            Gui.set_style(name, { font_color = player.chat_color })
        end
        t.add { type = 'label', caption = data.seat or '-' }
        t.add { type = 'label', caption = data.gold }
        t.add { type = 'label', caption = data.kills }
    end
end

local function update(player, refs)
    local state = State.get()
    local data = Game.get_player(player.index)
    refs.status.caption = status_caption()
    refs.call.visible = state.phase == phases.break_ and state.wave > 0
    refs.lives.caption = { 'convergence.lives', state.lives }
    refs.gold.caption = { 'convergence.gold', data and data.gold or 0 }

    for name, button in pairs(refs.buy) do
        local line = Settings.lines[name]
        local first = line.levels[1]
        button.enabled = data ~= nil and data.gold >= first.cost and state.phase ~= phases.over
        button.tooltip = { '', '[font=default-bold]', Towers.line_name(name), '[/font]\n', { 'convergence.line_' .. name .. '_description' }, '\n', stats_text(name, first), '\n', { 'convergence.cost', first.cost } }
    end

    local tower = Game.selected_tower(player.index)
    if tower then
        local stats = Towers.level_stats(tower)
        local owner = game.get_player(tower.owner)
        refs.tower_title.caption = { 'convergence.tower_title', Towers.line_name(tower.line), tower.level, owner and owner.name or '?' }
        refs.tower_stats.caption = stats_text(tower.line, stats, tower.aura)
        local cost = Towers.upgrade_cost(tower)
        local mine = tower.owner == player.index
        refs.upgrade.visible = true
        refs.sell.visible = true
        refs.upgrade.caption = cost and { 'convergence.upgrade', cost } or { 'convergence.max_level' }
        refs.upgrade.enabled = mine and cost ~= nil and data ~= nil and data.gold >= cost
        if cost then
            local next_stats = Settings.lines[tower.line].levels[tower.level + 1]
            refs.upgrade.tooltip = { '', { 'convergence.next_level' }, '\n', stats_text(tower.line, next_stats, tower.aura) }
        else
            refs.upgrade.tooltip = ''
        end
        refs.sell.caption = { 'convergence.sell', Towers.sell_value(tower) }
        refs.sell.enabled = mine
        refs.sell.tooltip = mine and '' or { 'convergence.not_yours' }
    else
        refs.tower_title.caption = { 'convergence.tower' }
        refs.tower_stats.caption = { 'convergence.pick_tower' }
        refs.upgrade.visible = false
        refs.sell.visible = false
    end

    update_team(refs.team)
end

local function open(player)
    local frame, content = Gui.add_panel(player, {
        name = main_frame_name,
        caption = { 'convergence.panel_title' },
        toggle_name = main_button_name,
        width = 'wide',
        sections = true
    })
    local refs = draw(content)
    Gui.set_data(frame, refs)
    update(player, refs)
    local button = Gui.get_top_element(player, main_button_name)
    if button then
        button.toggled = true
    end
end

local function close(player)
    local frame = Gui.get_panel(player, main_frame_name)
    if frame then
        Gui.destroy(frame)
    end
    local button = Gui.get_top_element(player, main_button_name)
    if button then
        button.toggled = false
    end
end

function Public.show(player)
    if not Gui.get_panel(player, main_frame_name) then
        open(player)
    end
end

function Public.refresh(player)
    local frame = Gui.get_panel(player, main_frame_name)
    if frame then
        update(player, Gui.get_data(frame))
    end
end

Game.set_refresh(function(player_index)
    if player_index then
        local player = game.get_player(player_index)
        if player then
            Public.refresh(player)
        end
    end
end)

--- Brings every open panel up to date.
function Public.update_all()
    for _, player in pairs(game.connected_players) do
        Public.refresh(player)
    end
end

Gui.on_click(main_button_name, function(event)
    if Gui.get_panel(event.player, main_frame_name) then
        close(event.player)
    else
        open(event.player)
    end
end)

for line_name, button_name in pairs(buy_button_names) do
    Gui.on_click(button_name, function(event)
        if not Game.buy(event.player_index, line_name) then
            event.player.print({ 'convergence.cant_buy' })
        end
    end)
end

Gui.on_click(call_button_name, function(event)
    Game.call_wave(event.player_index)
end)

Gui.on_click(upgrade_button_name, function(event)
    Game.upgrade(event.player_index)
end)

Gui.on_click(sell_button_name, function(event)
    Game.sell(event.player_index)
end)

Gui.allow_player_to_toggle_top_element_visibility(main_button_name)

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    Gui.add_top_element(player, {
        name = main_button_name,
        type = 'sprite-button',
        sprite = 'item/gun-turret',
        tooltip = { 'convergence.panel_tooltip' },
        auto_toggle = true
    })
end)

return Public
