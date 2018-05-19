local Event = require 'utils.event'

local function on_init()
    global.corpse_util_corpses = {}
end

local function player_died(event)
    local player = game.players[event.player_index]

    if not player or not player.valid then
        return
    end

    local pos = player.position
    local entities =
        player.surface.find_entities_filtered {
        area = {{pos.x, pos.y}, {pos.x + 1, pos.y + 1}},
        name = 'character-corpse'
    }
    local entity
    for _, e in ipairs(entities) do
        if e.character_corpse_player_index == event.player_index then
            entity = e
            break
        end
    end

    if not entity or not entity.valid then
        return
    end

    local text = player.name .. "'s corpse"
    local position = entity.position
    local tag =
        player.force.add_chart_tag(
        player.surface,
        {icon = {type = 'item', name = 'power-armor-mk2'}, position = position, text = text}
    )

    if not tag then
        return
    end

    global.corpse_util_corpses[position.x .. ',' .. position.y] = tag
end

local function remove_tag(entity)
    if not entity or not entity.valid then
        return
    end

    local pos = entity.position
    local tag = global.corpse_util_corpses[pos.x .. ',' .. pos.y]
    global.corpse_util_corpses[entity] = nil

    if not tag or not tag.valid then
        return
    end

    tag.destroy()
end

local function corpse_expired(event)
    local entity = event.corpse

    remove_tag(entity)
end

local function mined_entity(event)
    local entity = event.entity

    remove_tag(entity)
end

Event.on_init(on_init)
Event.add(defines.events.on_player_died, player_died)
Event.add(defines.events.on_character_corpse_expired, corpse_expired)
Event.add(defines.events.on_pre_player_mined_item, mined_entity)