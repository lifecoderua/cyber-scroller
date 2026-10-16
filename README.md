# Cyber Scroller

Cyberpunk side-scroller with indirect control. You are a fixer: hire runners, build a
deck of soft, and send the squad on contracts. They fight on their own; you hack from the
net with an active pause. Godot 4.7, GL Compatibility, targets web and mobile.

- Design: [docs/DESIGN.md](docs/DESIGN.md)
- Platforms and export: [docs/PLATFORMS.md](docs/PLATFORMS.md)
- Asset shortlist (CC0, not yet used): [docs/ASSETS.md](docs/ASSETS.md)

## Controls
- Tap a soft card: the game pauses for targeting, then tap a unit or squad chip.
- `1..9` soft slots, `Space` pause, `Esc` cancel, `F` speed (1x/2x/3x).
- Extract between fights to keep the bag; a wipe flatlines the squad.

## Dev tools (run from the project root)
```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --script res://tools/sim_flow_check.gd   # hub -> mission -> hub e2e
$G --headless --path . --script res://tools/audio_flow_check.gd # audio hooks
$G --headless --path . --script res://tools/sim_mission.gd      # balance harness
$G --path . --script res://tools/shot_hub.gd -- out.png 0       # hub screenshot (tab 0-4)
$G --path . --script res://tools/shot_mission.gd -- prefix 1    # mission screenshots
```
`shot_hub.gd` resets `user://save.json`.
