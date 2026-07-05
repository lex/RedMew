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

if failures == 0 then
    print('\nALL PASSED')
else
    print('\n' .. failures .. ' FAILURE(S)')
    os.exit(1)
end
