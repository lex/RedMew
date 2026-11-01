local DOC = require 'map_gen.maps.danger_ores.configuration'
local Scenario = require 'map_gen.maps.danger_ores.scenario'
local ScenarioInfo = require 'features.gui.info'

ScenarioInfo.set_map_name('Danger Ores - Switchback')
ScenarioInfo.add_map_extra_info([[
  This map is split in three sectors [item=iron-ore] [item=copper-ore] [item=coal].
  Belts can't run straight for long: see the rules below.
]])

DOC.scenario_name = 'danger-ore-switchback'
DOC.switchback.enabled = true

return Scenario.register(DOC)
