-- The High Stakes panel: the player's hand and what they can do with it, their chips, and the
-- table's standings.

local Cards = require 'map_gen.maps.high_stakes.cards'
local Event = require 'utils.event'
local Game = require 'map_gen.maps.high_stakes.game'
local Gui = require 'utils.gui'
local Settings = require 'map_gen.maps.high_stakes.settings'
local State = require 'map_gen.maps.high_stakes.state'
local Towers = require 'map_gen.maps.high_stakes.towers'
local Waves = require 'map_gen.maps.high_stakes.waves'

local phases = State.phases

local Public = {}

local main_button_name = Gui.uid_name()
local main_frame_name = Gui.uid_name()
local card_button_name = Gui.uid_name()
local swap_button_name = Gui.uid_name()
local play_button_name = Gui.uid_name()
local fold_button_name = Gui.uid_name()
local tip_button_name = Gui.uid_name()

local card_style = { width = 72, height = 64, font = 'default-large-bold', padding = 0 }
local action_style = { minimal_width = 100 }

local function time_text(seconds)
    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

local function status_caption()
    local state = State.get()
    local phase = state.phase
    local seconds = time_text(Game.seconds_left())
    if phase == phases.hand then
        return { 'high_stakes.status_hand', seconds }
    elseif phase == phases.wave then
        local left = Waves.count()
        for _, n in pairs(state.to_spawn) do
            left = left + n
        end
        return { 'high_stakes.status_wave', state.round, left }
    elseif phase == phases.break_ then
        return { 'high_stakes.status_break', seconds }
    elseif phase == phases.over then
        return { 'high_stakes.status_over', seconds }
    end
    return { 'high_stakes.status_waiting' }
end

-- what a player is doing this round, for the standings
local function player_status(data)
    if data.out then
        return { 'high_stakes.player_out_short' }
    elseif data.folded then
        return { 'high_stakes.player_folded' }
    elseif data.last_hand then
        return { '', Towers.hand_name(data.last_hand.type), ' ', data.last_hand.text }
    elseif data.hand and State.get().phase == phases.hand then
        return { 'high_stakes.player_thinking' }
    end
    return ''
end

local function add_section(content, caption)
    local frame = content.add { type = 'frame', style = 'inside_shallow_frame', direction = 'vertical' }
    local subheader = frame.add { type = 'frame', style = 'subheader_frame' }
    Gui.set_style(subheader, { horizontally_stretchable = true })
    local title = subheader.add { type = 'label', style = 'subheader_caption_label', caption = caption }
    Gui.add_pusher(subheader)
    local body = frame.add { type = 'flow', direction = 'vertical' }
    Gui.set_style(body, { padding = 8, vertical_spacing = 8 })
    return body, title, subheader
end

local function draw(content)
    local refs = {}

    local hand, status = add_section(content, '')
    refs.status = status

    local cards = hand.add { type = 'flow', direction = 'horizontal' }
    Gui.set_style(cards, { horizontal_spacing = 8, horizontal_align = 'center', horizontally_stretchable = true })
    refs.cards = {}
    for i = 1, 5 do
        -- siblings can't share a name: each card gets a flow of its own
        local button = cards.add { type = 'flow' }.add { type = 'button', name = card_button_name, caption = '' }
        Gui.set_style(button, card_style)
        Gui.set_data(button, i)
        refs.cards[i] = button
    end

    refs.best = hand.add { type = 'label', caption = '' }
    Gui.set_style(refs.best, { font = 'default-bold' })

    local actions = hand.add { type = 'flow', direction = 'horizontal' }
    Gui.set_style(actions, { horizontal_spacing = 8 })
    refs.swap = actions.add { type = 'button', name = swap_button_name, caption = { 'high_stakes.swap' } }
    refs.play = actions.add { type = 'button', name = play_button_name, style = 'confirm_button', caption = { 'high_stakes.play' }, tooltip = { 'high_stakes.play_tooltip' } }
    refs.fold = actions.add { type = 'button', name = fold_button_name, style = 'red_button', caption = '' }
    Gui.set_style(refs.swap, action_style)
    Gui.set_style(refs.play, action_style)
    Gui.set_style(refs.fold, action_style)

    local chips = hand.add { type = 'flow', direction = 'horizontal' }
    Gui.set_style(chips, { vertical_align = 'center', horizontal_spacing = 8 })
    refs.chips = chips.add { type = 'label', caption = '' }
    Gui.set_style(refs.chips, { font = 'default-bold' })
    Gui.add_pusher(chips)
    refs.tip = chips.add { type = 'button', name = tip_button_name, caption = { 'high_stakes.tip', Settings.tip_cost }, tooltip = { 'high_stakes.tip_tooltip' } }

    refs.message = hand.add { type = 'label', caption = '' }
    Gui.set_style(refs.message, { single_line = false, width = 400 })

    local standings = add_section(content, { 'high_stakes.standings' })
    refs.standings = standings

    Gui.set_data(content, refs)
    return refs
end

local function update_standings(parent)
    parent.clear()
    local state = State.get()
    local list = {}
    for _, data in pairs(state.players) do
        list[#list + 1] = data
    end
    table.sort(list, function(a, b)
        if a.chips ~= b.chips then
            return a.chips > b.chips
        end
        return a.seat < b.seat
    end)
    if #list == 0 then
        parent.add { type = 'label', caption = { 'high_stakes.no_players' } }
        return
    end
    local t = parent.add { type = 'table', column_count = 4, draw_horizontal_line_after_headers = true }
    Gui.set_style(t, { horizontal_spacing = 12, vertical_spacing = 4 })
    for _, caption in pairs({ { 'high_stakes.column_player' }, { 'high_stakes.column_chips' }, { 'high_stakes.column_towers' }, { 'high_stakes.column_hand' } }) do
        t.add { type = 'label', style = 'caption_label', caption = caption }
    end
    for _, data in ipairs(list) do
        local player = game.get_player(data.index)
        local name = t.add { type = 'label', caption = player and player.name or '?' }
        if player then
            Gui.set_style(name, { font_color = player.chat_color })
        end
        t.add { type = 'label', caption = data.chips }
        t.add { type = 'label', caption = Towers.count(data.seat) }
        local status = t.add { type = 'label', caption = player_status(data) }
        Gui.set_style(status, { maximal_width = 200 })
    end
end

local function update(player, refs)
    local state = State.get()
    local data = Game.get_player(player.index)
    refs.status.caption = { '', { 'high_stakes.round', state.round, #Settings.waves }, ' · ', status_caption() }

    local in_hand = data and Game.in_hand(data)
    local hand = data and data.hand
    local best = hand and Cards.evaluate(hand)
    local used = {}
    if best then
        for _, i in pairs(best.used) do
            used[i] = true
        end
    end
    for i, button in ipairs(refs.cards) do
        local card = hand and hand[i]
        button.caption = card and Cards.text(card) or ''
        button.enabled = card ~= nil and in_hand and not data.swapped or false
        button.toggled = card ~= nil and data.selected[i] or false
        button.tooltip = card and (used[i] and { 'high_stakes.card_in_hand' } or { 'high_stakes.card_tooltip' }) or ''
        Gui.set_style(button, { font_color = (card and used[i]) and { 0.1, 0.5, 0.1 } or { 0, 0, 0 } })
    end

    if best and not data.folded then
        refs.best.caption = { '', Towers.hand_name(best.type), ': ', Cards.hand_text(hand, best) }
    else
        refs.best.caption = ''
    end

    local selected = data and table_size(data.selected) or 0
    refs.swap.caption = selected > 0 and { 'high_stakes.swap_count', selected } or { 'high_stakes.swap' }
    refs.swap.enabled = in_hand and not data.swapped and selected > 0 or false
    refs.swap.tooltip = (data and data.swapped) and { 'high_stakes.swap_used' } or { 'high_stakes.swap_tooltip', Settings.max_swap }
    refs.play.enabled = in_hand or false
    refs.fold.caption = { 'high_stakes.fold', data and data.folds_left or 0 }
    refs.fold.enabled = in_hand and data.folds_left > 0 or false
    refs.fold.tooltip = { 'high_stakes.fold_tooltip', Settings.max_folds }

    if data then
        refs.chips.caption = { 'high_stakes.chips', data.chips, data.tips }
        refs.tip.enabled = not data.out and data.chips >= Settings.tip_cost and data.tips < Cards.max_tips
    else
        refs.chips.caption = ''
        refs.tip.enabled = false
    end

    local message = ''
    if not data then
        message = Game.can_join() and { 'high_stakes.message_can_join' } or { 'high_stakes.message_watching' }
    elseif data.out then
        message = { 'high_stakes.message_out' }
    elseif #(state.pending[data.seat] or {}) > 0 then
        message = { 'high_stakes.message_place' }
    elseif in_hand then
        message = data.swapped and { 'high_stakes.message_play' } or { 'high_stakes.message_swap' }
    end
    refs.message.caption = message
    refs.message.visible = message ~= ''

    update_standings(refs.standings)
end

local function open(player)
    local frame, content = Gui.add_panel(player, {
        name = main_frame_name,
        caption = { 'high_stakes.panel_title' },
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

--- Opens the panel, if it isn't open.
function Public.show(player)
    if not Gui.get_panel(player, main_frame_name) then
        open(player)
    end
end

--- Brings a player's open panel up to date.
function Public.refresh(player)
    local frame = Gui.get_panel(player, main_frame_name)
    if frame then
        update(player, Gui.get_data(frame))
    end
end

local function refresh_index(player_index)
    if player_index then
        local player = game.get_player(player_index)
        if player then
            Public.refresh(player)
        end
    end
    -- everyone else's panels catch up on the next update
end

Game.set_refresh(refresh_index)

--- Refreshes every open panel; opens seated players' panels when a hand starts.
function Public.update_all(open_for_hand)
    for _, player in pairs(game.connected_players) do
        if open_for_hand and Game.get_player(player.index) then
            Public.show(player)
        end
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

Gui.on_click(card_button_name, function(event)
    Game.toggle_card(event.player_index, Gui.get_data(event.element))
end)

Gui.on_click(swap_button_name, function(event)
    Game.swap(event.player_index)
end)

Gui.on_click(play_button_name, function(event)
    Game.play(event.player_index)
end)

Gui.on_click(fold_button_name, function(event)
    Game.fold(event.player_index)
end)

Gui.on_click(tip_button_name, function(event)
    if Game.tip(event.player_index) then
        event.player.print({ 'high_stakes.tipped', Game.get_player(event.player_index).tips })
    end
end)

Gui.allow_player_to_toggle_top_element_visibility(main_button_name)

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    Gui.add_top_element(player, {
        name = main_button_name,
        type = 'sprite-button',
        sprite = 'virtual-signal/signal-heart',
        tooltip = { 'high_stakes.panel_tooltip' },
        auto_toggle = true
    })
end)

return Public
