-- Pure-Lua layout generator for the Danger Ores "Jigsaw" map.
-- ZERO Factorio dependencies: unit-testable with a standalone Lua interpreter.
-- All randomness is injected via `random(n) -> integer in [1, n]`, so the caller
-- owns the seed (the Factorio builder passes the map-seeded generator; tests pass
-- math.random).
local sort = table.sort
local concat = table.concat

local M = {}

-- Normalize a shape (list of {dx,dy}) so its min dx/dy are 0; return a sorted copy
-- plus a string key for de-duplication.
local function normalize(cells)
    local min_x, min_y = math.huge, math.huge
    for _, c in ipairs(cells) do
        if c[1] < min_x then min_x = c[1] end
        if c[2] < min_y then min_y = c[2] end
    end
    local out = {}
    for i, c in ipairs(cells) do
        out[i] = { c[1] - min_x, c[2] - min_y }
    end
    sort(out, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    local parts = {}
    for i, c in ipairs(out) do parts[i] = c[1] .. ',' .. c[2] end
    return out, concat(parts, ';')
end

-- All unique orientations (4 rotations x reflection) of a shape.
function M.orientations(shape)
    local variants = {}
    local seen = {}
    local cur = shape
    for _ = 1, 4 do
        local rotated = {}      -- rotate 90deg: (x,y) -> (y, -x)
        for i, c in ipairs(cur) do rotated[i] = { c[2], -c[1] } end
        local reflected = {}    -- reflect the rotated variant: (x,y) -> (-x, y)
        for i, c in ipairs(rotated) do reflected[i] = { -c[1], c[2] } end
        for _, variant in ipairs({ rotated, reflected }) do
            local norm, key = normalize(variant)
            if not seen[key] then
                seen[key] = true
                variants[#variants + 1] = norm
            end
        end
        cur = rotated
    end
    return variants
end

-- Does `cells` placed at (ox,oy) fit on the torus (all target cells empty)?
local function fits(grid, size, cells, ox, oy)
    for _, c in ipairs(cells) do
        local x = (ox + c[1]) % size
        local y = (oy + c[2]) % size
        if grid[x][y] ~= 0 then return false end
    end
    return true
end

local function stamp(grid, size, cells, ox, oy, id)
    for _, c in ipairs(cells) do
        local x = (ox + c[1]) % size
        local y = (oy + c[2]) % size
        grid[x][y] = id
    end
end

-- Pack a size x size torus with pieces from `oriented`.
-- Returns grid[x][y] = piece id (1..count) and the piece count.
function M.pack(size, oriented, random)
    local TRIES = 6 -- random placement attempts per empty cell before the monomino fallback
    local grid = {}
    for x = 0, size - 1 do
        grid[x] = {}
        for y = 0, size - 1 do grid[x][y] = 0 end
    end
    local id = 0
    local filled = true
    while filled do
        filled = false
        for x = 0, size - 1 do
            for y = 0, size - 1 do
                if grid[x][y] == 0 then
                    filled = true
                    id = id + 1
                    local placed = false
                    for _ = 1, TRIES do
                        local cells = oriented[random(#oriented)]
                        if fits(grid, size, cells, x, y) then
                            stamp(grid, size, cells, x, y, id)
                            placed = true
                            break
                        end
                    end
                    if not placed then
                        grid[x][y] = id -- current cell is empty, so a single cell always fits
                    end
                end
            end
        end
    end

    -- Dissolve stray single-chunk pieces (monominoes): merge each into an orthogonally
    -- adjacent piece so no lone 1x1 squares remain. A monomino's four neighbours all
    -- belong to other pieces, so a merge target always exists. Deterministic (no random);
    -- re-coloring later keeps borders clean.
    local size_of = {}
    for pid = 1, id do size_of[pid] = 0 end
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            size_of[grid[x][y]] = size_of[grid[x][y]] + 1
        end
    end
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            local pid = grid[x][y]
            if size_of[pid] == 1 then
                local neigh = {
                    grid[(x + 1) % size][y], grid[(x - 1) % size][y],
                    grid[x][(y + 1) % size], grid[x][(y - 1) % size],
                }
                for _, other in ipairs(neigh) do
                    if other ~= pid then
                        grid[x][y] = other
                        size_of[other] = size_of[other] + 1
                        size_of[pid] = 0
                        break
                    end
                end
            end
        end
    end

    -- Renumber surviving piece ids to a contiguous 1..count range.
    local remap = {}
    local count = 0
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            local pid = grid[x][y]
            local new = remap[pid]
            if not new then
                count = count + 1
                new = count
                remap[pid] = new
            end
            grid[x][y] = new
        end
    end
    return grid, count
end

-- neighbors[id] = { other_id = true, ... } over the torus (4-adjacency).
function M.adjacency(grid, size)
    local neighbors = {}
    local function link(a, b)
        if a == b then return end
        neighbors[a] = neighbors[a] or {}
        neighbors[b] = neighbors[b] or {}
        neighbors[a][b] = true
        neighbors[b][a] = true
    end
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            local id = grid[x][y]
            link(id, grid[(x + 1) % size][y])
            link(id, grid[x][(y + 1) % size])
        end
    end
    return neighbors
end

-- Complete graph coloring via dynamic DSATUR (incremental saturation) + backtracking.
-- Returns colors[id] = 1..num_colors (no two adjacent pieces equal) or nil if impossible.
-- Colors are tried in a per-seed fixed random preference order: a STATIC order keeps the
-- backtracking near-linear (a dynamic least-used order caused pathological search), while
-- randomizing it once per seed varies which ore ends up dominant. Vertex selection is a
-- deterministic DSATUR (max saturation, tie-break by degree then lowest id).
function M.color(count, neighbors, num_colors, random)
    local adj = {}
    local deg = {}
    for id = 1, count do
        local a = {}
        local nb = neighbors[id]
        if nb then
            for o in pairs(nb) do a[#a + 1] = o end
        end
        adj[id] = a
        deg[id] = #a
    end

    -- per-seed fixed color preference (a static random permutation of 1..num_colors)
    local pref = {}
    for c = 1, num_colors do pref[c] = c end
    for i = num_colors, 2, -1 do
        local j = random(i)
        pref[i], pref[j] = pref[j], pref[i]
    end

    local colors = {}   -- id -> color, or nil
    local sat = {}      -- id -> number of distinct colors among its coloured neighbours
    local ncolor = {}   -- id -> { [c] = number of neighbours currently coloured c }
    for id = 1, count do
        sat[id] = 0
        local t = {}
        for c = 1, num_colors do t[c] = 0 end
        ncolor[id] = t
    end

    local uncolored = count
    -- Backtracking node ceiling. With the static DSATUR order the solve is near-linear
    -- (< ~1000 nodes for a ~400-piece size-32 super-tile), so this is a generous safety
    -- net; it fails closed to nil, letting generate() re-pack rather than freezing.
    local SAFETY = 200000
    local nodes = 0

    local function assign(id, c)
        colors[id] = c
        uncolored = uncolored - 1
        for _, o in ipairs(adj[id]) do
            if colors[o] == nil then
                local nc = ncolor[o]
                if nc[c] == 0 then sat[o] = sat[o] + 1 end
                nc[c] = nc[c] + 1
            end
        end
    end

    local function unassign(id, c)
        for _, o in ipairs(adj[id]) do
            if colors[o] == nil then
                local nc = ncolor[o]
                nc[c] = nc[c] - 1
                if nc[c] == 0 then sat[o] = sat[o] - 1 end
            end
        end
        colors[id] = nil
        uncolored = uncolored + 1
    end

    local function pick()
        local best, best_sat, best_deg = nil, -1, -1
        for id = 1, count do
            if colors[id] == nil then
                local s = sat[id]
                local d = deg[id]
                if s > best_sat or (s == best_sat and d > best_deg) then
                    best, best_sat, best_deg = id, s, d
                end
            end
        end
        return best
    end

    local function solve()
        if uncolored == 0 then return true end
        nodes = nodes + 1
        if nodes > SAFETY then return false end
        local id = pick()
        local nc = ncolor[id]
        for _, c in ipairs(pref) do
            if nc[c] == 0 then
                assign(id, c)
                if solve() then return true end
                unassign(id, c)
            end
        end
        return false
    end

    if solve() then return colors end
    return nil
end

-- Pack + color, retrying with fresh randomness until a clean coloring exists.
function M.generate(opts)
    local size = opts.size
    local num_ores = opts.num_ores
    local random = opts.random
    local max_attempts = opts.max_attempts or 8

    local oriented = {}
    for _, shape in ipairs(opts.palette) do
        for _, variant in ipairs(M.orientations(shape)) do
            oriented[#oriented + 1] = variant
        end
    end

    for _ = 1, max_attempts do
        local grid, count = M.pack(size, oriented, random)
        local neighbors = M.adjacency(grid, size)
        local colors = M.color(count, neighbors, num_ores, random)
        if colors then
            local ore_grid = {}
            for x = 0, size - 1 do
                ore_grid[x] = {}
                for y = 0, size - 1 do
                    ore_grid[x][y] = colors[grid[x][y]]
                end
            end
            return ore_grid
        end
    end
    error('jigsaw_layout: could not ' .. num_ores .. '-color the packing after '
        .. max_attempts .. ' attempts')
end

return M
