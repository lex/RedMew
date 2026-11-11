-- Waves of biters: each walks its seat's path to the vault, stealing chips if it gets there.
--
-- A biter's health here is the wave's (settings.lua), far more than the game's biters have. The
-- script keeps it, and shows it on the biter's own health bar as a share of its max health.

local Layout = require 'map_gen.maps.high_stakes.layout'
local Settings = require 'map_gen.maps.high_stakes.settings'
local State = require 'map_gen.maps.high_stakes.state'

local sqrt = math.sqrt
local max = math.max

local Public = {}

-- what happens when a creep dies or reaches the vault, set by the scenario
local handlers = {}

--- Sets what to call when a creep is killed (creep) and when one reaches its vault (creep).
function Public.set_handlers(on_kill, on_leak)
    handlers.on_kill = on_kill
    handlers.on_leak = on_leak
end

-- tiles between the points a biter walks to: short hops keep it on the path. Asked to walk far
-- across open ground, the game's pathfinder plans coarsely and cuts across the felt.
local hop = 3

-- each seat's points along the path, worked out once: they only depend on the layout
local waypoint_cache = {}

local function waypoints(seat)
    local points = waypoint_cache[seat]
    if points then
        return points
    end
    points = {}
    local corners = Layout.waypoints(seat)
    for i = 1, #corners - 1 do
        local a, b = corners[i], corners[i + 1]
        local length = math.max(math.abs(b.x - a.x), math.abs(b.y - a.y))
        local steps = math.max(1, math.ceil(length / hop))
        for step = 0, steps - 1 do
            local t = step / steps
            points[#points + 1] = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
        end
    end
    points[#points + 1] = corners[#corners]
    waypoint_cache[seat] = points
    return points
end

local function command(creep)
    local entity = creep.entity
    local destination = waypoints(creep.seat)[creep.leg]
    entity.commandable.set_command {
        type = defines.command.go_to_location,
        destination = destination,
        radius = 1,
        distraction = defines.distraction.none,
        pathfind_flags = { allow_paths_through_own_entities = true, prefer_straight_paths = true, cache = false }
    }
end

--- Sends a wave's biter into the seat's plot.
---@return table? creep
function Public.spawn(surface, seat, wave_index)
    local wave = Settings.waves[wave_index]
    local points = waypoints(seat)
    local entity = surface.create_entity { name = wave.unit, position = points[1], force = 'enemy' }
    if not entity then
        return nil
    end
    entity.speed = Settings.biter_speed
    local health = Settings.biter_health(wave)
    local creep = {
        entity = entity,
        seat = seat,
        wave = wave_index,
        health = health,
        max_health = health,
        leg = 2,
        loot = wave.loot,
        bounty = wave.bounty,
        boss = wave.boss
    }
    if wave.boss and wave_index == #Settings.waves then
        creep.wrecker = true
        creep.next_wreck = game.tick + Settings.wrecker_interval
    end
    State.get().creeps[entity.unit_number] = creep
    command(creep)
    return creep
end

--- Creeps grouped by seat: seat -> list.
function Public.creeps_by_seat()
    local by_seat = {}
    for _, creep in pairs(State.get().creeps) do
        local list = by_seat[creep.seat]
        if not list then
            list = {}
            by_seat[creep.seat] = list
        end
        list[#list + 1] = creep
    end
    return by_seat
end

--- How far along the path a creep is: more is further.
function Public.progress(creep)
    local point = waypoints(creep.seat)[creep.leg]
    local position = creep.entity.position
    local dx, dy = point.x - position.x, point.y - position.y
    return creep.leg * 10000 - sqrt(dx * dx + dy * dy)
end

local function forget(creep)
    State.get().creeps[creep.entity.unit_number] = nil
end

--- Takes health off a creep; it dies when it has none left.
function Public.damage(creep, amount, _)
    local entity = creep.entity
    if not entity.valid or creep.health <= 0 then
        return
    end
    creep.health = creep.health - amount
    if creep.health <= 0 then
        creep.killed = true
        entity.die('player')
        return
    end
    entity.health = max(entity.max_health * creep.health / creep.max_health, 0.01)
end

function Public.slow(creep, tick)
    creep.slow_until = max(creep.slow_until or 0, tick + Settings.slow_ticks)
end

function Public.stun(creep, tick)
    creep.stun_until = max(creep.stun_until or 0, tick + Settings.stun_ticks)
end

--- Sets a creep burning: it loses this much more health over the next burn_ticks.
function Public.burn(creep, amount, tick)
    local per_tick = amount / Settings.burn_ticks
    if (creep.burn_until or 0) > tick and (creep.burn_per_tick or 0) > per_tick then
        per_tick = creep.burn_per_tick
    end
    creep.burn_per_tick = per_tick
    creep.burn_until = tick + Settings.burn_ticks
end

local function leak(creep)
    forget(creep)
    if handlers.on_leak then
        handlers.on_leak(creep)
    end
    if creep.entity.valid then
        creep.entity.destroy()
    end
end

--- Burns, slows and stuns, every `interval` ticks; calls wreck(seat) when the last boss wrecks.
function Public.update(tick, interval, wreck)
    for id, creep in pairs(State.get().creeps) do
        local entity = creep.entity
        if not entity.valid then
            State.get().creeps[id] = nil
        else
            if (creep.burn_until or 0) > tick then
                Public.damage(creep, creep.burn_per_tick * interval, tick)
            end
            if entity.valid then
                local speed = Settings.biter_speed
                if (creep.stun_until or 0) > tick then
                    speed = 0.0001
                elseif (creep.slow_until or 0) > tick then
                    speed = speed * Settings.slow_factor
                end
                if entity.speed ~= speed then
                    entity.speed = speed
                end
                if creep.wrecker and tick >= creep.next_wreck then
                    creep.next_wreck = tick + Settings.wrecker_interval
                    if math.random(2) == 1 then
                        wreck(creep.seat)
                    end
                end
            end
        end
    end
end

--- A creep finished walking to a waypoint: send it on to the next, or into the vault.
function Public.on_ai_command_completed(event)
    local creep = State.get().creeps[event.unit_number]
    if not creep or not creep.entity.valid then
        return
    end
    local points = waypoints(creep.seat)
    if event.result == defines.behavior_result.success then
        creep.leg = creep.leg + 1
    end
    if creep.leg > #points then
        leak(creep)
        return
    end
    command(creep)
end

--- A creep died: pay its bounty, whatever killed it.
function Public.on_entity_died(event)
    local entity = event.entity
    local id = entity.unit_number
    if not id then
        return
    end
    local creep = State.get().creeps[id]
    if not creep then
        return
    end
    State.get().creeps[id] = nil
    if handlers.on_kill then
        handlers.on_kill(creep)
    end
end

--- Removes every creep, or every creep in one seat's plot, without bounty or loot.
function Public.clear(seat)
    local creeps = State.get().creeps
    for id, creep in pairs(creeps) do
        if seat == nil or creep.seat == seat then
            creeps[id] = nil
            if creep.entity.valid then
                creep.entity.destroy()
            end
        end
    end
end

function Public.count()
    return table_size(State.get().creeps)
end

return Public
