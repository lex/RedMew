-- High Stakes' saved state, shared by its modules.

local Global = require 'utils.global'

local Public = {}

Public.phases = {
    -- no one is seated yet
    waiting = 'waiting',
    -- players look at their cards, swap, and place their tower
    hand = 'hand',
    -- biters walk the plots
    wave = 'wave',
    -- the wave is over; the next hand starts soon
    break_ = 'break',
    -- the last wave is over; a new game starts soon
    over = 'over'
}

local function new_state()
    return {
        game = 1,
        phase = Public.phases.waiting,
        -- the round being played, 1 to #Settings.waves
        round = 0,
        -- the tick the phase ends
        phase_end = 0,
        -- seat -> player index
        seats = {},
        -- player index -> seat data (players.lua)
        players = {},
        -- unit number -> creep (waves.lua)
        creeps = {},
        -- how many of this wave's biters are still to come, for each seat
        to_spawn = {},
        -- unit number -> tower (towers.lua)
        towers = {},
        -- seat -> towers waiting for their player to place them
        pending = {},
        -- the last round's winners: { player indexes, hand score }
        last_winners = nil
    }
end

local this = new_state()

Global.register({ state = this }, function(tbl)
    this = tbl.state
end)

function Public.get()
    return this
end

--- Starts a new game: forgets everything but the game count and the table itself.
function Public.reset()
    local game = this.game
    local table_ready = this.table_ready
    for k in pairs(this) do
        this[k] = nil
    end
    for k, v in pairs(new_state()) do
        this[k] = v
    end
    this.game = game + 1
    this.table_ready = table_ready
end

return Public
