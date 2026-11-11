# Convergence: notes for agents

Read [README.md](README.md) first: what the mode is and how it fits together. This adds how the
code behaves and what is easy to break.

## How the code behaves

- **A tower's entity only shows where it is.** Turrets are `disabled_by_script`, indestructible
  and not minable; `towers.lua` picks targets (the creep in range furthest along its path) and
  deals the damage. Beacons are entities too, and land mines are the traps: a disabled mine never
  goes off.
- **A creep's health is the script's**, `Settings.biter_health(wave)`, far more than the game's
  biters have; the entity's health bar shows the share left. A creep dies through
  `Creeps.damage`, which records who gets the bounty, and `entity.die` raises the death event that
  pays it.
- **Ground biters walk in hops of 3 tiles** (`go_to_location`, `distraction.none`). Asked to walk
  further across open ground, the game's pathfinder plans coarsely and cuts across the felt.
- **Air waves are combat robots** (defender, distractor, destroyer) on the enemy force, which the
  script teleports along the lane every tick (`Creeps.fly`), with a long `time_to_live`.
- **Biters and players are at cease fire**, so biters never attack players, and towers are
  indestructible: only the core's lives are at stake.
- **Players buy a tower in the panel and get its item**; building it registers the tower if the
  player has one of that line waiting (`state.pending`) and it stands where `Layout.can_build`
  allows. Anything else built is destroyed. Players pick a tower to upgrade or sell by pointing at
  it, or by clicking it (its own window is closed).
- **The waves come one after another**: the next after a break once a wave is cleared, or at once
  if someone calls it. Only seats whose player is online get biters.

## Rules that are easy to break

- **Balance numbers come from games played out with the real code**, not from a model. A model of
  this game (and of High Stakes) was badly off; play every wave on a headless server with a
  stand-in player and change the numbers from what that shows. `settings.lua` says what the
  current curve was tuned against.
- **Each line's shop button has its own GUI name**: siblings can't share one.
- **A new game keeps the map** (`state.map_ready`): resetting it would place a second core.

## Tests

`scenario_tests.lua`, loaded only with the game mode, needs no player: a player is stood in for
by their game data (a player index no real player has), and towers are created by script. It
checks the lanes are path from spawn to core and merge as they should, that a biter keeps to the
path and a robot flies its lane to the core, that towers kill and pay, that flak only hits the
air, that traps don't touch shielded waves, beacons, and the gold of upgrading and selling. How to
write and run tests is in `docs/TESTS.md`.
