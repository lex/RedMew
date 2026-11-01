local Config = require 'config'
local DOC = require 'map_gen.maps.danger_ores.configuration'
local Scenario = require 'map_gen.maps.danger_ores.scenario'
local ScenarioInfo = require 'features.gui.info'
local Switchback = require 'map_gen.maps.danger_ores.modules.switchback'

local LIMIT = 3

ScenarioInfo.set_map_name('Danger Ores - Switchback')
ScenarioInfo.add_map_extra_info(([[
  This map is split in three sectors [item=iron-ore] [item=copper-ore] [item=coal].
  No belt runs straight for more than %d [item=transport-belt]: every turn starts the count again.
  Drag a belt and it bends round by itself, taking two more belts from your inventory for each bend.
  [item=underground-belt] and [item=splitter] don't count, and a run ends at them.
  Blueprints can't be used, so every line is laid by hand.
]]):format(LIMIT))

DOC.scenario_name = 'danger-ore-switchback'
Switchback.register({ limit = LIMIT })

-- no making, importing, copying or pasting blueprints
local action = defines.input_action
Config.permissions.presets.no_blueprints = true
Config.permissions.modes.no_blueprints = {}
for _, name in pairs({
  'activate_paste',
  'alt_select_blueprint_entities',
  'alternative_copy',
  'copy',
  'grab_blueprint_record',
  'import_blueprint',
  'import_blueprint_string',
  'import_blueprints_filtered',
  'import_permissions_string',
  'open_blueprint_library_gui',
  'open_blueprint_record',
  'select_blueprint_entities',
  'setup_blueprint',
  'setup_single_blueprint_record',
  'upgrade_opened_blueprint_by_record',
}) do
  Config.permissions.modes.no_blueprints[action[name]] = false
end

return Scenario.register(DOC)
