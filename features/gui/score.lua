local Global = require 'utils.global'
local Event = require 'utils.event'
local Token = require 'utils.token'
local Schedule = require 'utils.task'
local Gui = require 'utils.gui'
local Server = require 'features.server'
local ScoreTracker = require 'utils.score_tracker'
local format_number = require 'util'.format_number
local pairs = pairs
local min = math.min
local floor = math.floor
local format = string.format
local scores_to_show = storage.config.score.global_to_show
local score_goals = storage.config.score.goals or {}
local set_timeout_in_ticks = Schedule.set_timeout_in_ticks
local main_frame_name = Gui.uid_name()
local main_button_name = Gui.uid_name()

-- How the time left to a goal is estimated: the score is sampled once a game minute, and the
-- rate over the last ETA_WINDOW samples (at least ETA_MIN_SAMPLES of history) gives the estimate.
local ETA_SAMPLE_TICKS = 60 * 60
local ETA_WINDOW = 30
local ETA_MIN_SAMPLES = 5

local memory = {
    redraw_score_scheduled = false,
    -- score name => {ticks = {...}, values = {...}}, oldest first
    goal_history = {},
    player_last_position = {},
    player_death_causes = {}
}

Global.register(
    memory,
    function(tbl)
        memory = tbl
    end
)

---Estimated ticks until a score reaches its goal at its recent rate, or nil without enough history,
---progress or distance left
local function estimate_ticks_left(score_name, value, goal)
    local history = memory.goal_history and memory.goal_history[score_name]
    if not history or #history.ticks < ETA_MIN_SAMPLES or value >= goal then
        return nil
    end

    local elapsed = game.tick - history.ticks[1]
    local gained = value - history.values[1]
    if elapsed <= 0 or gained <= 0 then
        return nil
    end

    return (goal - value) * elapsed / gained
end

---Localised "1h 5m" / "5m", using the game's own time symbols
local function format_ticks_left(ticks)
    local minutes = floor(ticks / ETA_SAMPLE_TICKS + 0.5)
    local hours = floor(minutes / 60)
    minutes = minutes - hours * 60
    if hours > 0 then
        return {'', {'time-symbol-hours-short', hours}, ' ', {'time-symbol-minutes-short', minutes}}
    end
    return {'time-symbol-minutes-short', math.max(minutes, 1)}
end

---Creates a map of score name => {icon, name, value, tooltip, progress}, where progress (0 to 1) is
---only set for scores with a goal in storage.config.score.goals
local function get_global_score_labels()
    local scores = ScoreTracker.get_global_scores_with_metadata(scores_to_show)
    local score_labels = {}

    for index = 1, #scores do
        local score_data = scores[index]
        local value = score_data.value
        local goal = score_goals[score_data.name]

        if goal and goal > 0 then
            local progress = min(value / goal, 1)
            local tooltip = {'score.goal_tooltip', score_data.locale_string, format_number(value), format_number(goal), format('%.1f', progress * 100)}
            local ticks_left = estimate_ticks_left(score_data.name, value, goal)
            if ticks_left then
                tooltip = {'', tooltip, '\n', {'score.goal_eta', format_ticks_left(ticks_left)}}
            end
            score_labels[score_data.name] = {
                icon = score_data.icon,
                name = score_data.locale_string,
                value = format_number(value, true) .. ' / ' .. format_number(goal, true),
                tooltip = tooltip,
                progress = progress
            }
        else
            local tooltip = score_data.tooltip
            score_labels[score_data.name] = {
                icon = score_data.icon,
                name = score_data.locale_string,
                value = format_number(value, true),
                tooltip = tooltip and tooltip(value) or score_data.locale_string
            }
        end
    end

    return score_labels
end

-- A score's icon and value; its name is in its tooltip, as in the old strip in the top bar. A
-- score without an icon shows its name instead.
local function score_caption(textual_display)
    return {'', textual_display.icon or {'', textual_display.name, ':'}, ' ', textual_display.value}
end

local do_redraw_score =
    Token.register(
    function()
        local players = game.connected_players
        local scores = get_global_score_labels()

        for i = 1, #players do
            local player = players[i]
            local frame = Gui.get_panel(player, main_frame_name)

            if frame and frame.valid then
                local score_table = Gui.get_data(frame)
                for score_name, textual_display in pairs(scores) do
                    local value = score_table[score_name]
                    value.label.caption = score_caption(textual_display)
                    value.label.tooltip = textual_display.tooltip
                    if textual_display.progress then
                        value.bar.value = textual_display.progress
                        value.bar.tooltip = textual_display.tooltip
                    end
                end
            end
        end

        memory.redraw_score_scheduled = false
    end
)

local function schedule_redraw_score()
    if memory.redraw_score_scheduled then
        return
    end

    -- throttle redraws
    set_timeout_in_ticks(30, do_redraw_score)
    memory.redraw_score_scheduled = true
end

local function get_score_sprite()
    if script.active_mods['Krastorio2'] then
        return 'achievement/kr-matter-production-3'
    end
    if script.active_mods['space-exploration'] then
        return 'achievement/se-there-is-no-spoon'
    end
    return 'achievement/there-is-no-spoon'
end

local function player_created(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    Gui.add_top_element(player,
        {
            type = 'sprite-button',
            name = main_button_name,
            sprite = get_score_sprite(),
            tooltip = {'score.tooltip'},
            auto_toggle = true,
        }, 'score'
    )
end

-- A side panel with each score's icon and value in a grid, a few to a row so it stays short, and for
-- a score with a goal a progress bar toward it.
local function score_show(player)
    local frame, content = Gui.add_panel(player, { name = main_frame_name, caption = {'score.frame_title'}, toggle_name = main_button_name, width = 'narrow' })

    local score_table = content.add {type = 'table', column_count = 5}
    Gui.set_style(score_table, {vertical_spacing = 4, horizontal_spacing = 16})

    for score_name, textual_display in pairs(get_global_score_labels()) do
        local value = score_table.add {type = 'flow', name = score_name, direction = 'horizontal'}
        Gui.set_style(value, {vertical_align = 'center', horizontal_spacing = 8})
        value.add {type = 'label', name = 'label', caption = score_caption(textual_display), tooltip = textual_display.tooltip}
        if textual_display.progress then
            local bar = value.add {type = 'progressbar', name = 'bar', value = textual_display.progress, tooltip = textual_display.tooltip}
            Gui.set_style(bar, {width = 60})
        end
    end

    Gui.set_data(frame, score_table)
end

local function global_score_changed(event)
    local found = false
    for index = 1, #scores_to_show do
        if scores_to_show[index] then
            found = true
        end
    end

    if not found then
        return
    end

    schedule_redraw_score()

    if event.score_name ~= 'satellites-launched' then
        return
    end

    local count = ScoreTracker.get_for_global('satellites-launched')

    if (count < 10) or ((count < 50) and ((count % 5) == 0)) or ((count < 1000) and ((count % 25) == 0)) or ((count < 10000) and ((count % 100) == 0)) or ((count < 100000) and ((count % 1000) == 0))or ((count < 1000000) and ((count % 10000) == 0)) or ((count % 100000) == 0) then
        local message = 'A satellite has been launched! Total count: ' .. count

        game.print(message)
        Server.to_discord_bold(message)
    end
end

Gui.on_click(
    main_button_name,
    function(event)
        local player = event.player
        local frame = Gui.get_panel(player, main_frame_name)

        if frame then
            Gui.destroy(frame)
            Gui.get_top_element(player, main_button_name).toggled = false
        else
            score_show(player)
        end
    end
)

Gui.allow_player_to_toggle_top_element_visibility(main_button_name)

---Records each goal score once a game minute for the time-left estimate, keeping the last
---ETA_WINDOW samples, and refreshes the bar so the estimate keeps up even between launches
local function sample_goal_scores()
    local history_by_name = memory.goal_history
    if not history_by_name then
        history_by_name = {}
        memory.goal_history = history_by_name
    end

    local sampled = false
    for score_name, goal in pairs(score_goals) do
        if goal and goal > 0 then
            local history = history_by_name[score_name]
            if not history then
                history = {ticks = {}, values = {}}
                history_by_name[score_name] = history
            end

            local ticks, values = history.ticks, history.values
            ticks[#ticks + 1] = game.tick
            values[#values + 1] = ScoreTracker.get_for_global(score_name) or 0
            if #ticks > ETA_WINDOW then
                table.remove(ticks, 1)
                table.remove(values, 1)
            end
            sampled = true
        end
    end

    if sampled then
        schedule_redraw_score()
    end
end

Event.add(defines.events.on_player_created, player_created)
Event.add(ScoreTracker.events.on_global_score_changed, global_score_changed)
Event.on_nth_tick(ETA_SAMPLE_TICKS, sample_goal_scores)
