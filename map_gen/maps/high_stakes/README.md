# High Stakes

A tower defence played with cards. Every round each seated player gets five cards, swaps up to
four of them once, and plays their best poker hand: it becomes a tower in their own plot. Then a
wave of biters walks every plot's path to its vault; each one killed pays chips, each one that
gets there steals some, and a player with no chips left is out. The best hand of each round wins
chips, tipping the dealer makes the next hand more likely to be good, and three folds a game skip
a hand and its wave. After thirty waves the richest player wins, and a new game starts.

Its rules come from a Warcraft III custom map (poker hands as towers, tipping, folding, the
richest wins); the name, layout and art are its own. The suits are Factorio's signals: crosshair,
lightning, fire and explosion, each a high card's way of attacking.

## How it fits together

- `scenario.lua` sets the table up (no autoplace, the vaults, cease fire between biters and
  players), wires the events, and holds the info window's text and changelog.
- `layout.lua` is the map: eight plots round a hall, each with a path that weaves back through
  itself, the shape function, and where towers may go.
- `settings.lua` holds the numbers: chips, rounds, the waves and the towers each hand makes.
- `cards.lua` is the cards: decks, reading poker hands, and the dealer's rigged hands for tips.
- `state.lua` is the saved state; `waves.lua` walks the biters and keeps their health;
  `towers.lua` makes, aims and fires the towers; `game.lua` runs the seats, chips and rounds;
  `gui.lua` is the panel with the hand and the standings.

## Adding a map

High Stakes is one map, selected by `scenario_templates/high-stakes/map_selection.lua`. It has no
next-map poll. Its changelog is the `ScenarioInfo.set_new_info` text in `scenario.lua`: a dated
entry, newest at the top, for changes players will notice.

Notes for working on the code, the rules that are easy to break and how the tests work are in
[AGENTS.md](AGENTS.md).
