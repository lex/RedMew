-- Towers: what the players build, upgrade and sell. The entity is only what a tower looks like;
-- the script picks its targets and deals its damage, as its line and level say (settings.lua).

local Creeps = require 'map_gen.maps.convergence.creeps'
local Settings = require 'map_gen.maps.convergence.settings'
local State = require 'map_gen.maps.convergence.state'

local sqrt = math.sqrt

local Public = {}

-- how often towers look for targets, in ticks
Public.interval = 6

-- the line each tower entity belongs to
Public.line_of_entity = {}
for name, line in pairs(Settings.lines) do
    Public.line_of_entity[line.entity] = name
end

function Public.line_name(name)
    return { 'convergence.line_' .. name }
end

function Public.level_stats(tower)
    return Settings.lines[tower.line].levels[tower.level]
end

local function owner_name(tower)
    local player = game.get_player(tower.owner)
    return player and player.name or ''
end

local function draw_label(tower)
    if tower.label and tower.label.valid then
        tower.label.destroy()
    end
    local entity = tower.entity
    tower.label = rendering.draw_text {
        text = { 'convergence.tower_label', Public.line_name(tower.line), tower.level },
        surface = entity.surface,
        target = { entity = entity, offset = { 0, -entity.tile_height / 2 - 0.6 } },
        color = { 1, 1, 1 },
        scale = 1.2,
        alignment = 'center',
        vertical_alignment = 'middle'
    }
end

local function destroy_drawings(tower)
    for _, key in pairs({ 'label', 'range_circle' }) do
        if tower[key] and tower[key].valid then
            tower[key].destroy()
        end
    end
end

-- beacons boost the damage of the towers round them: each tower takes its best beacon's aura
function Public.update_auras()
    local towers = State.get().towers
    local beacons = {}
    for _, tower in pairs(towers) do
        if tower.line == 'beacon' and tower.entity.valid then
            beacons[#beacons + 1] = tower
        end
    end
    for _, tower in pairs(towers) do
        local best = 0
        if tower.line ~= 'beacon' and tower.entity.valid then
            local p = tower.entity.position
            for _, beacon in pairs(beacons) do
                local stats = Public.level_stats(beacon)
                local b = beacon.entity.position
                local dx, dy = p.x - b.x, p.y - b.y
                if sqrt(dx * dx + dy * dy) <= stats.range and stats.aura > best then
                    best = stats.aura
                end
            end
        end
        tower.aura = best
    end
end

--- Makes an entity a tower of a line, owned by a player.
function Public.register(entity, line_name, owner)
    entity.destructible = false
    entity.minable_flag = false
    entity.rotatable = false
    entity.disabled_by_script = true
    local tower = {
        id = entity.unit_number,
        entity = entity,
        line = line_name,
        level = 1,
        owner = owner,
        spent = Settings.lines[line_name].levels[1].cost,
        next_attack = 0,
        aura = 0
    }
    State.get().towers[tower.id] = tower
    draw_label(tower)
    Public.update_auras()
    return tower
end

--- Creates a tower of a line at a position.
---@return table? tower
function Public.create(surface, line_name, owner, position)
    local entity = surface.create_entity { name = Settings.lines[line_name].entity, position = position, force = 'player', raise_built = false }
    if not entity then
        return nil
    end
    return Public.register(entity, line_name, owner)
end

--- What the next level costs, or nil at the top level.
function Public.upgrade_cost(tower)
    local next_level = Settings.lines[tower.line].levels[tower.level + 1]
    return next_level and next_level.cost
end

--- Raises a tower a level; the caller has taken the gold.
function Public.upgrade(tower)
    local cost = Public.upgrade_cost(tower)
    if not cost then
        return false
    end
    tower.level = tower.level + 1
    tower.spent = tower.spent + cost
    draw_label(tower)
    if tower.line == 'beacon' then
        Public.update_auras()
    end
    return true
end

--- What selling a tower gives back.
function Public.sell_value(tower)
    return math.floor(tower.spent * Settings.sell_share)
end

--- Removes a tower; the caller pays out its sell value.
function Public.remove(tower)
    destroy_drawings(tower)
    if tower.entity.valid then
        tower.entity.destroy()
    end
    State.get().towers[tower.id] = nil
    if tower.line == 'beacon' then
        Public.update_auras()
    end
end

--- Removes every tower.
function Public.remove_all()
    local towers = State.get().towers
    for id, tower in pairs(towers) do
        destroy_drawings(tower)
        if tower.entity.valid then
            tower.entity.destroy()
        end
        towers[id] = nil
    end
end

function Public.get(id)
    return State.get().towers[id]
end

--- Shows a tower's range to a player, until shown another's.
function Public.show_range(tower, player)
    local state = State.get()
    state.range_circles = state.range_circles or {}
    local old = state.range_circles[player.index]
    if old and old.valid then
        old.destroy()
    end
    local stats = Public.level_stats(tower)
    state.range_circles[player.index] = rendering.draw_circle {
        surface = tower.entity.surface,
        target = tower.entity,
        radius = stats.range,
        color = { 0.2, 0.4, 0.2, 0.2 },
        width = 2,
        filled = false,
        players = { player }
    }
end

-- Attacking ---------------------------------------------------------------------------------

local function distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

local colors = {
    gun = { 1, 0.9, 0.4 },
    laser = { 1, 0.2, 0.2 },
    flamer = { 1, 0.5, 0.1 },
    flak = { 0.8, 0.8, 1 },
    cryo = { 0.5, 0.8, 1 },
    trap = { 1, 0.4, 0.1 }
}

local function can_hit(targets, creep)
    if targets == 'both' then
        return true
    end
    return (targets == 'air') == (creep.air == true)
end

local function shot(surface, from, to, color)
    rendering.draw_line { surface = surface, from = from, to = to, color = color, width = 2, time_to_live = 6 }
end

local function ring(surface, position, radius, color)
    rendering.draw_circle {
        surface = surface,
        target = position,
        radius = radius,
        color = { color[1], color[2], color[3], 0.35 },
        filled = true,
        time_to_live = 10,
        draw_on_ground = true
    }
end

local function attack(tower, creeps, tick)
    local line = Settings.lines[tower.line]
    local stats = line.levels[tower.level]
    local entity = tower.entity
    local surface = entity.surface
    local from = entity.position
    local damage = stats.damage * (1 + (tower.aura or 0))
    local color = colors[tower.line]

    -- traps and cryo hit everything in reach at once
    if line.trap or line.effect == 'slow' then
        local hit = false
        for _, creep in pairs(creeps) do
            if creep.entity.valid and can_hit(line.targets, creep) and distance(creep.entity.position, from) <= stats.range then
                if not (line.trap and creep.shielded) then
                    hit = true
                    if line.effect == 'slow' then
                        Creeps.slow(creep, stats.slow, tick)
                    end
                    Creeps.damage(creep, damage, tower.owner)
                end
            end
        end
        if hit then
            ring(surface, from, stats.range, color)
        end
        return hit
    end

    -- the rest pick the creep in range that's furthest along
    local target, best = nil, -math.huge
    for _, creep in pairs(creeps) do
        if creep.entity.valid and can_hit(line.targets, creep) and distance(creep.entity.position, from) <= stats.range then
            local progress = Creeps.progress(creep)
            if progress > best then
                target, best = creep, progress
            end
        end
    end
    if not target then
        return false
    end
    local to = target.entity.position
    shot(surface, from, to, color)

    if line.effect == 'splash' or line.effect == 'burn' then
        ring(surface, to, Settings.splash_radius, color)
        for _, creep in pairs(creeps) do
            if creep ~= target and creep.entity.valid and can_hit(line.targets, creep) and distance(creep.entity.position, to) <= Settings.splash_radius then
                Creeps.damage(creep, damage * Settings.splash_share, tower.owner)
                if line.effect == 'burn' and creep.entity.valid then
                    Creeps.burn(creep, damage * Settings.burn_share, tick, tower.owner)
                end
            end
        end
        if line.effect == 'burn' then
            Creeps.burn(target, damage * Settings.burn_share, tick, tower.owner)
        end
    end
    Creeps.damage(target, damage, tower.owner)
    return true
end

--- Every tower that's ready attacks.
function Public.update(tick)
    local state = State.get()
    if next(state.creeps) == nil then
        return
    end
    local creeps = {}
    for _, creep in pairs(state.creeps) do
        creeps[#creeps + 1] = creep
    end
    for id, tower in pairs(state.towers) do
        if not tower.entity.valid then
            state.towers[id] = nil
        elseif tower.line ~= 'beacon' and tick >= tower.next_attack then
            if attack(tower, creeps, tick) then
                tower.next_attack = tick + Settings.lines[tower.line].levels[tower.level].cooldown
            end
        end
    end
end

Public.owner_name = owner_name

return Public
