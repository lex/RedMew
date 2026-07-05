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
    return grid, id
end

return M
