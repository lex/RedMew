--[[
    Crash Site on Gleba.

    Structurally the closest port of the Nauvis map, because Gleba's planet prototype sets
    pollutant_type = "spores". Taking product out of an outpost therefore still emits Gleba's own
    pollutant, and the pentapods still come for it - the entire risk/reward loop survives without
    touching outpost_builder at all. What has to change is every hard-coded enemy name, which is
    what enemy_roster.lua exists for.

    Egg rafts only place on shallow water (their collision mask includes ground_tile), so the
    terrain painter lays down wetland patches and the map generator's own can_place_entity check
    filters the scattered nests into them. Nests end up in marshes, which is where they belong.

    Spoilage turns out not to matter here: crash site's loot and market stock is plates, ores,
    ammo, coins and the six non-spoiling science packs. Nothing in the roster rots.
]]
local ScenarioInfo = require 'features.gui.info'
local MGSP = require 'resources.map_gen_settings'
local RS = require 'map_gen.shared.redmew_surface'
local Terrain = require 'map_gen.maps.crash_site.terrain'
local Roster = require 'map_gen.maps.crash_site.enemy_roster'

RS.set_planet('gleba')

Roster.set {
    -- Nests need shallow water; positions rolled on dry ground are skipped by the generator.
    spawners = {
        'gleba-spawner-small',
        'gleba-spawner'
    },
    -- Gleba has no worm turrets. Strafers are the ranged analogue, with a wriggler on the
    -- bottom rung so the ring just outside the safe radius is not immediately lethal.
    worms = {
        'small-wriggler-pentapod',
        'small-strafer-pentapod',
        'medium-strafer-pentapod',
        'big-strafer-pentapod'
    },
    -- Nest rolls that land on dry ground are discarded, so roll far more of them to end up with
    -- a comparable number of nests once the marshes have filtered them.
    spawner_chance_multiplier = 5,
    -- The "worms" here are mobile units rather than static turrets. At the Nauvis worm density
    -- that would be tens of thousands of pathfinding pentapods, so scatter far fewer.
    worm_chance_multiplier = 0.12,
    unit_levels = {
        wriggler = {'small-wriggler-pentapod', 'medium-wriggler-pentapod', 'big-wriggler-pentapod'},
        strafer = {'small-strafer-pentapod', 'medium-strafer-pentapod', 'big-strafer-pentapod'},
        stomper = {'small-stomper-pentapod', 'medium-stomper-pentapod', 'big-stomper-pentapod'}
    },
    entity_drop_amount = {
        ['gleba-spawner-small'] = {low = 8, high = 24},
        ['gleba-spawner'] = {low = 12, high = 30},
        ['small-wriggler-pentapod'] = {low = 3, high = 10},
        ['small-strafer-pentapod'] = {low = 8, high = 24},
        ['medium-strafer-pentapod'] = {low = 15, high = 30},
        ['big-strafer-pentapod'] = {low = 25, high = 45},
        ['big-stomper-pentapod'] = {low = 30, high = 60}
    },
    enemy_spawn_map = {
        ['medium-wriggler-pentapod'] = {name = 'small-strafer-pentapod', count = 1, chance = 0.2},
        ['big-wriggler-pentapod'] = {name = 'medium-strafer-pentapod', count = 1, chance = 0.2},
        ['medium-strafer-pentapod'] = {name = 'small-strafer-pentapod', count = 1, chance = 0.2},
        ['medium-stomper-pentapod'] = {name = 'medium-strafer-pentapod', count = 1, chance = 0.2},
        ['gleba-spawner-small'] = {type = 'wriggler', count = 3, chance = 1},
        ['gleba-spawner'] = {type = 'wriggler', count = 5, chance = 1},
        ['big-strafer-pentapod'] = {
            type = 'compound',
            spawns = {
                {name = 'big-wriggler-pentapod', count = 2},
                {name = 'medium-strafer-pentapod', count = 2}
            },
            chance = 1
        },
        ['big-stomper-pentapod'] = {
            type = 'compound',
            spawns = {
                {name = 'big-strafer-pentapod', count = 2},
                {name = 'big-wriggler-pentapod', count = 2}
            },
            chance = 1
        }
    },
    allowed_cause_source = {
        ['small-wriggler-pentapod'] = true,
        ['medium-wriggler-pentapod'] = true,
        ['big-wriggler-pentapod'] = true,
        ['small-wriggler-pentapod-premature'] = true,
        ['medium-wriggler-pentapod-premature'] = true,
        ['big-wriggler-pentapod-premature'] = true,
        ['small-strafer-pentapod'] = true,
        ['medium-strafer-pentapod'] = true,
        ['big-strafer-pentapod'] = true,
        ['small-stomper-pentapod'] = true,
        ['medium-stomper-pentapod'] = true,
        ['big-stomper-pentapod'] = true
    },
    static_entities_to_check = {
        'gleba-spawner',
        'gleba-spawner-small',
        'gun-turret',
        'laser-turret',
        'artillery-turret',
        'flamethrower-turret'
    },
    mobile_entities_to_check = {
        'small-wriggler-pentapod',
        'medium-wriggler-pentapod',
        'big-wriggler-pentapod',
        'small-wriggler-pentapod-premature',
        'medium-wriggler-pentapod-premature',
        'big-wriggler-pentapod-premature',
        'small-strafer-pentapod',
        'medium-strafer-pentapod',
        'big-strafer-pentapod',
        'small-stomper-pentapod',
        'medium-stomper-pentapod',
        'big-stomper-pentapod'
    }
}

local config = {
    scenario_name = 'crashsite-gleba',
    map_gen_settings = {
        MGSP.water_none,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.tree_none,
        MGSP.cliff_none
    },
    terrain = Terrain.painter {
        ground = {
            'lowland-brown-blubber',
            'lowland-olive-blubber',
            'lowland-cream-red',
            'midland-turquoise-bark',
            'midland-yellow-crust',
            'midland-cracked-lichen',
            'highland-yellow-rock',
            'highland-dark-rock'
        },
        scale = 1 / 96,
        seed = 4242,
        -- Marshes. Pentapod nests can only sit in these, so their size and frequency is
        -- effectively the nest density control for the whole map.
        wet = {
            tiles = {
                'wetland-green-slime',
                'wetland-light-green-slime',
                'wetland-blue-slime',
                'wetland-dead-skin'
            },
            threshold = -0.3,
            scale = 1 / 128,
            seed = 8484
        }
    }
}

local Scenario = require 'map_gen.maps.crash_site.scenario'
ScenarioInfo.set_map_name('Crashsite Gleba')
ScenarioInfo.set_map_description('Capture outposts on Gleba. Everything you take from them gives off spores, and the pentapods follow the spores back to you.')
ScenarioInfo.add_map_extra_info(
    [[
    - The map runs on the Gleba planet, so outpost production emits spores rather than pollution.
    - Pentapods replace biters. Wrigglers rush, strafers circle and shell you from range, stompers soak an enormous amount of damage.
    - Stompers resist 80% impact and 80% laser. Bring something else.
    - Pentapod nests are egg rafts and only sit in the marshes. Clear the marshes to clear the map.
    - Cars have repair beams.
    - Outposts have enemy turrets defending them.
    - Outposts have loot and provide a steady stream of resources.
    - Outpost markets to purchase items and outpost upgrades.
    - Capturing outposts increases evolution.
    - Reduced damage by all player weapons, turrets, and ammo.
    - Pentapods spawn on death of entities.
    ]]
)

return Scenario.init(config)
