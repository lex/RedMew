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

return M
