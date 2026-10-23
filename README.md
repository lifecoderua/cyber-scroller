# Cyber Scroller

Portrait cyberpunk roguelite with turn-based dice fights (Slice & Dice style). You are a fixer: take a job,
jack into a crew of three hired guns, and pick the route and the loot. Every merc rolls a gear die and a
chrome die built from their equipment; you lock, reroll and spend them against visible enemy intents, backed
by your cyberdeck's hacks and daemons. Godot 4.7, GL Compatibility, targets web and mobile (360x640 portrait).

- Design: [docs/DESIGN.md](docs/DESIGN.md), dice combat: [docs/DICE_DESIGN.md](docs/DICE_DESIGN.md)
- Platforms and export: [docs/PLATFORMS.md](docs/PLATFORMS.md)
- Asset shortlist (CC0, not yet used): [docs/ASSETS.md](docs/ASSETS.md)

## How a run plays
1. **JOBS:** pick a contract, then 1 of 3 random crews.
2. **Map:** tap a node to see its intel, then GO. Fights, caches, fence, ripperdoc, subnet, safehouse, events.
3. **Fights:** read the intents, lock and reroll dice, then tap a die and its target. Hacks cost RAM.
4. **Loot:** pick one card: gear (changes a merc's dice) or a hack / daemon. DECK opens the loadout.
5. Reach the target. Trace at 100% or a wiped crew ends the run.

## Controls (fight)
- Roll phase: tap dice to lock, REROLL, DONE ROLLING.
- Assign phase: tap a die, then an enemy or a crew card; tap an untargeted die (RAM, Dodge, Blast...) twice.
- Tap a hack, then its target. Tap an enemy for its intent. END TURN lets the enemies act; AUTO plays the turn.

## Dev tools (run from the project root)
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --script res://tools/sim_flow_check.gd   # whole run through the real scenes
$G --headless --path . --script res://tools/audio_flow_check.gd # audio hooks
$G --headless --path . --script res://tools/sim_dice.gd         # run balance harness (random / greedy / smart)
$G --path . --script res://tools/shot_hub.gd -- out.png 0       # hub screenshot (tab 0-2)
$G --path . --script res://tools/shot_run.gd -- prefix          # run screens
$G --path . --script res://tools/shot_mission.gd -- prefix 2    # dice fight screenshots
```
The `shot_*` tools reset `user://save.json`.
