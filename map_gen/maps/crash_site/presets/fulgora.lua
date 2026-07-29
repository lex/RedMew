--[[
    Crash Site on Fulgora.

    The surface is associated with the Fulgora planet, so the map inherits the 3 minute
    day/night cycle, the 20% solar output and - the point of the map - the lightning storms.
    Terrain is not Fulgora's own generator: the outpost grid needs a continuous plane, and
    Fulgora's islands-in-an-oil-ocean would drop most of the grid into the sea. Instead the
    ground is painted from the Fulgoran tile palette, so it reads as Fulgora but plays flat.

    Fulgora has no pollutant_type, which would have silently switched off crash site's entire
    cost model, so ordinary pollution is restored via the surface override. The enemy roster is
    left as Nauvis biters: Fulgora ships no hostile prototypes at all, and a scenario cannot add
    any, so the wreck brought its own company.
]]
require 'map_gen.maps.crash_site.features.fulgora_lightning'

local ScenarioInfo = require 'features.gui.info'
local MGSP = require 'resources.map_gen_settings'
local RS = require 'map_gen.shared.redmew_surface'
local Terrain = require 'map_gen.maps.crash_site.terrain'

RS.set_planet('fulgora')
RS.set_pollution_override('pollution')

local config = {
    scenario_name = 'crashsite-fulgora',
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
            'fulgoran-dust',
            'fulgoran-sand',
            'fulgoran-dunes',
            'fulgoran-rock',
            'fulgoran-paving',
            'fulgoran-conduit',
            'fulgoran-machinery',
            'fulgoran-walls'
        },
        scale = 1 / 96,
        seed = 7331,
        -- Flattening the planet removed its oil ocean, and with it Fulgora's signature fluid
        -- source: oil-ocean tiles carry heavy-oil, so an offshore pump on one is an unlimited
        -- heavy oil supply. These are pools rather than an ocean - enough to pump from without
        -- cutting the outpost grid into islands. Spawn keeps ordinary water for steam power.
        wet = {
            tiles = {
                'oil-ocean-shallow',
                'oil-ocean-deep'
            },
            threshold = -0.5,
            scale = 1 / 112,
            seed = 1357
        }
    }
}

local Scenario = require 'map_gen.maps.crash_site.scenario'
ScenarioInfo.set_map_name('Crashsite Fulgora')
ScenarioInfo.set_map_description('Capture outposts on Fulgora. Everything you take from them draws the lightning down onto what you have built.')
ScenarioInfo.add_map_extra_info(
    [[
    - Fulgora's storms are real: the map runs on the Fulgora planet, with its 3 minute day/night cycle and 20% solar output.
    - Every batch of product you take out of an outpost builds charge, and that charge calls lightning down on your own buildings.
    - Lightning rods and collectors soak strikes far better than anything else you own. Build them early.
    - Solar panels are near useless here. Plan your power around that.
    - The oil pools are Fulgoran oil ocean: an offshore pump on one is an unlimited heavy oil supply.
    - Cars have repair beams.
    - Outposts have enemy turrets defending them.
    - Outposts have loot and provide a steady stream of resources.
    - Outpost markets to purchase items and outpost upgrades.
    - Capturing outposts increases evolution.
    - Reduced damage by all player weapons, turrets, and ammo.
    - Biters have more health and deal more damage.
    - Biters and spitters spawn on death of entities.
    ]]
)

return Scenario.init(config)
