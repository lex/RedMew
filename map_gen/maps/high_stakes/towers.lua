-- Towers: each played hand becomes one. The turret entity is only what a tower looks like; the
-- script picks its targets and deals its damage, as the hand decides (settings.lua).

local Cards = require 'map_gen.maps.high_stakes.cards'
local Settings = require 'map_gen.maps.high_stakes.settings'
local State = require 'map_gen.maps.high_stakes.state'
local Waves = require 'map_gen.maps.high_stakes.waves'

local random = math.random
local sqrt = math.sqrt

local Public = {}

-- how often towers look for targets, in ticks
Public.interval = 6

local types = Cards.hand_types

--- What a hand's tower does.
---@param cards integer[] the hand's five cards
---@param hand table Cards.evaluate's result for them
---@return table spec { type, rank, suit, entity, damage, cooldown, range, effect, text }
function Public.spec(cards, hand)
    local stats = Settings.towers[hand.type]
    local spec = {
        type = hand.type,
        rank = hand.rank,
        suit = hand.suit,
        entity = stats.entity,
        damage = stats.damage(hand.rank),
        cooldown = stats.cooldown,
        range = stats.range,
        effect = stats.effect,
        text = Cards.hand_text(cards, hand)
    }
    if hand.type == types.high_card then
        local suit = Settings.suits[hand.suit]
        spec.damage = spec.damage * (suit.damage or 1)
        spec.cooldown = suit.cooldown or spec.cooldown
        spec.range = spec.range + (suit.range or 0)
        spec.effect = suit.effect
    end
    return spec
end

--- The hand's name, to show: "Pair", "Full house"...
function Public.hand_name(hand_type)
    return { 'high_stakes.hand_' .. Cards.hand_type_names[hand_type] }
end

local function draw_label(tower)
    local entity = tower.entity
    local color = Settings.tower_colors[tower.type]
    local owner = game.get_player(State.get().seats[tower.seat] or 0)
    tower.label = rendering.draw_text {
        text = { '', Public.hand_name(tower.type), '\n', tower.text },
        surface = entity.surface,
        target = { entity = entity, offset = { 0, -entity.tile_height / 2 - 1.2 } },
        color = color,
        scale = 1,
        alignment = 'center',
        vertical_alignment = 'middle',
        use_rich_text = true
    }
    if owner then
        tower.range_circle = rendering.draw_circle {
            surface = entity.surface,
            target = entity,
            radius = tower.range,
            color = { color[1] * 0.3, color[2] * 0.3, color[3] * 0.3, 0.3 },
            width = 2,
            filled = false,
            players = { owner },
            only_in_alt_mode = true
        }
    end
end

--- Makes an entity a tower: one that was just built, or one created by Public.create.
function Public.register(entity, seat, spec)
    entity.destructible = false
    entity.minable_flag = false
    entity.operable = false
    entity.rotatable = false
    entity.disabled_by_script = true

    local tower = {
        entity = entity,
        seat = seat,
        type = spec.type,
        rank = spec.rank,
        suit = spec.suit,
        damage = spec.damage,
        cooldown = spec.cooldown,
        range = spec.range,
        effect = spec.effect,
        text = spec.text,
        next_attack = 0
    }
    State.get().towers[entity.unit_number] = tower
    draw_label(tower)
    return tower
end

--- Creates a tower at this position.
---@return table? tower nil if the entity couldn't be created
function Public.create(surface, seat, spec, position)
    local entity = surface.create_entity { name = spec.entity, position = position, force = 'player', raise_built = false }
    if not entity then
        return nil
    end
    return Public.register(entity, seat, spec)
end

local function destroy(tower)
    if tower.label and tower.label.valid then
        tower.label.destroy()
    end
    if tower.range_circle and tower.range_circle.valid then
        tower.range_circle.destroy()
    end
    if tower.entity.valid then
        tower.entity.destroy()
    end
end

--- Destroys every tower in a seat's plot, or every tower when seat is nil.
function Public.remove(seat)
    local towers = State.get().towers
    for id, tower in pairs(towers) do
        if seat == nil or tower.seat == seat then
            destroy(tower)
            towers[id] = nil
        end
    end
end

--- How many towers a seat has.
function Public.count(seat)
    local n = 0
    for _, tower in pairs(State.get().towers) do
        if tower.seat == seat then
            n = n + 1
        end
    end
    return n
end

-- Attacking ---------------------------------------------------------------------------------

local function distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

local function shot(surface, from, to, color, width)
    rendering.draw_line {
        surface = surface,
        from = from,
        to = to,
        color = color,
        width = width or 2,
        time_to_live = 8
    }
end

local function ring(surface, target, radius, color)
    rendering.draw_circle {
        surface = surface,
        target = target,
        radius = radius,
        color = { color[1], color[2], color[3], 0.4 },
        filled = true,
        time_to_live = 10,
        draw_on_ground = true
    }
end

local function effect(surface, name, position)
    if prototypes.entity[name] then
        surface.create_entity { name = name, position = position }
    end
end

local function nearby(creeps, centre, radius, except)
    local result = {}
    for _, creep in pairs(creeps) do
        if creep ~= except and creep.entity.valid and distance(creep.entity.position, centre) <= radius then
            result[#result + 1] = creep
        end
    end
    return result
end

local function attack(tower, target, creeps, tick)
    local entity = tower.entity
    local surface = entity.surface
    local color = Settings.tower_colors[tower.type]
    local from = entity.position
    local to = target.entity.position
    local damage = tower.damage
    local kind = tower.effect

    if kind == 'critical' and random() < Settings.critical_chance then
        damage = damage * Settings.critical_factor
        effect(surface, 'big-explosion', to)
    end

    shot(surface, from, to, color, (tower.type >= types.four_of_a_kind) and 4 or 2)

    if kind == 'chain' then
        local hit = { [target] = true }
        local current = target
        local amount = damage
        Waves.damage(current, amount, tick)
        for _ = 1, Settings.chain_jumps do
            amount = amount * Settings.chain_falloff
            local next_creep, best = nil, math.huge
            for _, creep in pairs(creeps) do
                if not hit[creep] and creep.entity.valid and current.entity.valid then
                    local d = distance(creep.entity.position, current.entity.position)
                    if d <= Settings.chain_radius and d < best then
                        next_creep, best = creep, d
                    end
                end
            end
            if not next_creep then
                break
            end
            if current.entity.valid then
                shot(surface, current.entity.position, next_creep.entity.position, { 0.6, 0.8, 1 }, 1)
            end
            hit[next_creep] = true
            current = next_creep
            Waves.damage(current, amount, tick)
        end
        return
    end

    if kind == 'splash' or kind == 'frost' then
        local radius = kind == 'frost' and Settings.frost_radius or Settings.splash_radius
        ring(surface, to, radius, color)
        effect(surface, 'explosion', to)
        for _, creep in pairs(nearby(creeps, to, radius, target)) do
            Waves.damage(creep, damage * Settings.splash_share, tick)
            if kind == 'frost' then
                Waves.slow(creep, tick)
            end
        end
        if kind == 'frost' then
            Waves.slow(target, tick)
        end
        Waves.damage(target, damage, tick)
        return
    end

    if kind == 'burn' then
        Waves.burn(target, damage * Settings.burn_share, tick)
    elseif kind == 'slow' then
        Waves.slow(target, tick)
    elseif kind == 'stun' and random() < Settings.stun_chance then
        Waves.stun(target, tick)
        effect(surface, 'explosion', to)
    end
    Waves.damage(target, damage, tick)
end

--- Every tower that's ready hits the creep in its plot that's furthest along the path.
function Public.update(tick)
    local state = State.get()
    local by_seat = Waves.creeps_by_seat()
    for id, tower in pairs(state.towers) do
        if not tower.entity.valid then
            state.towers[id] = nil
        elseif tick >= tower.next_attack then
            local creeps = by_seat[tower.seat]
            if creeps then
                local from = tower.entity.position
                local target, best = nil, -math.huge
                for _, creep in pairs(creeps) do
                    if creep.entity.valid and distance(creep.entity.position, from) <= tower.range then
                        local progress = Waves.progress(creep)
                        if progress > best then
                            target, best = creep, progress
                        end
                    end
                end
                if target then
                    attack(tower, target, creeps, tick)
                    tower.next_attack = tick + tower.cooldown
                end
            end
        end
    end
end

--- The last boss wrecks one of the seat's towers: four of a kind first, or any.
---@return table? tower the wrecked tower's record
function Public.wreck(seat)
    local towers = State.get().towers
    local quads, any = {}, {}
    for id, tower in pairs(towers) do
        if tower.seat == seat and tower.entity.valid then
            any[#any + 1] = id
            if tower.type == types.four_of_a_kind then
                quads[#quads + 1] = id
            end
        end
    end
    local list = #quads > 0 and quads or any
    if #list == 0 then
        return nil
    end
    local id = list[random(#list)]
    local tower = towers[id]
    effect(tower.entity.surface, 'big-explosion', tower.entity.position)
    destroy(tower)
    towers[id] = nil
    return tower
end

return Public
