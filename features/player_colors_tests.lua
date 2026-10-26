-- Tests for the shared chat color: while a player's chat color is shared, it follows their
-- character color, and the chat color they saved waits until they untick it. Discovered whenever
-- features.player_colors is loaded (config.player_colors). The settings go through
-- Settings.set, so every handler sees them as it would from the settings window or a sync from
-- the server; the player is a stand-in, returned by a swapped `game`, so they run headless.
local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Helper = require 'utils.test.helper'
local Settings = require 'utils.redmew_settings'
local PlayerColors = require 'features.player_colors'

local names = PlayerColors.setting_names

-- an index no real player has, so the stand-in's settings don't touch anyone's
local player_index = 4000

local red = { r = 255, g = 0, b = 0, a = 255 }
local green = { r = 0, g = 255, b = 0, a = 255 }
local yellow = { r = 255, g = 255, b = 0, a = 255 }
local white = { r = 255, g = 255, b = 255, a = 255 }
-- too dark to read in chat
local dark_red = { r = 40, g = 0, b = 0, a = 255 }

-- chat would refuse it if it were set as the chat color
local function assert_readable_red(chat_color)
    Assert.is_nil(Settings.validate(names.chat_color, chat_color), 'chat color readable: ' .. serpent.line(chat_color))
    Assert.is_true(chat_color.r > dark_red.r and chat_color.g == 0 and chat_color.b == 0, 'still red: ' .. serpent.line(chat_color))
end

-- a stand-in player whose colors the handlers set, returned by game.get_player
local function stand_in_player(context)
    local player = { valid = true, index = player_index, name = 'test runner', color = white, chat_color = white, gui = { screen = {} } }

    local real_game = game
    local proxy = setmetatable({
        get_player = function(index)
            if index == player_index then
                return player
            end
            return real_game.get_player(index)
        end,
    }, { __index = real_game })
    Helper.modify_global(context, 'game', proxy)

    context:add_teardown(function()
        local settings = Settings.all(player_index)
        for name in pairs(settings) do
            settings[name] = nil
        end
    end)

    return player
end

Declare.module({ 'features', 'player colors' }, function()
    Declare.module('shared chat color', function()
        Declare.test('chat follows the character color', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, true)

            -- Act
            Settings.set(player_index, names.color, red)

            -- Assert
            Assert.table_equal(red, player.color, 'character color')
            Assert.table_equal(red, player.chat_color, 'chat color')
        end)

        Declare.test('a saved chat color waits while shared', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, true)
            Settings.set(player_index, names.color, red)

            -- Act
            Settings.set(player_index, names.chat_color, yellow)

            -- Assert
            Assert.table_equal(red, player.chat_color, 'chat color')
        end)

        Declare.test('ticking it gives chat the character color', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, false)
            Settings.set(player_index, names.color, red)
            Settings.set(player_index, names.chat_color, yellow)

            -- Act
            Settings.set(player_index, names.chat_color_shared, true)

            -- Assert
            Assert.table_equal(red, player.chat_color, 'chat color')
        end)

        Declare.test('a character color too dark for chat is brightened for chat', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, true)

            -- Act
            Settings.set(player_index, names.color, dark_red)

            -- Assert
            Assert.table_equal(dark_red, player.color, 'character color')
            assert_readable_red(player.chat_color)
        end)

        Declare.test('ticking it with a dark character color brightens it for chat', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, false)
            Settings.set(player_index, names.color, dark_red)

            -- Act
            Settings.set(player_index, names.chat_color_shared, true)

            -- Assert
            assert_readable_red(player.chat_color)
        end)

        Declare.test('unticking it brings back the saved chat color', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, true)
            Settings.set(player_index, names.color, red)
            Settings.set(player_index, names.chat_color, yellow)

            -- Act
            Settings.set(player_index, names.chat_color_shared, false)

            -- Assert
            Assert.table_equal(yellow, player.chat_color, 'chat color')
        end)
    end)

    Declare.module('separate chat color', function()
        Declare.test('chat keeps its own color when the character color changes', function(context)
            -- Arrange
            local player = stand_in_player(context)
            Settings.set(player_index, names.chat_color_shared, false)
            Settings.set(player_index, names.chat_color, yellow)

            -- Act
            Settings.set(player_index, names.color, red)

            -- Assert
            Assert.table_equal(red, player.color, 'character color')
            Assert.table_equal(yellow, player.chat_color, 'chat color')
        end)
    end)

    Declare.module('shared by default', function()
        Declare.test('when no colors are saved', function(context)
            -- Arrange
            stand_in_player(context)

            -- Act
            local shared = Settings.get(player_index, names.chat_color_shared)

            -- Assert
            Assert.equal(true, shared, 'shared')
        end)

        Declare.test('when the saved colors are the same', function(context)
            -- Arrange
            stand_in_player(context)
            Settings.set(player_index, names.color, green)
            Settings.set(player_index, names.chat_color, green)

            -- Act
            local shared = Settings.get(player_index, names.chat_color_shared)

            -- Assert
            Assert.equal(true, shared, 'shared')
        end)

        Declare.test('but not when the saved colors differ', function(context)
            -- Arrange
            stand_in_player(context)
            Settings.set(player_index, names.color, red)
            Settings.set(player_index, names.chat_color, yellow)

            -- Act
            local shared = Settings.get(player_index, names.chat_color_shared)

            -- Assert
            Assert.equal(false, shared, 'shared')
        end)
    end)
end)
