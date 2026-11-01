-- Switchback: no belt runs straight for more than `limit` transport belts; every turn starts the
-- count again. Underground belts and splitters don't count, and a run ends at them.
--
-- A belt that would make a run too long is turned aside instead, when a player builds it from
-- their hand (or as a ghost): it turns to one side, two more belts take the line round and back,
-- and the next belt carries on in line, so dragging a belt still lays a line. The two belts come
-- from the player's inventory. When there's no room or no belts, or a robot or a blueprint built
-- it, the belt is removed and handed back.
--
-- Rotating a belt into a run that's too long is undone. Removing a belt that curved another one
-- can straighten it into a run that's too long: the straightened belt is then taken up too.
--
-- Ghosts count as the belts they will be, so a planned bend holds while robots build it.
--
-- With `no_blueprints`, blueprints can't be made, imported, copied or pasted, so a solved layout
-- can't be stamped down again: RedMew's no_blueprints permissions, widened to all of these. The
-- permissions only apply in multiplayer, and a blueprint may still reach a player's hand some
-- other way, so whatever is built from a blueprint in the hand is removed too.
--
-- Turned on for any Danger Ores map with DOC.switchback.enabled (see configuration.lua).
local Config = require 'config'
local Event = require 'utils.event'
local Global = require 'utils.global'
local RobotRefund = require 'map_gen.shared.robot_refund'
local Rules = require 'map_gen.maps.danger_ores.modules.switchback_rules'
local Task = require 'utils.task'
local Token = require 'utils.token'

local floor = math.floor

local BELT_TYPES = {'transport-belt', 'underground-belt', 'splitter'}
local is_belt_type = {}
for _, type in pairs(BELT_TYPES) do
    is_belt_type[type] = true
end

-- set by the preset as the scenario loads, the same on every load
local settings = {limit = 3}
local registered = false

-- player index -> the bend the player's last belt made, kept until their next belt
local bends = {}
-- player index -> the tick a blueprint of theirs was last removed, to say so once a blueprint
local blueprint_removed = {}

Global.register({bends = bends, blueprint_removed = blueprint_removed}, function(tbl)
    bends = tbl.bends
    blueprint_removed = tbl.blueprint_removed
end)

local Public = {}

local function entity_type(entity)
    if entity.name == 'entity-ghost' then
        return entity.ghost_type, true
    end
    return entity.type, false
end

local function entity_name(entity)
    return entity.name == 'entity-ghost' and entity.ghost_name or entity.name
end

local function key(x, y)
    -- adding 0 turns -0 into 0, which has the same key
    return (x + 0) .. ',' .. (y + 0)
end

local function tiles_of(entity, type)
    local p = entity.position
    if type == 'splitter' then
        local px, py = Rules.vector(Rules.turn(entity.direction, 1))
        return {
            {floor(p.x - px * 0.5), floor(p.y - py * 0.5)},
            {floor(p.x + px * 0.5), floor(p.y + py * 0.5)}
        }
    end
    return {{floor(p.x), floor(p.y)}}
end

local function underground_output(entity)
    -- a ghost may not tell which end it is; taken as an entrance, it feeds nothing
    local ok, belt_to_ground_type = pcall(function()
        return entity.belt_to_ground_type
    end)
    return ok and belt_to_ground_type == 'output'
end

--- The piece `entity` makes in the rules' world, facing `direction` (its own by default).
local function piece_of(entity, type, direction)
    direction = direction or entity.direction
    local dx, dy = Rules.vector(direction)
    local outputs = {}
    if type ~= 'underground-belt' or underground_output(entity) then
        for _, t in pairs(tiles_of(entity, type)) do
            outputs[#outputs + 1] = {t[1] + dx, t[2] + dy}
        end
    end
    return {belt = type == 'transport-belt', direction = direction, outputs = outputs}
end

local function find_belt(surface, x, y, types)
    local area = {{x + 0.1, y + 0.1}, {x + 0.9, y + 0.9}}
    return surface.find_entities_filtered({area = area, type = types, limit = 1})[1]
        or surface.find_entities_filtered({area = area, ghost_type = types, limit = 1})[1]
end

--- The rules' world for `surface`, with `overrides` (tile key -> piece, or false for none) laid
-- over what is built there.
function Public.world(surface, overrides)
    local cache = {}
    return function(x, y)
        local k = key(x, y)
        local piece = overrides and overrides[k]
        if piece == nil then
            piece = cache[k]
            if piece == nil then
                local entity = find_belt(surface, x, y, BELT_TYPES)
                piece = entity and piece_of(entity, (entity_type(entity))) or false
                cache[k] = piece
            end
        end
        return piece or nil
    end
end

--- The tiles whose runs a change to `entity` can lengthen: its own and those it feeds.
local function affected(entity, type)
    local tiles = tiles_of(entity, type)
    for _, o in pairs(piece_of(entity, type).outputs) do
        tiles[#tiles + 1] = o
    end
    return tiles
end

local function placement_stack(entity)
    local items = entity.prototype.items_to_place_this
    local item = items and items[1]
    if not item then
        return nil
    end
    return {name = item.name, count = item.count or 1, quality = entity.quality.name}
end

local function tell(player, position)
    if not (player and player.valid) then
        return
    end
    player.create_local_flying_text({text = {'danger_ores.switchback_too_straight', settings.limit}, position = position})
    player.play_sound({path = 'utility/cannot_build'})
end

local function give(player, stack, surface, position, force)
    local given = 0
    if player and player.valid then
        given = player.insert(stack)
    end
    if given < stack.count then
        surface.spill_item_stack({
            position = position,
            stack = {name = stack.name, count = stack.count - given, quality = stack.quality},
            enable_looted = true,
            force = force
        })
    end
end

--- Removes `entity` and hands its item back to the robot or player that built it.
local function refuse(entity, ghost, event, player)
    local stack = not ghost and placement_stack(entity)
    local surface, position, force = entity.surface, entity.position, entity.force
    entity.destroy({raise_destroy = true})
    tell(player, position)
    if not stack then
        return
    end
    local robot = event.robot
    if robot and robot.valid then
        RobotRefund.refund(robot, stack, surface, position, force)
    else
        give(player, stack, surface, position, force)
    end
end

--- Takes `count` belts from the player's hand, or else their inventory.
-- @return false, taking nothing, when they don't have them
local function take_belts(player, name, quality, count)
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == name and cursor.quality.name == quality and cursor.count >= count then
        if cursor.count == count then
            cursor.clear()
        else
            cursor.count = cursor.count - count
        end
        return true
    end
    local item = {name = name, count = count, quality = quality}
    if player.get_item_count(item) >= count then
        player.remove_item(item)
        return true
    end
    return false
end

local function can_place_spec(ghost, name, b, force)
    -- a ghost is checked by the name of what it will be, with the ghost check: asked about an
    -- 'entity-ghost', the game says no everywhere
    local check = ghost and defines.build_check_type.manual_ghost or defines.build_check_type.manual
    return {name = name, position = {b[1] + 0.5, b[2] + 0.5}, direction = b[3], force = force, build_check_type = check}
end

--- Turns a belt that made its run too long aside, with two more belts taking the line round to
-- the tile after it, on whichever side has room and keeps every run short enough.
-- @return true when it bent
local function try_bend(entity, ghost, player)
    local surface, force = entity.surface, entity.force
    local x, y = floor(entity.position.x), floor(entity.position.y)
    local direction = entity.direction
    local limit = settings.limit
    local world = Public.world(surface)
    if Rules.run_length(world, x, y, limit) <= limit then
        -- the run that's too long isn't this belt's, so turning it wouldn't help
        return false
    end

    local name, quality = entity_name(entity), entity.quality.name
    local dx, dy = Rules.vector(direction)
    for _, side in pairs({-1, 1}) do
        local bend = Rules.bend(x, y, direction, side)
        local overrides = {[key(x, y)] = Rules.belt(x, y, bend.turn)}
        local check = {{x, y}, {x + dx, y + dy}, {x - dx, y - dy}}
        local free = true
        for _, b in pairs(bend.belts) do
            overrides[key(b[1], b[2])] = Rules.belt(b[1], b[2], b[3])
            check[#check + 1] = {b[1], b[2]}
            free = free and not world(b[1], b[2]) and surface.can_place_entity(can_place_spec(ghost, name, b, force))
        end

        local bent = Public.world(surface, overrides)
        if free and not Rules.too_long(bent, check, limit) and (ghost or take_belts(player, name, quality, #bend.belts)) then
            entity.direction = bend.turn
            for _, b in pairs(bend.belts) do
                surface.create_entity({
                    name = ghost and 'entity-ghost' or name,
                    inner_name = ghost and name or nil,
                    position = {b[1] + 0.5, b[2] + 0.5},
                    direction = b[3],
                    force = force,
                    quality = quality,
                    player = player,
                    raise_built = true
                })
            end
            bends[player.index] = {entity = entity, turn = bend.turn, after = {x + dx, y + dy}}
            return true
        end
    end
    return false
end

--- Dragging a belt on from a bend may turn the bent belt back in line, to feed the next one;
-- this turns it aside again.
local function keep_bend(player, entity)
    local bend = bends[player.index]
    if not bend then
        return
    end
    bends[player.index] = nil
    local bent = bend.entity
    if not bent.valid or bent.direction == bend.turn then
        return
    end
    local p = entity.position
    if floor(p.x) == bend.after[1] and floor(p.y) == bend.after[2] then
        bent.direction = bend.turn
    end
end

local function on_built(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    local type, ghost = entity_type(entity)
    if not is_belt_type[type] then
        return
    end

    local player = event.player_index and game.get_player(event.player_index)
    local by_hand = player and not event.robot and not player.is_cursor_blueprint()
    if by_hand then
        keep_bend(player, entity)
    end

    if not Rules.too_long(Public.world(entity.surface), affected(entity, type), settings.limit) then
        return
    end
    if by_hand and type == 'transport-belt' and try_bend(entity, ghost, player) then
        return
    end
    refuse(entity, ghost, event, player)
end

local function on_rotated(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    local type = entity_type(entity)
    if not is_belt_type[type] then
        return
    end

    local tiles = affected(entity, type)
    for _, o in pairs(piece_of(entity, type, event.previous_direction).outputs) do
        tiles[#tiles + 1] = o
    end
    if Rules.too_long(Public.world(entity.surface), tiles, settings.limit) then
        entity.rotate({reverse = true})
        tell(event.player_index and game.get_player(event.player_index), entity.position)
    end
end

--- A tick after a belt went, takes up any belt it left on a run that's too long. A tick later,
-- so that a belt replaced by an upgrade is back first.
local check_removed = Token.register(function(params)
    local surface = params.surface
    if not surface.valid then
        return
    end
    local player = params.player_index and game.get_player(params.player_index)
    local limit = settings.limit
    for _, t in pairs(params.tiles) do
        if Rules.run_length(Public.world(surface), t[1], t[2], limit) > limit then
            local belt = find_belt(surface, t[1], t[2], 'transport-belt')
            local ghost = belt.name == 'entity-ghost'
            local stack = not ghost and placement_stack(belt)
            local position, force = belt.position, belt.force
            belt.destroy({raise_destroy = true})
            tell(player, position)
            if stack then
                give(player, stack, surface, position, force)
            end
        end
    end
end)

local function on_removed(entity, player_index)
    if not (entity and entity.valid) then
        return
    end
    local type = entity_type(entity)
    if not is_belt_type[type] then
        return
    end
    local outputs = piece_of(entity, type).outputs
    if #outputs > 0 then
        Task.set_timeout_in_ticks(1, check_removed, {surface = entity.surface, tiles = outputs, player_index = player_index})
    end
end

local function on_mined(event)
    on_removed(event.entity, event.player_index)
end

local function on_ghost_removed(event)
    on_removed(event.ghost, event.player_index)
end

--- Removes what a player builds from a blueprint in their hand, a copy and paste included.
-- Blueprints build ghosts, so there is nothing to hand back.
local function on_built_from_blueprint(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    local player = game.get_player(event.player_index)
    if not (player and player.is_cursor_blueprint()) then
        return
    end
    local position = entity.position
    entity.destroy({raise_destroy = true})
    if blueprint_removed[player.index] ~= game.tick then
        blueprint_removed[player.index] = game.tick
        player.create_local_flying_text({text = {'danger_ores.switchback_no_blueprints'}, position = position})
        player.play_sound({path = 'utility/cannot_build'})
    end
end

--- @return how many belts a straight run may have
function Public.get_limit()
    return settings.limit
end

local BLUEPRINT_ACTIONS = {
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
    'upgrade_opened_blueprint_by_record'
}

--- @param config {limit = how many belts a straight run may have (3 by default), no_blueprints = true to ban blueprints}
function Public.register(config)
    settings.limit = config and config.limit or 3
    if config and config.no_blueprints then
        local actions = {}
        for _, name in pairs(BLUEPRINT_ACTIONS) do
            actions[defines.input_action[name]] = false
        end
        Config.permissions.presets.no_blueprints = true
        Config.permissions.modes.no_blueprints = actions
    end
    if registered then
        return
    end
    registered = true
    Event.add(defines.events.on_built_entity, on_built)
    Event.add(defines.events.on_robot_built_entity, on_built)
    Event.add(defines.events.on_player_rotated_entity, on_rotated)
    Event.add(defines.events.on_player_mined_entity, on_mined)
    Event.add(defines.events.on_robot_mined_entity, on_mined)
    Event.add(defines.events.on_pre_ghost_deconstructed, on_ghost_removed)
    if config and config.no_blueprints then
        -- added last, so it runs first: handlers run in reverse order
        Event.add(defines.events.on_built_entity, on_built_from_blueprint)
    end
end

return Public
