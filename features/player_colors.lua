local Event = require 'utils.event'
local Server = require 'features.server'
local Token = require 'utils.token'
local Settings = require 'utils.redmew_settings'
local Color = require 'resources.color_presets'
local SettingTypes = require 'resources.setting_types'

local player_color_name = 'player-color'
local player_chat_color_shared_name = 'player-chat-color-shared'
local player_chat_color_name = 'player-chat-color'

local function same_color(a, b)
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
end

-- players who already saved a chat color unlike their character color keep both
local function chat_color_shared_by_default(player_index)
    local color = Settings.get(player_index, player_color_name)
    local chat_color = Settings.get(player_index, player_chat_color_name)
    return not (color and chat_color and not same_color(color, chat_color))
end

local function is_chat_color_shared(player_index)
    return Settings.get(player_index, player_chat_color_shared_name)
end

-- a shared chat color is the character color, brightened if it is too dark to read in chat
local readable_chat_color = SettingTypes.chat_color.readable

-- registered in the order the settings window lists them
Settings.register(player_color_name, Settings.types.color, nil, 'player_colors.player_color_setting_label')
local shared_setting = Settings.register(player_chat_color_shared_name, Settings.types.boolean, chat_color_shared_by_default, 'player_colors.chat_color_shared_setting_label')
-- while ticked, the settings window hides the chat color
shared_setting.hides = player_chat_color_name
Settings.register(player_chat_color_name, Settings.types.chat_color, nil, 'player_colors.player_chat_color_setting_label')

local Public = {}

Public.setting_names = {
    color = player_color_name,
    chat_color = player_chat_color_name,
    chat_color_shared = player_chat_color_shared_name,
}

-- left in for migration purposes, remove at a later point
local color_callback = Token.register(function(data)
    local key = data.key
    local value = data.value

    if not value then
        return
    end

    local player = game.get_player(key)
    if not player then
        return
    end

    Settings.set(player.index, player_color_name, value.color)
    Settings.set(player.index, player_chat_color_name, value.chat_color)

end)

local function setting_set(event)
    local value = event.new_value
    if value == nil then
        return
    end

    local setting_name = event.setting_name
    if setting_name ~= player_color_name and setting_name ~= player_chat_color_name and setting_name ~= player_chat_color_shared_name then
        return
    end

    local player_index = event.player_index
    local player = game.get_player(player_index)
    if not player or not player.valid then
        return
    end

    -- settings synced from the server arrive one at a time in any order, so each one leaves the
    -- chat color as the settings so far say
    if setting_name == player_color_name then
        player.color = value
        if is_chat_color_shared(player_index) then
            player.chat_color = readable_chat_color(value)
        end
    elseif setting_name == player_chat_color_name then
        if not is_chat_color_shared(player_index) then
            player.chat_color = value
        end
    elseif value then
        player.chat_color = readable_chat_color(player.color)
    else
        local chat_color = Settings.get(player_index, player_chat_color_name)
        if chat_color then
            player.chat_color = chat_color
        end
    end
end

local function player_joined_game(event)
    local player_index = event.player_index
    local player = game.get_player(player_index)
    if not player or not player.valid then
        return
    end

    -- already migrated
    if Settings.get(player_index, player_color_name) then
        return
    end

    Server.try_get_data('colors', player.name, color_callback)
end

local function on_command(event)
    local player_index = event.player_index
    if not player_index or event.command ~= 'color' then
        return
    end

    local player = game.get_player(player_index)
    if not player or not player.valid then
        return
    end

    player.print({'player_colors.gui_setting_reference_message'}, {color = Color.success})
    Settings.set(player_index, player_color_name, player.color)

    local error = Settings.validate(player_chat_color_name, player.chat_color)
    if not error then
        Settings.set(player_index, player_chat_color_name, player.chat_color)
    end
end

Event.add(defines.events.on_player_joined_game, player_joined_game)
Event.add(Settings.events.on_setting_set, setting_set)
Event.add(defines.events.on_console_command, on_command)

return Public
