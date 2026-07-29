--[[
    The crash site scenario is built around four enemy roles, and until now every one of them
    was a hard-coded Nauvis prototype name spread across events.lua, commands.lua and scenario.lua:

    1. spawners  - static nests scattered across the whole map by the map-gen enemy function.
    2. worms     - static/ranged defenders, scattered in tiers that get nastier further from spawn.
    3. units     - mobile enemies, picked by tier from the current evolution factor.
    4. the win condition - "clear the map" counts every one of the above by name.

    Any map that wants to run crash site on a different planet needs to swap all four together,
    so they live here in one mutable table. Presets call Public.set{...} before (or after, order
    does not matter) requiring the scenario; the consumers read through this module at call time
    rather than copying the tables into locals, so the roster is always the one the preset chose.

    Anything that is not planet specific stays where it was. Outpost turrets (gun/laser/
    flamethrower/artillery) are player-tech entities handed to the enemy force, so they are
    identical on every planet, as are the 'cause' entries that punish the player for building
    their own machines.
]]
local Public = {}

--- Build a name -> true lookup from an array of prototype names.
local function to_set(array)
    local set = {}
    for i = 1, #array do
        set[array[i]] = true
    end
    return set
end

--- Static nests scattered over the map. Entities that cannot be placed at a rolled position are
-- silently skipped by the map generator, so a roster may rely on terrain to filter placement.
Public.spawners = {
    'biter-spawner',
    'spitter-spawner'
}

--- Static defenders, ordered weakest to strongest. Any length is supported; the map-gen tiering
-- and the death-spawn tables scale to #worms.
Public.worms = {
    'small-worm-turret',
    'medium-worm-turret',
    'big-worm-turret',
    'behemoth-worm-turret'
}

--- Mobile units by tier, keyed by the 'type' used in enemy_spawn_map entries.
Public.unit_levels = {
    biter = {'small-biter', 'medium-biter', 'big-biter', 'behemoth-biter'},
    spitter = {'small-spitter', 'medium-spitter', 'big-spitter', 'behemoth-spitter'}
}

--- Coin payout range per enemy killed.
Public.entity_drop_amount = {
    ['biter-spawner'] = {low = 8, high = 24},
    ['spitter-spawner'] = {low = 8, high = 24},
    ['small-worm-turret'] = {low = 3, high = 10},
    ['medium-worm-turret'] = {low = 8, high = 24},
    ['big-worm-turret'] = {low = 15, high = 30},
    ['behemoth-worm-turret'] = {low = 25, high = 45}
}

--- What an enemy leaves behind when it dies. Entries for player machines are not roster specific
-- and stay in events.lua.
Public.enemy_spawn_map = {
    ['medium-biter'] = {name = 'small-worm-turret', count = 1, chance = 0.2},
    ['big-biter'] = {name = 'medium-worm-turret', count = 1, chance = 0.2},
    ['behemoth-biter'] = {name = 'big-worm-turret', count = 1, chance = 0.2},
    ['medium-spitter'] = {name = 'small-worm-turret', count = 1, chance = 0.2},
    ['big-spitter'] = {name = 'medium-worm-turret', count = 1, chance = 0.2},
    ['behemoth-spitter'] = {name = 'big-worm-turret', count = 1, chance = 0.2},
    ['biter-spawner'] = {type = 'biter', count = 5, chance = 1},
    ['spitter-spawner'] = {type = 'spitter', count = 5, chance = 1},
    ['behemoth-worm-turret'] = {
        type = 'compound',
        spawns = {
            {name = 'behemoth-spitter', count = 2},
            {name = 'behemoth-biter', count = 2}
        },
        chance = 1
    }
}

--- Enemies that are allowed to trigger a 'cause' spawn when they destroy a player machine.
Public.allowed_cause_source = {
    ['small-biter'] = true,
    ['medium-biter'] = true,
    ['big-biter'] = true,
    ['behemoth-biter'] = true,
    ['small-spitter'] = true,
    ['medium-spitter'] = true,
    ['big-spitter'] = true,
    ['behemoth-spitter'] = true
}

--- Structures that must all be dead before the map counts as cleared. Outpost turrets are
-- included because they sit on the enemy force until the outpost is captured.
Public.static_entities_to_check = {
    'spitter-spawner',
    'biter-spawner',
    'small-worm-turret',
    'medium-worm-turret',
    'big-worm-turret',
    'behemoth-worm-turret',
    'gun-turret',
    'laser-turret',
    'artillery-turret',
    'flamethrower-turret'
}

--- Mobile enemies counted towards the "few stragglers left" allowance of the restart check.
Public.mobile_entities_to_check = {
    'small-spitter',
    'medium-spitter',
    'big-spitter',
    'behemoth-spitter',
    'small-biter',
    'medium-biter',
    'big-biter',
    'behemoth-biter'
}

--- Multipliers on the map-gen scatter density, relative to the Nauvis tuning.
-- Needed when a roster's entities are not like-for-like replacements: a roster whose "worms" are
-- mobile units rather than static turrets wants far fewer of them, and a roster whose nests can
-- only stand on particular terrain wants more rolls to land the same number of nests.
Public.spawner_chance_multiplier = 1
Public.worm_chance_multiplier = 1

--- Set lookup built from Public.worms; entities in here are placed with a collision search
-- instead of being dropped straight onto the corpse position.
Public.worm_set = to_set(Public.worms)

--- Replace part or all of the roster. Fields not present in the argument are left untouched.
-- @param roster <table> any subset of the fields defined above
function Public.set(roster)
    for k, v in pairs(roster) do
        Public[k] = v
    end

    -- worm_set is derived, so recompute it unless the caller supplied one explicitly.
    if roster.worms and not roster.worm_set then
        Public.worm_set = to_set(roster.worms)
    end
end

return Public
