-- The numbers that balance High Stakes: rounds, chips, waves and towers.

local Cards = require 'map_gen.maps.high_stakes.cards'

local types = Cards.hand_types

local Public = {}

-- Players who can sit at the table: one plot each.
Public.seats = 8

Public.starting_chips = 25
Public.tip_cost = 10
-- folds a player has for the whole game: a fold skips the player's wave, and their tower
Public.max_folds = 3
-- how many cards a swap can replace, once a hand
Public.max_swap = 4

-- the hand phase: seconds to look at the cards, swap and place the tower
Public.hand_seconds = 45
-- seconds between a wave's end and the next hand
Public.break_seconds = 5
-- a wave ends early once its last biter is gone; this ends it anyway, removing what's left
Public.max_wave_seconds = 240
-- seconds after the last wave before a new game starts
Public.game_over_seconds = 60
-- newcomers get a seat until this round; after it, they watch until the next game
Public.last_round_to_join = 5

-- the best hand of a round wins chips: 5, and 5 more every sixth round
function Public.hand_bonus(round)
    return 5 + math.floor((round + 1) / 6) * 5
end

-- Waves -----------------------------------------------------------------------------------

-- biters a wave sends at each player, one every spawn_interval ticks; a boss wave sends one
Public.wave_size = 12
Public.spawn_interval = 120
-- tiles a tick
Public.biter_speed = 0.1
-- A biter's health is health_factor * health ^ health_exponent, health being the wave's below.
-- The exponent flattens the climb from the first wave to the last (from 150 to 45000 below, 13 to
-- 723 here), so towers, which come one a round, can keep up; the factor is the difficulty.
Public.health_factor = 0.4
Public.health_exponent = 0.7

function Public.biter_health(wave)
    return Public.health_factor * wave.health ^ Public.health_exponent
end

-- health: what the towers' damage has to get through. loot: the chips a biter steals when it
-- reaches the vault. bounty: the chips it pays when killed.
local function wave(unit, health, loot, bounty, boss)
    return { unit = unit, health = health, loot = loot, bounty = bounty, boss = boss or false }
end

Public.waves = {
    wave('small-biter', 150, 1, 1),
    wave('small-spitter', 250, 1, 1),
    wave('small-biter', 400, 1, 1),
    wave('small-spitter', 600, 1, 1),
    wave('small-biter', 750, 1, 1),
    wave('medium-biter', 3000, 5, 10, true),
    wave('medium-biter', 1000, 5, 2),
    wave('medium-spitter', 1500, 5, 2),
    wave('medium-biter', 1900, 5, 2),
    wave('medium-spitter', 2300, 5, 2),
    wave('medium-biter', 2700, 5, 2),
    wave('big-biter', 8000, 20, 20, true),
    wave('big-biter', 3800, 10, 3),
    wave('big-spitter', 4400, 10, 3),
    wave('big-biter', 5000, 10, 3),
    wave('big-spitter', 5600, 10, 3),
    wave('big-biter', 6200, 10, 3),
    wave('behemoth-biter', 16000, 40, 30, true),
    wave('behemoth-spitter', 7000, 20, 4),
    wave('behemoth-biter', 7800, 20, 4),
    wave('behemoth-spitter', 8600, 20, 4),
    wave('behemoth-biter', 9400, 20, 4),
    wave('behemoth-spitter', 9000, 20, 4),
    wave('behemoth-biter', 28000, 60, 40, true),
    wave('behemoth-spitter', 10200, 30, 5),
    wave('behemoth-biter', 11000, 30, 5),
    wave('behemoth-spitter', 12000, 30, 5),
    wave('behemoth-biter', 13000, 30, 5),
    wave('behemoth-spitter', 14000, 30, 5),
    wave('behemoth-biter', 45000, 100, 50, true)
}

-- The last boss wrecks a tower now and then while it lives: four of a kind first.
Public.wrecker_interval = 10 * 60

-- Towers ----------------------------------------------------------------------------------

-- Each hand makes one tower. entity: what it looks like (the turret does nothing itself).
-- damage: per hit, as a function of the hand's rank. cooldown: ticks between hits. range: tiles.
-- effect: what else a hit does (towers.lua).
Public.towers = {
    [types.high_card] = {
        entity = 'gun-turret',
        cooldown = 108,
        range = 7,
        damage = function(rank)
            return rank + 1
        end
    },
    [types.pair] = {
        entity = 'gun-turret',
        cooldown = 72,
        range = 8,
        damage = function(rank)
            return rank + 16
        end
    },
    [types.two_pair] = {
        entity = 'gun-turret',
        cooldown = 60,
        range = 8,
        damage = function(rank)
            return rank + 28
        end
    },
    [types.three_of_a_kind] = {
        entity = 'laser-turret',
        cooldown = 42,
        range = 9.5,
        damage = function(rank)
            return rank + 34
        end
    },
    [types.straight] = {
        entity = 'laser-turret',
        cooldown = 30,
        range = 11,
        damage = function(rank)
            return rank + 40
        end
    },
    [types.flush] = {
        entity = 'flamethrower-turret',
        cooldown = 30,
        range = 11,
        effect = 'slow',
        damage = function(rank)
            return rank + 44
        end
    },
    [types.full_house] = {
        entity = 'flamethrower-turret',
        cooldown = 30,
        range = 11,
        effect = 'frost',
        damage = function(rank)
            return 2 * rank + 49
        end
    },
    [types.four_of_a_kind] = {
        entity = 'artillery-turret',
        cooldown = 30,
        range = 11,
        effect = 'stun',
        damage = function(rank)
            return 2 * rank + 58
        end
    },
    [types.straight_flush] = {
        entity = 'artillery-turret',
        cooldown = 24,
        range = 14,
        effect = 'critical',
        damage = function(rank)
            return 2 * rank + 113
        end
    }
}

-- A high card's suit changes how it attacks. damage: multiplies the tower's. range: adds to it.
Public.suits = {
    [Cards.suits.crosshair] = { cooldown = 90 },
    [Cards.suits.lightning] = { effect = 'chain', damage = 1.2, cooldown = 96 },
    [Cards.suits.fire] = { effect = 'burn', damage = 1.3 },
    [Cards.suits.explosion] = { effect = 'splash', damage = 1.2, range = 3 }
}

-- effect numbers
Public.chain_jumps = 2
Public.chain_falloff = 0.6
Public.chain_radius = 5
Public.burn_ticks = 180
Public.burn_share = 0.5
Public.splash_radius = 2
Public.splash_share = 0.5
Public.slow_factor = 0.6
Public.slow_ticks = 120
Public.frost_radius = 2.5
Public.stun_chance = 0.15
Public.stun_ticks = 60
Public.critical_chance = 0.2
Public.critical_factor = 2.5

-- the colour of a tower's label and of its shots
Public.tower_colors = {
    [types.high_card] = { 0.9, 0.9, 0.9 },
    [types.pair] = { 0.5, 0.8, 1 },
    [types.two_pair] = { 0.4, 0.6, 1 },
    [types.three_of_a_kind] = { 0.4, 1, 0.5 },
    [types.straight] = { 0.3, 0.9, 0.3 },
    [types.flush] = { 1, 0.8, 0.3 },
    [types.full_house] = { 1, 0.6, 0.2 },
    [types.four_of_a_kind] = { 1, 0.35, 0.35 },
    [types.straight_flush] = { 1, 0.3, 1 }
}

return Public
