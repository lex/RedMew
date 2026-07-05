-- Polyomino palette for the Danger Ores "Jigsaw" map.
-- Each shape is a list of {dx, dy} chunk offsets. Rotations and reflections are
-- generated in code (see jigsaw_layout.orientations), so mirror pieces (J, Z) are
-- NOT listed here to avoid double-weighting.
return {
    { {0, 0}, {1, 0}, {2, 0}, {3, 0} }, -- I
    { {0, 0}, {1, 0}, {0, 1}, {1, 1} }, -- O
    { {0, 0}, {1, 0}, {2, 0}, {1, 1} }, -- T
    { {1, 0}, {2, 0}, {0, 1}, {1, 1} }, -- S (reflection yields Z)
    { {0, 0}, {0, 1}, {0, 2}, {1, 2} }, -- L (reflection yields J)
    { {0, 0} },                          -- monomino (guaranteed filler)
}
