-- Convergence's saved state, shared by its modules.

local Global = require 'utils.global'
local Settings = require 'map_gen.maps.convergence.settings'

local Public = {}

Public.phases = {
    -- no one is seated yet
    waiting = 'waiting',
    -- counting down to the next wave
    break_ = 'break',
    -- a wave is on the map
    wave = 'wave',
    -- won or lost; a new game starts soon
    over = 'over'
}

local function new_state()
    return {
        game = 1,
        phase = Public.phases.waiting,
        -- the last wave sent, 0 before the first
        wave = 0,
        -- the tick the phase ends
        phase_end = 0,
        lives = Settings.lives,
        won = false,
        -- seat -> player index
        seats = {},
        -- player index -> { index, seat, gold, kills, spent, selected (tower id) }
        players = {},
        -- unit number -> creep (creeps.lua)
        creeps = {},
        -- seat -> biters of this wave still to come down that lane
        to_spawn = {},
        next_spawn = 0,
        -- unit number -> tower (towers.lua)
        towers = {},
        -- player index -> list of { line } waiting to be placed
        pending = {},
        -- gold the waves so far have paid each player, for latecomers
        paid = 0
    }
end

local this = new_state()

Global.register({ state = this }, function(tbl)
    this = tbl.state
end)

function Public.get()
    return this
end

--- Starts a new game: forgets everything but the game count and the map's setup.
function Public.reset()
    local game = this.game
    local ready = this.map_ready
    for k in pairs(this) do
        this[k] = nil
    end
    for k, v in pairs(new_state()) do
        this[k] = v
    end
    this.game = game + 1
    this.map_ready = ready
end

return Public
