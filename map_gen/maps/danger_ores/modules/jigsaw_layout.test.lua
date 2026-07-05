-- Standalone unit tests for the pure Jigsaw layout algorithm.
-- Run from the repo root:  lua map_gen/maps/danger_ores/modules/jigsaw_layout.test.lua
package.path = './?.lua;' .. package.path

local Layout = require 'map_gen.maps.danger_ores.modules.jigsaw_layout'

local failures = 0
local function check(cond, msg)
    if cond then
        print('ok:   ' .. msg)
    else
        failures = failures + 1
        print('FAIL: ' .. msg)
    end
end

-- orientations: a square (O) collapses to 1; a chiral L expands to 8.
local o_square = Layout.orientations({ {0, 0}, {1, 0}, {0, 1}, {1, 1} })
check(#o_square == 1, 'square (O) has 1 unique orientation, got ' .. #o_square)

local l_shape = Layout.orientations({ {0, 0}, {0, 1}, {0, 2}, {1, 2} })
check(#l_shape == 8, 'L has 8 unique orientations, got ' .. #l_shape)

-- Build the flat oriented palette used by packing/generate.
local palette = require 'map_gen.maps.danger_ores.config.jigsaw_shapes'
local function oriented_palette()
    local oriented = {}
    for _, s in ipairs(palette) do
        for _, v in ipairs(Layout.orientations(s)) do
            oriented[#oriented + 1] = v
        end
    end
    return oriented
end
local function rand(n) return math.random(n) end

-- pack: fully covers the torus (no empty cells) and is deterministic per seed.
math.randomseed(1)
local oriented = oriented_palette()
local PSIZE = 12
local grid = Layout.pack(PSIZE, oriented, rand)
local empty = 0
for x = 0, PSIZE - 1 do
    for y = 0, PSIZE - 1 do
        if grid[x][y] == 0 then empty = empty + 1 end
    end
end
check(empty == 0, 'pack leaves no empty cells, empty=' .. empty)

math.randomseed(99)
local g1 = Layout.pack(PSIZE, oriented, rand)
math.randomseed(99)
local g2 = Layout.pack(PSIZE, oriented, rand)
local identical = true
for x = 0, PSIZE - 1 do
    for y = 0, PSIZE - 1 do
        if g1[x][y] ~= g2[x][y] then identical = false end
    end
end
check(identical, 'pack is deterministic for a fixed random sequence')

if failures == 0 then
    print('\nALL PASSED')
else
    print('\n' .. failures .. ' FAILURE(S)')
    os.exit(1)
end
