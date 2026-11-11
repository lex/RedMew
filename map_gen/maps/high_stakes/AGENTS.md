# High Stakes: notes for agents

Read [README.md](README.md) first: what the mode is and how it fits together. This adds how the
code behaves and what is easy to break.

## How the code behaves

- **A card is a number from 1 to 52**, `(rank - 2) * 4 + suit`, aces high (14) and low in a
  straight. `Cards.evaluate` reads the best hand in up to five cards and which cards make it;
  `Cards.score` orders hands for the round's winner.
- **A tower's entity only shows where it is**: the turret is `disabled_by_script`, indestructible
  and not minable, and `towers.lua` picks targets (the biter in its plot furthest along) and
  deals the damage. Which turret a hand looks like and what it does is `Settings.towers`, and a
  high card's suit changes how it attacks (`Settings.suits`).
- **A biter's health is the script's**, `Settings.biter_health(wave)`; the entity's health bar
  shows the share left. A biter dies through `Waves.damage` and `entity.die`, whose death event
  pays the bounty.
- **Biters walk in hops of 3 tiles** (`go_to_location`, `distraction.none`). Asked to walk further
  across open ground, the game's pathfinder plans coarsely and cuts across the felt.
- **A played hand gives the player the turret's item** and waits in `state.pending`; building it
  on their own felt makes it the tower. What isn't placed by the end of the hand is placed for
  them, where it sees the most path (`Layout.best_spots`).
- **Biters and players are at cease fire**, and towers are indestructible: only chips are at stake.

## Rules that are easy to break

- **Balance numbers come from games played out with the real code**, not from a model: a Python
  model of this game said players would be out by the tenth wave when, played out, no biter got
  through. Play all the rounds on a headless server with a stand-in player and change the numbers
  from what that shows; `settings.lua` says what the current curve was tuned against.
- **The hand's card buttons each sit in a flow of their own**: siblings can't share a GUI name.
- **A new game keeps the table** (`state.table_ready`): resetting it would place the vaults again.

## Tests

`cards_tests.lua` covers reading hands, ordering them, decks and rigged hands. `scenario_tests.lua`
needs no player: a seated player is stood in for by their seat data (a player index no real
player has). It checks the paths and vaults, that a biter keeps to the path and steals chips at
the vault, that a tower kills and pays, and that a tower nobody placed goes on the felt. How to
write and run tests is in `docs/TESTS.md`.
