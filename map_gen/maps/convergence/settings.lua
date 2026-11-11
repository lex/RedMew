-- The numbers that balance Convergence: lives, gold, waves and towers.

local Public = {}

-- The team's lives: each biter that reaches the core takes one.
Public.lives = 50
-- Gold each player starts with; a player joining late gets what the waves so far have paid too.
Public.starting_gold = 150
-- Gold each player gets when a wave is cleared.
function Public.wave_bonus(wave)
    return 10 + 2 * wave
end
-- A sold tower gives back this share of what was spent on it.
Public.sell_share = 0.75

-- Seconds before the first wave, and between a wave's end and the next.
Public.first_wave_seconds = 90
Public.break_seconds = 15
-- Seconds after the game is won or lost before a new one starts.
Public.game_over_seconds = 60

-- Waves -----------------------------------------------------------------------------------

-- Biters a wave sends down each seat's lane, one every spawn_interval ticks; bosses come two.
Public.wave_size = 20
Public.boss_size = 2
Public.spawn_interval = 30
-- Tiles a tick: ground biters, and the robots of air waves.
Public.ground_speed = 0.15
Public.air_speed = 0.12
-- Multiplies every biter's health: the difficulty.
Public.health_factor = 1

-- Every wave_kind-th wave is special: air waves fly (only some towers reach them), shielded waves
-- shrug off slows and traps, regenerating waves heal, and boss waves send two big biters.
local air_waves = { [7] = true, [14] = true, [21] = true, [28] = true, [35] = true, [42] = true, [49] = true, [56] = true }
local boss_waves = { [15] = true, [30] = true, [45] = true, [60] = true }
local regen_waves = { [13] = true, [26] = true, [39] = true, [52] = true }

-- what a wave's biters look like, by how far into the game it is
local function ground_unit(wave, boss)
    local tier = math.min(4, math.floor((wave - 1) / 15) + 1 + (boss and 1 or 0))
    local sizes = { 'small', 'medium', 'big', 'behemoth' }
    local kind = (wave % 2 == 0) and 'spitter' or 'biter'
    return sizes[tier] .. '-' .. kind
end

local function air_unit(wave)
    if wave < 20 then
        return 'defender'
    elseif wave < 40 then
        return 'distractor'
    end
    return 'destroyer'
end

-- health of one of a wave's biters: 35 at first, a tenth more each wave (about 9800 by the 60th)
local function health(wave)
    return math.floor(35 * 1.1 ^ (wave - 1))
end

-- gold a wave's biter pays when killed
local function bounty(wave)
    return 2 + math.floor(wave / 4)
end

Public.waves = {}
for wave = 1, 60 do
    local boss = boss_waves[wave] or false
    local air = air_waves[wave] or false
    local w = {
        boss = boss,
        air = air,
        shielded = (wave % 5 == 0) and not boss,
        regen = regen_waves[wave] and 0.02 or nil,
        count = boss and Public.boss_size or Public.wave_size,
        health = health(wave) * (boss and 12 or 1) * (air and 0.8 or 1),
        bounty = bounty(wave) * (boss and 12 or 1)
    }
    w.unit = air and air_unit(wave) or ground_unit(wave, boss)
    Public.waves[wave] = w
end

--- A biter's health in a wave, with the difficulty.
function Public.biter_health(wave)
    return Public.health_factor * Public.waves[wave].health
end

-- Towers ----------------------------------------------------------------------------------

-- Each line of towers has levels; level 1 is what building it costs, each level after it what
-- the upgrade costs. A level's damage and cooldown (ticks) give its damage per second.
--
-- targets: 'ground', 'air' or 'both'. effect: what else a hit does (towers.lua). aura: what a
-- beacon adds to the towers around it. trap: goes on the path and hits what walks over it.
local function line(spec)
    local levels = {}
    for level = 1, spec.levels do
        local grow = level - 1
        levels[level] = {
            cost = math.floor(spec.cost * spec.cost_growth ^ grow + 0.5),
            damage = spec.damage and spec.damage * spec.damage_growth ^ grow,
            cooldown = spec.cooldown,
            range = spec.range + (spec.range_growth or 0) * grow,
            slow = spec.slow and math.min(0.8, spec.slow + 0.08 * grow),
            aura = spec.aura and spec.aura * level
        }
    end
    spec.levels = levels
    return spec
end

Public.lines = {
    gun = line {
        entity = 'gun-turret',
        targets = 'both',
        levels = 10,
        cost = 50,
        cost_growth = 1.6,
        damage = 12,
        damage_growth = 1.75,
        cooldown = 30,
        range = 9,
        range_growth = 0.3
    },
    laser = line {
        entity = 'laser-turret',
        targets = 'both',
        levels = 8,
        cost = 150,
        cost_growth = 1.7,
        damage = 60,
        damage_growth = 1.85,
        cooldown = 45,
        range = 12,
        range_growth = 0.4
    },
    flamer = line {
        entity = 'flamethrower-turret',
        targets = 'ground',
        effect = 'burn',
        levels = 8,
        cost = 120,
        cost_growth = 1.7,
        damage = 18,
        damage_growth = 1.8,
        cooldown = 30,
        range = 8,
        range_growth = 0.3
    },
    flak = line {
        entity = 'artillery-turret',
        targets = 'air',
        effect = 'splash',
        levels = 8,
        cost = 80,
        cost_growth = 1.6,
        damage = 40,
        damage_growth = 1.8,
        cooldown = 30,
        range = 13,
        range_growth = 0.4
    },
    cryo = line {
        entity = 'radar',
        targets = 'both',
        effect = 'slow',
        levels = 5,
        cost = 100,
        cost_growth = 2,
        damage = 4,
        damage_growth = 1.8,
        cooldown = 60,
        range = 7,
        range_growth = 0.8,
        slow = 0.3
    },
    beacon = line {
        entity = 'beacon',
        targets = 'none',
        levels = 5,
        cost = 200,
        cost_growth = 2,
        range = 6,
        range_growth = 0.5,
        aura = 0.15
    },
    trap = line {
        entity = 'land-mine',
        targets = 'ground',
        trap = true,
        levels = 8,
        cost = 40,
        cost_growth = 1.6,
        damage = 30,
        damage_growth = 1.8,
        cooldown = 30,
        range = 2
    }
}

-- the order the shop shows them in
Public.line_order = { 'gun', 'laser', 'flamer', 'flak', 'cryo', 'beacon', 'trap' }

-- effect numbers
Public.burn_ticks = 180
Public.burn_share = 0.6
Public.splash_radius = 2.5
Public.splash_share = 0.6
Public.slow_ticks = 90

return Public
