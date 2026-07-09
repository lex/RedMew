local MGSP = require 'resources.map_gen_settings'
local Event = require 'utils.event'
local RestrictEntities = require 'map_gen.shared.entity_placement_restriction'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-steam-all-the-way',
    map_gen_settings = {
        MGSP.grass_only,
        MGSP.enable_water,
        MGSP.water_very_low,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    disabled_outpost_types = { 'mini_t2_energy_factory', 'medium_power_factory', 'big_power_factory' },
    disabled_technologies = { 'nuclear-power', 'nuclear-fuel-reprocessing' }
}

Info.set_info('Crashsite - Steam all the way', {
    extra = {
        '- Nuclear power is completely disabled.',
        '- Accumulators and Solar Panels cannot be placed but are still available for other recipes.'
    }
})

-- uranium-fuel-cell is unlocked by uranium-processing; disable it after that research
-- (an init disable would be undone when the research completes).
Event.add(defines.events.on_research_finished,
    function(event)
        if event.research.name ~= 'uranium-processing' then
            return
        end
        game.forces.player.recipes['uranium-fuel-cell'].enabled = false
    end
)

RestrictEntities.add_banned({ 'solar-panel', 'accumulator' })
Event.add(RestrictEntities.events.on_restricted_entity_destroyed,
    function(event)
        local p = event.player
        if p and p.valid then
            p.print('This preset does not allow placing [item=accumulator] or [item=solar-panel].')
        end
    end
)

return Scenario.init(config)
