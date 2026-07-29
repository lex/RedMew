--[[
    Fulgora's replacement for "your factory is what makes the biters angry".

    Crash site's economy has one price: outposts hand you product for free, and taking that
    product pollutes. Fulgora's planet prototype sets no pollutant_type, so the map preset
    restores ordinary pollution via RS.set_pollution_override so the biters still behave. This
    module then adds the planet's own pressure on top.

    Every batch an outpost hands over adds charge. When the charge crosses the threshold a bolt
    is called down on something the players built. Lightning rods and collectors soak strikes
    (the planet's own priority rules put them far above any other target), so the mitigation
    ladder is "buy rods from the outpost markets", exactly the way ammo works on Nauvis.

    Ambient storms are not scripted here. The surface is associated with the planet, so Fulgora's
    own lightning_properties drive the background strike rate for free.
]]
local Global = require 'utils.global'
local Token = require 'utils.token'
local Task = require 'utils.task'
local RS = require 'map_gen.shared.redmew_surface'
local OutpostBuilder = require 'map_gen.maps.crash_site.outpost_builder'

local random = math.random

-- Charge added per item handed over by an outpost.
local charge_per_item = 1
-- Charge needed for one bolt. Roughly one strike per 1500 items of outpost throughput.
local charge_per_strike = 1500
-- Never fire more than one scripted bolt per this many ticks, whatever the throughput.
local strike_cooldown = 60
-- How far from the map origin player structures are looked for.
local search_radius = 512
-- Cap on how much charge can bank up, so an idle period cannot unleash a barrage.
local max_charge = charge_per_strike * 5

local data = {
    charge = 0,
    last_strike_tick = 0
}

Global.register(
    data,
    function(tbl)
        data = tbl
    end
)

--- Structures worth striking. Power infrastructure first: it is what a player builds most of,
-- and losing it is the lesson the mechanic is teaching.
local target_types = {
    'electric-pole',
    'assembling-machine',
    'furnace',
    'solar-panel',
    'accumulator',
    'lab',
    'mining-drill',
    'boiler',
    'generator'
}

local function find_target(surface)
    local entities =
        surface.find_entities_filtered {
        type = target_types,
        force = 'player',
        area = {{-search_radius, -search_radius}, {search_radius, search_radius}},
        limit = 200
    }

    local count = #entities
    if count == 0 then
        return nil
    end

    return entities[random(count)]
end

local strike =
    Token.register(
    function()
        -- execute_lightning needs the prototype to exist. Without Space Age it does not, and the
        -- map should stay playable rather than erroring on every outpost tick.
        if not prototypes.entity['lightning'] then
            return
        end

        local surface = RS.get_surface()
        if not surface or not surface.valid then
            return
        end

        local target = find_target(surface)
        if not target or not target.valid then
            return
        end

        surface.execute_lightning {name = 'lightning', position = target.position}
    end
)

--- Called by the outpost builder every time a magic crafter hands over a batch.
local production_pressure =
    Token.register(
    function(_, count)
        local charge = data.charge + (count * charge_per_item)

        if charge < charge_per_strike then
            data.charge = charge
            return
        end

        local tick = game.tick
        if tick - data.last_strike_tick < strike_cooldown then
            -- Bank it, but do not let it grow without bound.
            data.charge = charge < max_charge and charge or max_charge
            return
        end

        data.charge = charge - charge_per_strike
        data.last_strike_tick = tick

        -- Deferred so the strike does not land inside the crafter update loop.
        Task.set_timeout_in_ticks(1, strike, {})
    end
)

OutpostBuilder.set_production_pressure_handler(production_pressure)

return {}
