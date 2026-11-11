-- The waves' biters. Ground biters walk their lane's path to the core in short hops: asked to
-- walk far across open ground, the game's pathfinder plans coarsely and cuts across the felt.
-- Air waves are combat robots that the script flies along the same path.
--
-- A creep's health is the wave's (settings.lua). The script keeps it, and shows it on the
-- entity's own health bar as a share of its max health.

local Layout = require 'map_gen.maps.convergence.layout'
local Settings = require 'map_gen.maps.convergence.settings'
local State = require 'map_gen.maps.convergence.state'

local sqrt = math.sqrt
local max = math.max

local Public = {}

-- tiles between the points a creep heads for
local hop = 3

-- what happens when a creep is killed or reaches the core, set by the game
local handlers = {}

--- Sets what to call when a creep is killed (creep) and when one reaches the core (creep).
function Public.set_handlers(on_kill, on_leak)
    handlers.on_kill = on_kill
    handlers.on_leak = on_leak
end

-- each seat's points along its path, worked out once: they only depend on the layout
local waypoint_cache = {}

local function waypoints(seat)
    local points = waypoint_cache[seat]
    if not points then
        points = Layout.waypoints(seat, hop)
        waypoint_cache[seat] = points
    end
    return points
end
Public.waypoints = waypoints

local function command(creep)
    creep.entity.commandable.set_command {
        type = defines.command.go_to_location,
        destination = waypoints(creep.seat)[creep.leg],
        radius = 1,
        distraction = defines.distraction.none,
        pathfind_flags = { allow_paths_through_own_entities = true, prefer_straight_paths = true, cache = false }
    }
end

--- Sends one of a wave's creeps down a seat's lane.
---@return table? creep
function Public.spawn(surface, seat, wave_index)
    local wave = Settings.waves[wave_index]
    local points = waypoints(seat)
    local entity = surface.create_entity { name = wave.unit, position = points[1], force = 'enemy' }
    if not entity then
        return nil
    end
    local health = Settings.biter_health(wave_index)
    local creep = {
        entity = entity,
        seat = seat,
        wave = wave_index,
        health = health,
        max_health = health,
        leg = 2,
        bounty = wave.bounty,
        air = wave.air,
        shielded = wave.shielded,
        regen = wave.regen,
        boss = wave.boss
    }
    State.get().creeps[entity.unit_number] = creep
    if wave.air then
        -- a robot that lives until it's shot down or reaches the core
        entity.time_to_live = 60 * 60 * 60
    else
        entity.speed = Settings.ground_speed
        command(creep)
    end
    return creep
end

--- How far along its path a creep is: more is further. Lanes merge, so it's comparable between
--- creeps of different seats only roughly; towers use it to pick a target.
function Public.progress(creep)
    local point = waypoints(creep.seat)[creep.leg]
    local position = creep.entity.position
    local dx, dy = point.x - position.x, point.y - position.y
    return creep.leg * hop - sqrt(dx * dx + dy * dy)
end

--- Takes health off a creep, credited to a player; it dies when it has none left.
---@param creep table
---@param amount number
---@param player_index integer? who gets the bounty if this kills it
function Public.damage(creep, amount, player_index)
    local entity = creep.entity
    if not entity.valid or creep.health <= 0 then
        return
    end
    creep.health = creep.health - amount
    if creep.health <= 0 then
        creep.killer = player_index
        entity.die('player')
        return
    end
    entity.health = max(entity.max_health * creep.health / creep.max_health, 0.01)
end

--- Slows a creep by this share for a while, unless it's shielded.
function Public.slow(creep, amount, tick)
    if creep.shielded then
        return
    end
    if (creep.slow_until or 0) > tick and (creep.slow_amount or 0) > amount then
        return
    end
    creep.slow_amount = amount
    creep.slow_until = tick + Settings.slow_ticks
end

--- Sets a creep burning: it loses this much more health over the next burn_ticks.
function Public.burn(creep, amount, tick, player_index)
    local per_tick = amount / Settings.burn_ticks
    if (creep.burn_until or 0) > tick and (creep.burn_per_tick or 0) > per_tick then
        return
    end
    creep.burn_per_tick = per_tick
    creep.burn_until = tick + Settings.burn_ticks
    creep.burn_owner = player_index
end

local function leak(creep)
    State.get().creeps[creep.entity.unit_number] = nil
    if handlers.on_leak then
        handlers.on_leak(creep)
    end
    if creep.entity.valid then
        creep.entity.destroy()
    end
end

local function speed_of(creep, tick)
    local speed = creep.air and Settings.air_speed or Settings.ground_speed
    if (creep.slow_until or 0) > tick then
        speed = speed * (1 - creep.slow_amount)
    end
    return speed
end

--- Flies the air creeps a tick along their paths; call every tick.
function Public.fly(tick)
    for _, creep in pairs(State.get().creeps) do
        local entity = creep.entity
        if creep.air and entity.valid then
            local points = waypoints(creep.seat)
            local target = points[creep.leg]
            local position = entity.position
            local dx, dy = target.x - position.x, target.y - position.y
            local distance = sqrt(dx * dx + dy * dy)
            local speed = speed_of(creep, tick)
            if distance <= speed then
                creep.leg = creep.leg + 1
                if creep.leg > #points then
                    leak(creep)
                else
                    entity.teleport(target)
                end
            else
                entity.teleport { position.x + dx / distance * speed, position.y + dy / distance * speed }
            end
        end
    end
end

--- Burns, regeneration and ground speed, every `interval` ticks.
function Public.update(tick, interval)
    local creeps = State.get().creeps
    for id, creep in pairs(creeps) do
        local entity = creep.entity
        if not entity.valid then
            creeps[id] = nil
        else
            if creep.regen and creep.health < creep.max_health then
                creep.health = math.min(creep.max_health, creep.health + creep.max_health * creep.regen * interval / 60)
                entity.health = max(entity.max_health * creep.health / creep.max_health, 0.01)
            end
            if (creep.burn_until or 0) > tick then
                Public.damage(creep, creep.burn_per_tick * interval, creep.burn_owner)
            end
            if entity.valid and not creep.air then
                local speed = speed_of(creep, tick)
                if entity.speed ~= speed then
                    entity.speed = speed
                end
            end
        end
    end
end

--- A ground creep reached a point on its path: send it on to the next, or into the core.
function Public.on_ai_command_completed(event)
    local creep = State.get().creeps[event.unit_number]
    if not creep or not creep.entity.valid or creep.air then
        return
    end
    if event.result == defines.behavior_result.success then
        creep.leg = creep.leg + 1
    end
    if creep.leg > #waypoints(creep.seat) then
        leak(creep)
        return
    end
    command(creep)
end

--- A creep died: pay its bounty, whatever killed it.
function Public.on_entity_died(event)
    local id = event.entity.unit_number
    local creeps = State.get().creeps
    local creep = id and creeps[id]
    if not creep then
        return
    end
    creeps[id] = nil
    if handlers.on_kill then
        handlers.on_kill(creep)
    end
end

--- Removes every creep without bounty or leak.
function Public.clear()
    local creeps = State.get().creeps
    for id, creep in pairs(creeps) do
        creeps[id] = nil
        if creep.entity.valid then
            creep.entity.destroy()
        end
    end
end

function Public.count()
    return table_size(State.get().creeps)
end

return Public
