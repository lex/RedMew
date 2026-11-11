# Convergence

A co-op tower defence. Each seated player's lane starts at the top of the map, and the eight
lanes merge like a tournament bracket on their way down to the core (a rocket silo): two into one
in the pair zones, two into one again in the half zones, and the last two in the final zone.
Biters come down every lane in sixty waves. The team buys, places, upgrades and sells towers to
stop them; each biter that reaches the core costs a life (a boss costs five). Clear every wave to
win; lose every life and the core falls. Either way a new game starts a minute later.

Its rules come from a Warcraft III custom map (shared lives, merging lanes, upgradable tower lines,
air, spell-immune and boss waves); the name, layout, towers and art are its own.

## How it fits together

- `scenario.lua` sets the map up (no autoplace, the core, cease fire between biters and players),
  wires the events, and holds the info window's text and changelog.
- `layout.lua` is the map: the lanes' corners, the zones (each seat's own zone at the top, shared
  below), the shape function the map is generated from, and where towers and traps may go.
- `settings.lua` holds the numbers: lives, gold, the waves and the seven tower lines with their
  levels.
- `state.lua` is the saved state: phase, wave, lives, players, creeps, towers.
- `creeps.lua` walks the waves' biters and flies their robots along the lanes, and keeps their
  health.
- `towers.lua` registers towers, aims and fires them, works out beacon auras, upgrades and sells.
- `game.lua` runs the game: seats, gold, buying and building, the waves and their breaks, winning,
  losing and new games.
- `gui.lua` is the panel: the wave and lives, gold, the shop, the picked tower, the team.

## Adding a map

Convergence is one map, selected by `scenario_templates/convergence/map_selection.lua`. It has no
next-map poll. Its changelog is the `ScenarioInfo.set_new_info` text in `scenario.lua`: a dated
entry, newest at the top, for changes players will notice.

Notes for working on the code, the rules that are easy to break and how the tests work are in
[AGENTS.md](AGENTS.md).
