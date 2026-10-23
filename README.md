# Cyber Scroller

Portrait cyberpunk roguelite with indirect control. You are a fixer: take a job, jack into a crew of hired
guns, wire your cyberdeck, and pick the route and the loot. The crew fights on its own; you program the deck
and fire manual threads. Godot 4.7, GL Compatibility, targets web and mobile (360x640 portrait).

- Design: [docs/DESIGN.md](docs/DESIGN.md)
- Platforms and export: [docs/PLATFORMS.md](docs/PLATFORMS.md)
- Asset shortlist (CC0, not yet used): [docs/ASSETS.md](docs/ASSETS.md)

## How a run plays
1. **JOBS:** pick a contract, then 1 of 3 random crews.
2. **Map:** tap a node to see its intel, then GO. Fights, caches, fence, ripperdoc, subnet, safehouse, events.
3. **Fights:** threads run on their own. EXEC fires MANUAL threads: tap EXEC, then a target (or AUTO).
4. **Loot:** pick one card: gear for a merc or a chip for the deck. DECK opens the editor.
5. Reach the target. Trace at 100% or a wiped crew ends the run.

## Controls (fight)
- Tap EXEC on a manual thread, then a unit or crew card; double-tap EXEC = auto target.
- Tap a unit for intel (pauses).
- `1..9` EXEC thread, `A` auto target, `Space` pause, `Esc` cancel, `F` speed (1x/2x/3x).

## Dev tools (run from the project root)
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --script res://tools/sim_flow_check.gd   # whole run through the real scenes
$G --headless --path . --script res://tools/audio_flow_check.gd # audio hooks
$G --headless --path . --script res://tools/sim_mission.gd      # run balance harness (idle vs bot)
$G --path . --script res://tools/shot_hub.gd -- out.png 0       # hub screenshot (tab 0-2)
$G --path . --script res://tools/shot_run.gd -- prefix          # run screens
$G --path . --script res://tools/shot_mission.gd -- prefix 2    # fight screenshots
```
The `shot_*` tools reset `user://save.json`.
