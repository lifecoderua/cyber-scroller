# Cyber Scroller — Design (v0.2, portrait roguelite slice)

Source idea and UI sketches: `_project_spaces/ideas__games/cyberpunk-fixer-sidescroller.md` and
`cyberpunk-fixer-ui-sketches.md` (design draft v1). This document describes what the game implements.

## Pitch
You are a **fixer / netrunner** who never sets foot on the street. For each job you jack into a crew of 2-3
hired guns and support them through a **programmable cyberdeck** and **loot decisions**. The mercs move and
fight on their own; you decide who gets which chrome, how the deck is wired, which node to take next, and
when to spend a manual EXEC. Portrait, one-handed, web and mobile.

## Design pillars
1. **You are the brain, not the gun.** All influence goes through the deck and the loot picks.
2. **Chrome is an interface.** Implants open ports your deck can hook, and make mercs targets for enemy
   netrunners. Over the chrome cap, mercs risk cyberpsychosis.
3. **Rules over numbers.** Chips and implants add events, rules and verbs; stat sticks are the filler.
4. **Readable auto-combat.** Enemies telegraph. Programs answer telegraphs automatically; EXEC covers the rest.

## Run structure
```
SAFEHOUSE (hub)                RUN (one contract)
  JOBS  -> pick 1 of 3  ---->  crew draft: 1 of 3 random crews (+ optional stash item)
  NET   -> skill tree          district map: 8 rows, 2-3 branches, target on top
  STASH -> extracted gear      node -> fight / loot / shop / rest / event -> map ...
     ^                         target down = job done: shards, rep, extract 1 item to stash
     '------------ debrief ----'  (wipe or Trace 100% = run over, a few shards)
```
- **Crew draft:** three offers; one of them is a 2-merc crew that comes with +50 €$. Mercs may come with an
  implant. One stash item may ride along (lost if the run fails).
- **Map:** row 0 is a fight, row 3 has an elite, row 6 is rest (safehouse / ripperdoc / fence), row 7 is the
  target. Tapping a node shows intel (enemy roles per wave, loot theme, Trace cost) before you commit.
- **Lose conditions:** the whole crew down in a fight, or **Trace reaches 100%**. Trace is the fixer's HP.
- **Merc down:** at 0 HP a merc is down for the fight; afterwards they get up with a **scar** (-10% max HP for
  the run). Survivors patch up 20% HP after each fight.
- **Rep perk:** after 3 fights survived, a merc picks 1 of 2 archetype perks.

### Node types
| Node | What happens |
|---|---|
| Fight | 2-3 waves (more deeper in), then a loot pick |
| Elite | 3 waves, one affixed elite per wave (Chromed / Shielded / Overclocked), +1 loot option |
| Cache | Loot pick only, themed by location (street / clinic / armory / server room) |
| Fence | Buy chips and gear for €$; hire a 3rd merc if the crew is short |
| Ripperdoc | Treat scars, upgrade gear one tier, pull implants (+€$ scrap) |
| Subnet | Take 1 of 3 chips, **or** scrub 18 Trace |
| Safehouse | Heal the whole crew, **or** recompile one chip to tier II |
| Event | Text choice with risk and reward (7 events) |
| Target | Two guard waves, then the Cyberpsycho boss |

### Fixer resources
- **RAM** (combat): regenerates; a thread's run costs the sum of its chips' RAM.
- **Heat** (combat): +1 per payload (+ modifiers), decays over time. At the cap the deck **freezes** for 3 s
  and Trace rises by 6. Caps combo spam.
- **Trace** (whole run): +4 per fight (elite +6, target +5), +8 per enemy netrunner hack that lands, +12 per
  Hijack, +6 per overheat, events. At **50%** corp security adds a gunman to every wave; at 100% the run is
  burned. Lowered at subnets, by Stealth, and by the INTEL branch.
- **Eddies (€$)** (whole run): kill bounties, scrap from skipped loot and replaced gear. Spent at the Fence
  and the Ripperdoc.

## Combat
- **Side-view strip** on top of the screen: the crew on the left in formation (front / mid / back rows),
  waves arrive from the right. Max ~4 enemies per wave; offscreen enemies get an arrow at the right edge.
- Mercs auto-move and auto-attack; their **signature** fires on its own cooldown.
- Damage: `taken = dmg * 10 / (10 + armor)`; hacks ignore armor. Breach strips armor and shields.
- Speed 1x/2x/3x, manual pause. EXEC targeting runs at 25% speed (slow-mo, not a full pause).

### Mercs (5 archetypes)
| Class | Row | Weapon | Signature | Sockets / chrome |
|---|---|---|---|---|
| Solo | front | blades (melee) | **Sandevistan**: dash through the line, 2x hits on 3 enemies (past shields) | 2 / 5 |
| Borg | front | shotgun (cleave 1) | **Bulwark**: taunt nearby enemies, -50% damage taken for 4s | 3 / 7 |
| Medtech | mid | SMG | **Stim**: heal the weakest ally 40 + haste 3s | 2 / 5 |
| Techie | back | pistol | **Deploy**: a turret for 12s (an ally the deck can buff). +15% RAM regen | 2 / 5 |
| Sniper | back | rifle (pierces shields) | **Mark**: next shot crits x2.5; target takes +30% from hacks | 1 / 4 |

Traits (random): Chromehead, Analog (immune to enemy quickhacks), Glass Jaw, Show-off, Scavenger (+1 loot
option), Loyal (never psycho), Old Wound.

**Cyberpsychosis:** chrome load above capacity builds stress when the merc is hit. At max stress the merc
goes psycho for 5 s: double damage, faster attacks, hits the nearest unit on either side, ignores the deck.

### Enemy roles (each asks a different question)
| Role | Behaviour | Answers |
|---|---|---|
| Ganger | cheap melee swarm | AoE: Chain, Fork, Contagion |
| Rusher | sprints past the front line to the back row | Bulwark taunt, Sonic knockback, focus fire |
| Gunman | ranged, random targets | — |
| Drone | flying, hijackable | Machine selector + Hijack |
| Shieldbearer | frontal shield blocks 75% of gunfire | Breach, hacks, Sniper pierce, Sandevistan |
| Sniper | 3 s aim (laser line), 70 dmg shot | Short Circuit / Sonic interrupt, Firewall the target |
| Grenadier | 1.6 s lob at clustered mercs | Interrupt, kill first |
| Netrunner | quickhacks the most chromed merc: burn + Trace | Interrupt, Firewall blocks it, Analog mercs |
| Turret | static, hits hard, hijackable | Hijack (Trace) or burst |
| Heavy | armored melee | Breach, hacks |
| Cyberpsycho (boss) | Berserk Charge (2 s telegraph) on the front merc; enrages at 50% | Interrupts, tanking |

## Cyberdeck
Chassis **Street Mk.I**: 3 threads x 4 slots, 12 RAM (+1.1/s), Heat cap 8. A thread is
`[Trigger] [chip] [chip] [chip]`, executed left to right when the trigger fires and the thread is off
cooldown:
- **Selectors (green)** set the target. If one finds nothing before any payload fired, the run aborts for
  free and the thread waits (gambit-style conditions: `[Timer][Telegraphing][Short Circuit]`).
- **Modifiers (blue)** stack onto the **next** payload.
- **Payloads (red)** fire and consume the modifiers. RAM is charged when the first payload fires.
- A payload with no fitting selector uses its default: the event's enemy or the front enemy for attacks,
  the event's merc or the weakest ally for buffs.
- **Cost** = chip RAM sum; **cycle** = chassis latency + chip latency (Timer: at least its interval);
  **Heat** = +1 per payload + modifiers.

| Kind | Chips |
|---|---|
| Trigger (yellow) | Timer, Manual (EXEC), On Kill, Ally Hit, Ally Low, Telegraph, Wave Start, Signature, Overheat; **port triggers** On Dodge / On Knockback / On Blast (need a merc with the implant, else the thread is **dark**) |
| Selector (green) | Front Enemy, Weakest, Telegraphing, Backline, Machine, Self-merc, Lowest Ally |
| Modifier (blue) | Amplify, Fork, Chain, Echo, Compress, Stealth, Overclock, Persist |
| Payload (red) | Ping, Short Circuit, Overheat (burn), Breach, Sonic Shock, Contagion, Hijack, Patch, Firewall, Overdrive |

Chips have a tier II (Safehouse recompile, some events): payloads x1.4, triggers cycle faster, modifiers
stronger. The starter deck teaches the three trigger families:
`T1 [Timer][Front][Ping]`, `T2 [Ally Low][Self][Patch]`, `T3 [Manual][Telegraphing][Short Circuit]`.

**Manual threads:** tap EXEC -> slow-mo, valid targets pulse -> tap a target (it replaces the first
selector), or AUTO / double-tap EXEC to use the thread's own selector.

**Visibility:** chip tiles light up as they run; every payload draws a line from its tile to the unit it hit;
an interrupt draws a thick line from the thread to the telegraph it answered.

## Loot and gear
After each fight: pick **1 of N** (3; +1 elite, +1 per Scavenger, +1 Scavenger Net). Unpicked options turn
into scrap €$; SKIP ALL pays a little more.
- **Sources:** SALVAGE (gear from what you fought), SHARD (chips; more after killing netrunners, drones,
  turrets), LOCATION (by node theme).
- **Kill method:** if most kills were burn ticks, one salvage card is fried scrap instead of gear.
- **Crew and deck compete for the same pick.** Items show a fit preview per merc (free slot, replaces X,
  OVER CAP, choose implant to replace).
- **Slots:** weapon, armor, implants (sockets by archetype). 19 items; implants cost chrome; three implants
  carry port events (Kerenzikov: On Dodge, Gorilla Arms: On Knockback, Projectile Launcher: On Blast).

## UI (portrait 360x640, one-handed)
- Interactive elements live in the bottom ~60%: crew cards, thread rows with EXEC, prompts, footers.
- Fight: top bar (Trace, RAM, Heat, speed, pause, wave pips) / battle strip / crew cards / 3 thread rows /
  hint or targeting prompt. Tap a unit for an intel sheet (pauses).
- Run: header (contract, €$, Trace, node) / current screen / footer (CREW, DECK, menu).
- Deck editor: thread board with a live **dry-run readout** and warnings, spare-chip drawer with kind
  filters. Tap a chip, then a slot.
- Hub: JOBS / NET / STASH tabs at the bottom.

## Meta progression
- **Data Shards:** won run = fights won - 1 + 3 + (threat - 1) (+ Boss Dossier), failed run =
  max(1, fights / 2) (+ Insurance); x (1 + Data Miner / Oracle Feed).
- **Rep:** + threat on a won run; max contract threat = 1 + rep / 4 (+ Rep Broker), up to 5.
- **Stash:** 4 slots (+ Stash Locker); extract 1 item per won run (2 with Fixer Empire).
- **Skill tree (NET tab):** 33 nodes in four branches.

| Branch | Nodes |
|---|---|
| NETRUNNING (cyan) | RAM Buffer, Overclocked Bus (RAM regen), ICEbreaker (payload power), Warm Boot (full RAM at fight start), Heat Sink, Wide Bus (+1 slot per thread), Cooling Loop (Heat decay), **Neural Overflow** |
| STREET CRED (magenta) | Smart Ammo, Subdermal Mesh, Combat Stims, Plated Chrome, Ripperdoc on Call (patch-up), Kerenzikov Lite (haste), Trauma Team (once per fight revive), **Pick of the Litter** (+1 crew offer, all crews of 3) |
| STREET BIZ (yellow) | Bounty Board, Seed Money (start €$), Fence Contacts (prices), Salvager (skip value), Scavenger Net (+1 loot option), Insurance Policy (failed-run shards), Stash Locker, **Fixer Empire** |
| INTEL (green) | Trace Scrubber, Data Miner, Subnet Mastery, Wider Network (4th contract), Recon Drones (enemy HP), Rep Broker, Boss Dossier, **Oracle Feed** (reveals the map, -Trace gain) |

## Balance snapshot (tools/sim_mission.gd, 24 runs per cell, no skill tree)
| Threat | idle (never EXECs) | bot (EXECs on its own selector) |
|---|---|---|
| 1 | 79% | 87% |
| 2 | 37% | 79% |
| 3 | 8% | 50% |
| 4-5 | 0% | 4-12% |

With a mid skill tree (~30 runs of shards) the bot wins 66-87% at threat 3-5. Fights last 40-60 s.

## Out of scope for this slice (from the design draft)
Daemons, zero-days, enemy ICE / junk-chip injection, the Bus chip, Ghost / Reboot / Purge payloads, extra
mission types (hold, escort), Nomad / Face / Street runner archetypes, a district per faction.

## Code layout
```
scripts/game.gd               autoload "Game": meta (shards, rep, tree, stash), contracts, save, screens
scripts/run/run_state.gd      RunState: draft, map, fights, loot, node actions, perks (plain data + rules)
scripts/run/run_screen.gd     run scene: header / footer, draft, map, previews, perk picks
scripts/run/*_view.gd         map, loot, node screens, deck editor, crew sheet, run over
scripts/mission/combat_sim.gd CombatSim: 1D fight simulation (mercs, enemy roles, telegraphs, waves)
scripts/mission/deck_engine.gd DeckEngine: threads, RAM, Heat, payloads, manual EXEC
scripts/mission/mission.gd    fight scene: battle strip + HUD (crew cards, thread rows, EXEC)
scripts/data/                 ChipDB, UnitDB (mercs, enemies, traits, perks), ItemDB, EventDB, TreeDB
scripts/hub/                  safehouse: JOBS, NET (skill tree graph), STASH, debrief
scripts/ui/                   theme, ScreenBase (toasts / modals), ChipTile, MeterBar
```
Save version 3 (`user://save.json`): meta plus the active run, saved after every step. Version 1-2 saves keep
shards, rep and the skill tree.
