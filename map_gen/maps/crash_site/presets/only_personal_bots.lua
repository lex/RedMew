local MGSP = require 'resources.map_gen_settings'
local Event = require 'utils.event'
local Scenario = require 'map_gen.maps.crash_site.scenario'
local Info = require 'map_gen.maps.crash_site.presets._shared'

local config = {
    scenario_name = 'crashsite-only-personal-bots',
    map_gen_settings = {
        MGSP.grass_only,
        MGSP.enable_water,
        MGSP.water_very_low,
        MGSP.starting_area_very_low,
        MGSP.ore_oil_none,
        MGSP.enemy_none,
        MGSP.cliff_none
    },
    disabled_outpost_types = { 'mini_t1_robotics_factory' },
    disabled_technologies = { 'logistic-robotics', 'logistic-system' }
}

Info.set_info('Crashsite - Only Personal Construction Bots', {
    extra = {
        '- Only personal construction bots are available on this map.',
        '- Roboport, passive provider chest and storage chest do NOT unlock.'
    }
})

-- Recipes unlocked by construction-robotics must be disabled AFTER that research
-- completes, or the research re-enables them -- so this stays event-driven.
Event.add(defines.events.on_research_finished,
    function(event)
        if event.research.name ~= 'construction-robotics' then
            return
        end
        game.forces.player.recipes['roboport'].enabled = false
        game.forces.player.recipes['passive-provider-chest'].enabled = false
        game.forces.player.recipes['storage-chest'].enabled = false
    end
)

return Scenario.init(config)
