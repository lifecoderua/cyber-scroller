# Cyber Scroller — Design (v0.3, portrait roguelite with dice combat)

Source idea and UI sketches: `_project_spaces/ideas__games/cyberpunk-fixer-sidescroller.md` and
`cyberpunk-fixer-ui-sketches.md` (design draft v1). This document describes what the game implements.

## Pitch
You are a **fixer / netrunner** who never sets foot on the street. For each job you jack into a crew of 3
hired guns. Fights are turn-based, Slice & Dice style: every merc rolls a **gear die** and a **chrome die**
built from their equipment, enemies show their **intents** up front, and you lock, reroll and assign dice,
backed by the fixer's **hacks** (spend RAM) and **daemons** (passive). Between fights you decide who gets which
chrome, how the deck is loaded and which node to take next. Portrait, one-handed, web and mobile.

## Design pillars
1. **The crew is the gun, you are the brain.** Gear builds the dice; the fixer bends dice and intents.
2. **Chrome is an interface.** Implants add faces and ports daemons hook, and make mercs targets for enemy
   netrunners. Over the chrome cap, faces turn into Glitch.
3. **Rules over numbers.** Faces, hacks and daemons are verbs; plain +pips are the filler.
4. **Everything visible.** Intents and targets are shown before you act; no clock.

## Run structure
```
SAFEHOUSE (hub)                RUN (one contract)
  JOBS  -> pick 1 of 3  ---->  crew draft: 1 of 3 random crews (+ optional stash item)
  NET   -> skill tree          district map: 8 rows, 2-3 branches, target on top
  STASH -> extracted gear      node -> fight / loot / shop / rest / event -> map ...
     ^                         target down = job done: shards, rep, extract 1 item to stash
     '------------ debrief ----'  (wipe or Trace 100% = run over, a few shards)
```
- **Crew draft:** three offers of 3 mercs each, shown with both dice. Mercs may come with an implant. One
  stash item may ride along (lost if the run fails).
- **Map:** row 0 is a fight, row 3 has an elite, row 6 is rest (safehouse / ripperdoc / fence), row 7 is the
  target. Tapping a node shows intel (enemy roles per wave, loot theme, Trace cost) before you commit.
- **Lose conditions:** the whole crew down in a fight, or **Trace reaches 100%**. Trace is the fixer's HP.
- **Merc down:** at 0 HP a merc is down for the fight; afterwards they get up with a **scar** (-1 max HP for
  the run). Survivors patch up 20% HP after each fight.
- **Rep perk:** after 3 fights survived, a merc picks 1 of 2 archetype perks.

### Node types
| Node | What happens |
|---|---|
| Fight | 2 waves, then a loot pick |
| Elite | 3 waves, one affixed elite per wave (Chromed / Shielded / Overclocked), +1 loot option |
| Cache | Loot pick only, themed by location (street / clinic / armory / server room) |
| Fence | Buy chips and gear for €$ |
| Ripperdoc | Treat scars, upgrade gear one tier, pull implants (+€$ scrap) |
| Subnet | Take 1 of 3 chips, **or** scrub 18 Trace |
| Safehouse | Heal the whole crew, **or** recompile one hack / daemon to tier II |
| Event | Text choice with risk and reward (7 events) |
| Target | Two guard waves, then the Cyberpsycho boss |

### Fixer resources
- **RAM** (fight): 2 at the start, +2 per turn, cap 6; RAM faces add more. Hacks spend it.
- **Rerolls** (fight): 2 per turn.
- **Heat** (fight): +1 per hack (Overclock +2), cools 2 per turn. At the cap (6) the deck overheats: no hacks
  next turn and +6 Trace.
- **Trace** (whole run): +4 per fight (elite +6, target +5), +6 per landed netrunner upload, +10 per Hijack,
  +6 per overheat, events. At **50%** corp security adds a gunman to every wave; at 100% the run is burned.
  Lowered at subnets and by the INTEL branch.
- **Eddies (€$)** (whole run): kill bounties, scrap from skipped loot and replaced gear. Spent at the Fence
  and the Ripperdoc.

## Combat
Turn-based dice on a flat battlefield. Full rules, faces, enemy dice, hacks, daemons and balance are in
[DICE_DESIGN.md](DICE_DESIGN.md). In short:
1. Enemies roll intents (what and whom; shown with a line to the target).
2. Mercs roll a gear die and a chrome die each. Lock and reroll (2 rerolls), then DONE ROLLING.
3. Use dice in any order: tap a die, then its target. Melee faces only reach front enemies; backline and
   flying enemies need shots, pierce, marks, stuns or blasts.
4. Hacks any time (RAM, Heat). Daemons trigger by themselves.
5. END TURN: unused Glitch faces fire, intents resolve, burns and turrets tick. AUTO plays the turn with the
   smart bot.

## Loot and gear
After each fight: pick **1 of N** (3; +1 elite, +1 per Scavenger, +1 Scavenger Net). Unpicked options turn
into scrap €$; SKIP ALL pays a little more.
- **Sources:** SALVAGE (gear), SHARD (hacks and daemons; more after killing netrunners, drones, turrets),
  LOCATION (by node theme). If most kills were burn ticks, one salvage card is fried scrap.
- **Gear changes dice:** weapons and armor rewrite the gear die, implants fill chrome-die sockets. Every
  merc button shows the fit and the dice change (e.g. `SHT2>PRC3`).

## UI (portrait 360x640, one-handed)
- Fight: top bar (Trace, RAM, Heat, wave, turn, €$) / battlefield with intent badges and lines / crew cards
  with incoming damage (LETHAL warnings) / two dice under each card / hack buttons / daemons / AUTO, REROLL,
  DONE ROLLING or END TURN. Tap an enemy for its intent and role.
- Run: header (contract, €$, Trace, node) / current screen / footer (CREW, DECK, menu).
- Deck: hack slots and daemon slots with descriptions, spare-chip drawer with kind filters.
- Crew sheet: both dice face by face, trait, perk, gear, chrome bar, port daemons.
- Hub: JOBS / NET / STASH tabs at the bottom.

## Meta progression
- **Data Shards:** won run = fights won - 1 + 3 + (threat - 1) (+ Boss Dossier), failed run =
  max(1, fights / 2) (+ Insurance); x (1 + Data Miner / Oracle Feed).
- **Rep:** + threat on a won run; max contract threat = 1 + rep / 4 (+ Rep Broker), up to 5.
- **Stash:** 4 slots (+ Stash Locker); extract 1 item per won run (2 with Fixer Empire).
- **Skill tree (NET tab):** 33 nodes in four branches (dice versions of the nodes: see DICE_DESIGN.md).

## Code layout
```
scripts/game.gd               autoload "Game": meta (shards, rep, tree, stash), contracts, save, screens
scripts/run/run_state.gd      RunState: draft, map, fights, loot, node actions, perks (plain data + rules)
scripts/run/run_screen.gd     run scene: header / footer, draft, map, previews, perk picks
scripts/run/*_view.gd         map, loot, node screens, deck loadout, crew sheet, run over
scripts/fight/dice_combat.gd  DiceCombat: turn-based dice fight (pure logic)
scripts/fight/dice_bot.gd     DiceBot: random / greedy / smart policies (harness, AUTO button)
scripts/fight/fight_scene.gd  fight scene: battlefield, intents, crew cards, dice tray, hacks
scripts/data/                 DiceDB (faces, merc dice), UnitDB (mercs, enemy intent dice), ItemDB,
                              ChipDB (hacks, daemons), EventDB, TreeDB
scripts/hub/                  safehouse: JOBS, NET (skill tree graph), STASH, debrief
scripts/ui/                   theme, ScreenBase (toasts / modals), ChipTile, DieView, MeterBar
```
Save version 3 (`user://save.json`): meta plus the active run, saved after every step. Runs saved before the
dice combat load with the starter hacks and daemons.
