-- Pure-Lua layout for the Danger Ores "Circuit Board" map: the world is a giant printed circuit
-- board. ZERO Factorio dependencies. Randomness comes from the injected `random(n) -> [1, n]`,
-- drawn once for a seed; everything after that is a hash of (cell, seed), so the map is
-- infinite, never repeats and needs nothing stored.
--
-- The board itself is the board ink (iron). Parts are thrown at it like darts: square chips,
-- long chips and small ones, of every size, wherever they land clear of one another (see
-- candidates_at), so they cluster and leave open board, with no grid. Chip bodies are the body
-- ink (coal), with rounded corners; pins and traces the trace ink (copper). From nearly every pin
-- a trace runs out, bends 45 degrees, runs on and ends in a via; the traces of a chip's side leave
-- together as a bus. Big chips get small parts (capacitors) by their corners. Under the parts the
-- board is cut into ground zones, and further from spawn more of them are flooded with copper,
-- with bare board kept round each chip: more copper where the rockets get built.
--
-- Everything is drawn wide, traces 40 tiles and more: a build site should sit on one ore.
-- Spawn sits on a CPU: a metal lid (board ink) in a body-ink frame, with a ring of pins round
-- it and a trace out of each pin.
local Shapes = require 'map_gen.maps.danger_ores.modules.art_shapes'

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local min = math.min
local max = math.max

local Public = {}

--- Default settings; `Public.new` fills any the caller leaves out from these. Lengths in tiles.
Public.defaults = {
    board_ink = 'iron-ore',
    trace_ink = 'copper-ore',
    body_ink = 'coal',
    cell = 800, -- spawn sits in the middle of one
    trace = 40, -- trace width
    pin = 44, -- pin width
    pin_length = 80,
    pin_pitch = 140, -- at least this far apart, centre to centre
    via = 46, -- via radius; its hole is the body ink
    via_hole = 16,
    -- the chance a pin gets a trace, and that a ground zone is flooded with copper, near spawn
    -- and far out,
    -- blending from blend_near to blend_far tiles from spawn
    trace_chance = {0.85, 1},
    flood_chance = {0, 0.65},
    -- ground zones under the parts: staggered rows of zones, a gap of board between them and
    -- their corners cut; a flooded one is copper but for a clearance of board round each chip
    zone_height = 1400,
    zone_width = {900, 2200},
    zone_gap = 60,
    zone_cut = 200,
    clearance = 50,
    -- traces and pins get wider further out, by this much
    widen = {1, 1.5},
    blend_near = 400,
    blend_far = 2000,
    -- spawn's CPU: half its lid, its frame, its pins per side
    cpu = 150,
    cpu_frame = 22,
    cpu_pin_pitch = 100,
    cpu_pin_length = 100,
    -- no cell's component closer to spawn than this, so the CPU stands alone
    spawn_clear = 330 -- no part's footprint this close to spawn
}

-- layers: higher draws over lower
local CLEAR, TRACE, PAD, BODY, HOLE, LID = 0, 1, 2, 3, 4, 5

local function lerp(range, t)
    return range[1] + (range[2] - range[1]) * t
end

-- A piece: a box {x0, y0, x1, y1}, a stroke (a round-capped segment of radius r), or a disc,
-- with its ink, layer and bounds.
local function box(x0, y0, x1, y1, ink, layer)
    return {kind = 'box', x0 = min(x0, x1), y0 = min(y0, y1), x1 = max(x0, x1), y1 = max(y0, y1), ink = ink, layer = layer,
        bx0 = min(x0, x1), by0 = min(y0, y1), bx1 = max(x0, x1), by1 = max(y0, y1)}
end

-- A box with its corners rounded to radius `r`.
local function round_box(x0, y0, x1, y1, r, ink, layer)
    local p = box(x0, y0, x1, y1, ink, layer)
    p.kind, p.r = 'round', r
    return p
end

local function stroke(ax, ay, bx, by, r, ink, layer)
    return {kind = 'stroke', ax = ax, ay = ay, bx = bx, by = by, r2 = r * r, ink = ink, layer = layer,
        bx0 = min(ax, bx) - r, by0 = min(ay, by) - r, bx1 = max(ax, bx) + r, by1 = max(ay, by) + r}
end

local function disc(x, y, r, ink, layer)
    return {kind = 'disc', x = x, y = y, r2 = r * r, ink = ink, layer = layer, bx0 = x - r, by0 = y - r, bx1 = x + r, by1 = y + r}
end

local function segment_d2(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local wx, wy = px - ax, py - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = max(0, min(1, (wx * dx + wy * dy) / len2))
    end
    local ex, ey = wx - t * dx, wy - t * dy
    return ex * ex + ey * ey
end

local function covers(p, x, y)
    if x < p.bx0 or x > p.bx1 or y < p.by0 or y > p.by1 then
        return false
    end
    local kind = p.kind
    if kind == 'box' then
        return true
    elseif kind == 'round' then
        -- outside a corner's square, it is the box; inside, within r of the corner's centre
        local r = p.r
        local dx = x < p.x0 + r and p.x0 + r - x or (x > p.x1 - r and x - (p.x1 - r) or 0)
        local dy = y < p.y0 + r and p.y0 + r - y or (y > p.y1 - r and y - (p.y1 - r) or 0)
        return dx * dx + dy * dy <= r * r
    elseif kind == 'stroke' then
        return segment_d2(x, y, p.ax, p.ay, p.bx, p.by) <= p.r2
    end
    local dx, dy = x - p.x, y - p.y
    return dx * dx + dy * dy <= p.r2
end
Public.covers = covers

--- A new layout. `opts` = {random = random(n), any of Public.defaults to override}.
function Public.new(opts)
    local settings = {}
    for k, v in pairs(Public.defaults) do
        settings[k] = v
    end
    for k, v in pairs(opts) do
        settings[k] = v
    end

    local seed_hash = settings.random(Shapes.PRIME - 1)
    local hash_stream = Shapes.hash_stream
    local cell = settings.cell
    local board, copper, coal = settings.board_ink, settings.trace_ink, settings.body_ink
    local tw = settings.trace / 2
    local pin_w = settings.pin

    local function blend_at(x, y)
        local r = sqrt(x * x + y * y)
        return max(0, min(1, (r - settings.blend_near) / (settings.blend_far - settings.blend_near)))
    end

    -- A trace out of (x, y) heading (dx, dy) (a unit step along an axis): straight on for l1,
    -- a 45 degree bend to `side` for l2, then on for l3, either the way it was going or out to
    -- the side (`turn`), and a via at the end.
    local function add_trace(pieces, x, y, dx, dy, route)
        local side, l1, l2, l3 = route.side, route.l1, route.l2, route.l3
        local ddx, ddy = (dx - side * dy) * 0.7071, (dy + side * dx) * 0.7071
        local ax, ay = x + dx * l1, y + dy * l1
        local bx, by = ax + ddx * l2, ay + ddy * l2
        local ex, ey = dx, dy
        if route.turn then
            ex, ey = -side * dy, side * dx
        end
        local cx, cy = bx + ex * l3, by + ey * l3
        pieces[#pieces + 1] = stroke(x, y, ax, ay, tw, copper, TRACE)
        pieces[#pieces + 1] = stroke(ax, ay, bx, by, tw, copper, TRACE)
        pieces[#pieces + 1] = stroke(bx, by, cx, cy, tw, copper, TRACE)
        pieces[#pieces + 1] = disc(cx, cy, settings.via, copper, PAD)
        pieces[#pieces + 1] = disc(cx, cy, settings.via_hole, coal, HOLE)
    end

    -- A route for one trace.
    local function lone_route(next01)
        return {side = next01() < 0.5 and -1 or 1, l1 = 30 + next01() * 120, l2 = 50 + next01() * 110,
            l3 = 60 + next01() * 160, turn = next01() < 0.35}
    end

    -- A chip `hw` by `hh` (half sizes) at (cx, cy), with pins on its sides ('x' left and right,
    -- 'y' top and bottom, 'xy' all four), as many as fit `pin_pitch` apart. The traces of a side
    -- leave as a bus: all bend the same way, the pin nearest the bend first, so the bus keeps
    -- its spacing through the bend.
    local function add_chip(pieces, cx, cy, hw, hh, sides, chance, next01, lid)
        -- rounded corners, a third of the shorter half side, at most 60
        local r = min(60, min(hw, hh) / 3)
        pieces[#pieces + 1] = round_box(cx - hw, cy - hh, cx + hw, cy + hh, r, coal, BODY)
        if lid then
            local f = settings.cpu_frame
            pieces[#pieces + 1] = round_box(cx - hw + f, cy - hh + f, cx + hw - f, cy + hh - f, max(0, r - f), lid, LID)
        end
        local pw, pl = pin_w / 2, lid and settings.cpu_pin_length or settings.pin_length
        local function side(nx, ny)
            -- the side's half length, and how far out it is
            local half = nx ~= 0 and hh or hw
            local edge = nx ~= 0 and hw or hh
            local n = max(1, floor(2 * half / (lid and settings.cpu_pin_pitch or settings.pin_pitch)))
            local pitch = 2 * half / n
            local bus = lone_route(next01)
            -- the bend side as a direction along the pins: (-side * ny, side * nx)
            local along = nx ~= 0 and bus.side * nx or -bus.side * ny
            for k = 1, n do
                local t = -half + (k - 0.5) * pitch
                local px, py
                if nx ~= 0 then
                    px, py = cx + nx * edge, cy + t
                    pieces[#pieces + 1] = box(px, py - pw, px + nx * pl, py + pw, copper, PAD)
                else
                    px, py = cx + t, cy + ny * edge
                    pieces[#pieces + 1] = box(px - pw, py, px + pw, py + ny * pl, copper, PAD)
                end
                -- the pin's rank towards the bend: 0 nearest
                local rank = along > 0 and n - k or k - 1
                local route = {side = bus.side, l1 = bus.l1 + rank * pitch, l2 = bus.l2, turn = bus.turn,
                    l3 = bus.l3 + (k % 2) * 100 + (bus.turn and (n - 1 - rank) * pitch or 0)}
                if next01() < chance then
                    add_trace(pieces, px + nx * pl, py + ny * pl, nx, ny, route)
                end
            end
        end
        if sides:find('x') then
            side(-1, 0)
            side(1, 0)
        end
        if sides:find('y') then
            side(0, -1)
            side(0, 1)
        end
    end

    -- A small part (a resistor or capacitor) at (cx, cy): a body between two pads, a trace
    -- out of each.
    local function add_part(pieces, cx, cy, horizontal, next01)
        local hl, hw, pad = 70, 36, 50
        local ax, ay = horizontal and 1 or 0, horizontal and 0 or 1
        local bx, by = ay, ax
        pieces[#pieces + 1] = round_box(cx - ax * hl - bx * hw, cy - ay * hl - by * hw, cx + ax * hl + bx * hw, cy + ay * hl + by * hw, 14, coal, BODY)
        for _, s in ipairs({-1, 1}) do
            local px, py = cx + s * ax * (hl + pad / 2), cy + s * ay * (hl + pad / 2)
            pieces[#pieces + 1] = box(px - ax * pad / 2 - bx * (hw + 8), py - ay * pad / 2 - by * (hw + 8),
                px + ax * pad / 2 + bx * (hw + 8), py + ay * pad / 2 + by * (hw + 8), copper, PAD)
            add_trace(pieces, px + s * ax * pad / 2, py + s * ay * pad / 2, s * ax, s * ay, lone_route(next01))
        end
    end

    -- Where parts go: each cell throws a few candidates (a kind, a size, a spot anywhere in the
    -- cell, a priority), and a candidate is kept unless one of higher priority near it overlaps
    -- it, so where they land never follows the cells. That only reads candidates, so it is the
    -- same whichever chunk asks first.
    local GAP = 50 -- clear board kept between parts' footprints
    local candidates = {}
    local function candidates_at(i, j)
        local key = i .. ',' .. j
        local list = candidates[key]
        if list then
            return list
        end
        list = {}
        local next01 = hash_stream(seed_hash, i * 3 + 1, j * 5 + 2)
        for k = 1, 4 + floor(next01() * 3) do
            local cx, cy = (i - 0.5 + next01()) * cell, (j - 0.5 + next01()) * cell
            local blend = blend_at(cx, cy)
            local widen = lerp(settings.widen, blend)
            local pl = settings.pin_length * widen
            local c = {i = i, j = j, x = cx, y = cy, priority = next01(), seed = k, blend = blend}
            local roll = next01()
            if roll < 0.4 then
                local h = 170 + next01() * 70
                c.kind, c.hw, c.hh, c.sides = 'chip', h, h, 'xy'
            elseif roll < 0.65 then
                local long, short = 260 + next01() * 80, 100 + next01() * 30
                if next01() < 0.5 then
                    c.kind, c.hw, c.hh, c.sides = 'chip', long, short, 'y'
                else
                    c.kind, c.hw, c.hh, c.sides = 'chip', short, long, 'x'
                end
            else
                local h = 90 + next01() * 60
                c.kind, c.hw, c.hh, c.sides = 'chip', h, h * (0.6 + next01() * 0.4), next01() < 0.5 and 'xy' or 'x'
            end
            do
                c.ex = c.hw + (c.sides:find('x') and pl or 0)
                c.ey = c.hh + (c.sides:find('y') and pl or 0)
            end
            -- clear of spawn's CPU and its pins
            local dx = max(0, abs(cx) - c.ex)
            local dy = max(0, abs(cy) - c.ey)
            if dx * dx + dy * dy < settings.spawn_clear * settings.spawn_clear then
                c.priority = -1
            end
            list[#list + 1] = c
        end
        candidates[key] = list
        return list
    end

    local function overlaps(a, b)
        return abs(a.x - b.x) < a.ex + b.ex + GAP and abs(a.y - b.y) < a.ey + b.ey + GAP
    end

    -- The candidates that overlap c.
    local function neighbours(c)
        local list = c.near
        if not list then
            list = {}
            for di = -2, 2 do
                for dj = -2, 2 do
                    for _, o in ipairs(candidates_at(c.i + di, c.j + dj)) do
                        if o ~= c and o.priority >= 0 and overlaps(c, o) then
                            list[#list + 1] = o
                        end
                    end
                end
            end
            c.near = list
        end
        return list
    end

    -- Which candidates are kept, in rounds (Luby's): each round keeps every open candidate of
    -- higher priority than all the open ones it overlaps, and closes what those overlap; what is
    -- left open goes on to the next round, so gaps a loser left get filled. Each round only
    -- reads candidates a few cells round, so this too is the same whichever chunk asks first.
    local ROUNDS = 3
    local is_kept
    local function is_open(c, r)
        if r == 1 then
            return c.priority >= 0
        end
        c.open = c.open or {}
        local open = c.open[r]
        if open == nil then
            open = is_open(c, r - 1) and not is_kept(c, r - 1)
            if open then
                for _, o in ipairs(neighbours(c)) do
                    if is_kept(o, r - 1) then
                        open = false
                        break
                    end
                end
            end
            c.open[r] = open
        end
        return open
    end
    is_kept = function(c, r)
        c.kept = c.kept or {}
        local kept = c.kept[r]
        if kept == nil then
            kept = is_open(c, r)
            if kept then
                for _, o in ipairs(neighbours(c)) do
                    if o.priority > c.priority and is_open(o, r) then
                        kept = false
                        break
                    end
                end
            end
            c.kept[r] = kept
        end
        return kept
    end

    -- the candidates of cell (i, j) that are kept
    local function kept_at(i, j)
        local kept = {}
        for _, c in ipairs(candidates_at(i, j)) do
            for r = 1, ROUNDS do
                if is_kept(c, r) then
                    kept[#kept + 1] = c
                    break
                end
            end
        end
        return kept
    end

    -- A cell's pieces: what its kept candidates draw.
    local function make_cell(i, j)
        local pieces = {}
        for _, c in ipairs(kept_at(i, j)) do
            local next01 = hash_stream(seed_hash, i * 7 + c.seed, j * 11 + c.seed)
            local cx, cy, hw, hh = c.x, c.y, c.hw, c.hh
            local widen = lerp(settings.widen, c.blend)
            tw, pin_w = settings.trace * widen / 2, settings.pin * widen
            -- bare board round the chip and its pins, in a flooded zone
            local cl = settings.clearance
            pieces[#pieces + 1] = round_box(cx - c.ex - cl, cy - c.ey - cl, cx + c.ex + cl, cy + c.ey + cl, cl + 20, board, CLEAR)
            do
                add_chip(pieces, cx, cy, hw, hh, c.sides, lerp(settings.trace_chance, c.blend), next01)
                -- a big chip gets small parts by its corners, like the capacitors beside a chip
                if hw >= 160 and hh >= 100 then
                    for _, s in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
                        if next01() < 0.3 then
                            add_part(pieces, cx + s[1] * (hw + 90), cy + s[2] * (hh + 90), next01() < 0.5, next01)
                        end
                    end
                end
            end
        end
        tw, pin_w = settings.trace / 2, settings.pin
        return pieces
    end

    local cells = {}
    local function cell_at(i, j)
        local by_i = cells[i]
        if not by_i then
            by_i = {}
            cells[i] = by_i
        end
        local c = by_i[j]
        if not c then
            c = make_cell(i, j)
            by_i[j] = c
        end
        return c
    end

    -- spawn's CPU
    local spawn_pieces = {}
    do
        local next01 = hash_stream(seed_hash, 7, 7)
        local h = settings.cpu
        add_chip(spawn_pieces, 0, 0, h, h, 'xy', 1, next01, board)
    end

    -- The ground zone at (x, y): its row (staggered by a hashed offset) and column, and whether
    -- it is flooded, by the distance of its middle from spawn.
    local zone_height, zone_gap, zone_cut = settings.zone_height, settings.zone_gap, settings.zone_cut
    local zone_rows = {}
    local function zone_row(row)
        local r = zone_rows[row]
        if not r then
            local next01 = hash_stream(seed_hash, 2000003, row)
            local width = lerp(settings.zone_width, next01())
            r = {width = width, offset = next01() * width, flooded = {}}
            zone_rows[row] = r
        end
        return r
    end
    local function zone_ink(x, y)
        local row = floor(y / zone_height)
        local r = zone_row(row)
        local w = r.width
        local col = floor((x - r.offset) / w)
        local left, top = r.offset + col * w, row * zone_height
        -- distances to the nearest side across and down
        local dx = min(x - left, left + w - x)
        local dy = min(y - top, top + zone_height - y)
        local half = zone_gap / 2
        if dx < half or dy < half or dx + dy < zone_cut then
            return board
        end
        local flooded = r.flooded[col]
        if flooded == nil then
            local mx, my = left + w / 2, top + zone_height / 2
            flooded = hash_stream(seed_hash, col, 3000017 + row)() < lerp(settings.flood_chance, blend_at(mx, my))
            r.flooded[col] = flooded
        end
        return flooded and copper or board
    end

    -- the pieces that can touch the 32 x 32 chunk at (x0, y0), bottom layer first
    -- how far a cell's pieces can reach past its edge: a long chip's pins, the bus of its
    -- side and a trace's three legs
    local margin = 2600
    local reach = margin
    local function chunk_pieces(x0, y0)
        local list = {}
        local x1, y1 = x0 + 31, y0 + 31
        local function take(pieces)
            for _, p in ipairs(pieces) do
                if p.bx1 >= x0 and p.bx0 <= x1 and p.by1 >= y0 and p.by0 <= y1 then
                    list[#list + 1] = p
                end
            end
        end
        if x0 < reach and x1 > -reach and y0 < reach and y1 > -reach then
            take(spawn_pieces)
        end
        local half = cell / 2
        local i0, i1 = floor((x0 - margin + half) / cell), floor((x1 + margin + half) / cell)
        local j0, j1 = floor((y0 - margin + half) / cell), floor((y1 + margin + half) / cell)
        for i = i0, i1 do
            for j = j0, j1 do
                take(cell_at(i, j))
            end
        end
        -- stable by layer
        for k, p in ipairs(list) do
            p.order = k
        end
        table.sort(list, function(a, b)
            if a.layer ~= b.layer then
                return a.layer < b.layer
            end
            return a.order < b.order
        end)
        return list
    end

    local last_key, last_list
    local function ore_at(x, y)
        local x0, y0 = floor(x / 32) * 32, floor(y / 32) * 32
        local key = x0 .. ',' .. y0
        if key ~= last_key then
            last_key, last_list = key, chunk_pieces(x0, y0)
        end
        local list = last_list
        for k = #list, 1, -1 do
            local p = list[k]
            if covers(p, x, y) then
                return p.ink
            end
        end
        return zone_ink(x, y)
    end

    return {settings = settings, cell_at = cell_at, ore_at = ore_at}
end

return Public
