-- The groups of buttons in the top bar, left to right, each in a panel of its own like the game's
-- shortcut bar, and the buttons in each group in order. A feature puts its button in a group by
-- passing its id to Gui.add_top_element. Buttons without an id (the info button, the cutscene
-- controls while a cutscene plays) and other mods' buttons stay in the first panel, mod-gui's
-- own, after the button that collapses the bar.
return {
    -- people
    { 'player_list', 'tag_group', 'poll', 'tasklist' },
    -- your tools
    { 'redmew_settings', 'autofill', 'paint', 'shortcuts', 'production_hud' },
    -- game status
    { 'evolution_progress', 'experience', 'score' },
    -- game modes' own buttons
    { 'snake', 'tetris' },
    -- admins only
    { 'admin_panel' },
}
