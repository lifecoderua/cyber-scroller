# Dice combat (Slice & Dice style) — design

Replaces the real-time side-scroller fight. The run layer (contract, crew draft, district map, loot, nodes,
stash, skill tree) stays. Numbers below are the shipped values; the balance table at the end comes from
`tools/sim_dice.gd`.

## Goals
- No clock, no movement: a flat battlefield and a turn loop where every decision is visible and deliberate.
- The crew is the gun: each merc brings **two dice** built from their gear and chrome.
- The fixer is the brain: rerolls, RAM, **hacks** that bend dice and enemy intents, passive **daemons**.
- Enemies telegraph by design: every enemy shows its **intent** (what and whom) before you act.

## Turn
1. **Intents.** Every enemy rolls its die. The face becomes its intent, with the target chosen now
   (melee: the front merc or a taunter; shots: a random merc; rushers: the back merc). Shown above the enemy
   with a line to its target.
2. **Roll.** Every living merc rolls both dice. **ROLL phase:** tap dice to lock them, REROLL rerolls the
   unlocked ones (2 rerolls per turn). DONE ends the phase (also automatic when rerolls run out).
3. **Assign** (any order): tap a die, then its target. Untargeted faces (RAM, Dodge, Blast...) apply on the
   second tap. Each die is used once. Dice can be left unused.
4. **Hacks** (any time in 2-3): spend RAM on fixer programs.
5. **END TURN:** unused Glitch faces fire at random targets, then the remaining enemy intents resolve
   left to right, then burns tick, turrets fire, shields expire, Heat cools.
6. A wave is cleared when every enemy is down; the next wave walks in for the next turn. The fight is won
   when the last wave is cleared, lost when every merc is down, or when Trace hits 100.

## Dice
A face is `{k: keyword, v: pips}` (plus optional `burn`). Dice have 6 faces.

| Keyword | Tag | Target | Effect |
|---|---|---|---|
| attack | ATK | enemy, melee reach | v damage |
| cleave | CLV | enemy, melee reach | v damage to the target and its neighbours |
| shot | SHT | any enemy | v damage; a Shieldbearer's front shield blocks it |
| pierce | PRC | any enemy | v damage, ignores shields and armor |
| slice | SLC | none | v damage to the 3 front enemies (past shields) |
| blast | BLS | none | v damage to every enemy |
| rage | RGE | enemy, melee reach | v damage, the merc takes 1 |
| shield | SHD | ally | v shield until the end of the enemy phase |
| heal | HEL | ally | heal v (not above max) |
| triage | TRI | none | heal every merc v |
| taunt | TNT | self | v shield, every single-target intent turns to this merc |
| dodge | DDG | self | the next hit on this merc this turn is ignored |
| mark | MRK | any enemy | the enemy takes +v from every hit this turn |
| stun | STN | any enemy | cancel its intent |
| ram | RAM | none | +v RAM |
| focus | FOC | none | the next die you use gets +v |
| turret | TUR | none | a turret shoots the front enemy for v at end of turn, 2 turns |
| glitch | GLT | none | v damage to a random unit, mercs included; fires by itself if unused |
| blank | — | — | nothing |

**Melee reach:** melee faces hit only front enemies (not backline, not flying) while any front enemy stands.
Backline enemies (sniper, netrunner) and drones need shots, pierce, mark, stun, blast or slice.

### Gear die = weapon + armor (reliable)
Base faces by archetype weapon; items modify them:

| Class | HP | Gear die (base weapon) |
|---|---|---|
| Solo (front) | 9 | ATK3 ATK3 ATK4 ATK2 SHD2 — |
| Borg (front) | 12 | CLV2 CLV3 ATK4 SHD3 SHD3 — |
| Medtech (mid) | 7 | SHT2 SHT2 HEL3 HEL3 SHD2 — |
| Techie (back) | 7 | SHT2 SHT3 RAM1 RAM1 SHD2 — |
| Sniper (back) | 6 | PRC4 PRC3 SHT3 SHT2 — — |

### Chrome die = signature + implants (spiky)
Signature faces plus empty **sockets** (blank faces) that implants fill:

| Class | Chrome die | Sockets |
|---|---|---|
| Solo | SLC2 SLC3 DDG + 3 sockets | 2 (third socket stays blank) |
| Borg | TNT3 TNT3 SHD4 + 3 sockets | 3 |
| Medtech | HEL4 HEL5 TRI1 + 3 sockets | 2 |
| Techie | TUR2 RAM2 STN + 3 sockets | 2 |
| Sniper | MRK2 MRK2 PRC5 + 3 sockets | 1 |

**Chrome cap:** implants cost chrome. Every chrome point over the cap turns one signature face into
**GLT 3** (it can hit your own crew and fires by itself if unused). Loyal mercs never glitch.

### Items as face changes
| Item | Effect on dice |
|---|---|
| Mono-wire | gear ATK faces become CLV (same pips); kills refund 1 RAM |
| Smart Rifle | gear SHT faces become PRC +1 |
| Riot Shotgun | gear ATK faces become CLV +1 |
| Rail Pistol | +1 on every gear damage face |
| Thermal Katana | gear damage faces add burn 1 (1 dmg at end of turn for 2 turns) |
| Kevlar Vest | +3 max HP; gear blank -> SHD2 |
| Riot Plating | gear SHD faces +2 |
| Ablative Coat | 2 shield at the start of every turn |
| Nanoweave | heal 1 at the start of every turn |
| Kerenzikov (2 chr, port Dodge) | socket -> DDG |
| Gorilla Arms (2 chr, port Knockback) | socket -> ATK5 |
| Projectile Launcher (3 chr, port Blast) | socket -> BLS2 |
| Subdermal Armor (1 chr) | socket -> SHD3, +1 max HP |
| Pain Editor (2 chr) | socket -> SHD5 |
| Synaptic Booster (2 chr) | socket -> ATK4 |
| Biomonitor (1 chr) | socket -> HEL4 |
| Kiroshi Optics (1 chr) | socket -> MRK2 |
| Neural Link (2 chr) | socket -> FOC2 |
| Adrenal Pump (2 chr) | socket -> RGE6 |
| Relay Booster (1 chr) | socket -> RAM2 |

Tier II (Ripperdoc upgrade): +1 pip on every face the item adds or changes (+2 HP for Kevlar).

Traits: Chromehead (+1 socket, +1 chrome), Analog (-1 socket, +3 HP, immune to uploads), Glass Jaw
(+1 on damage faces, -2 HP), Show-off (+1 on signature faces), Scavenger (+1 loot), Loyal (no glitch),
Old Wound (a scar, +1 on gear damage faces). A scar is -1 max HP.

Rep perks (after 3 fights): Solo Blade Dance (SLC +1) / Adrenaline (gear ATK +1); Borg Iron Wall (TNT +2) /
Heavy Hitter (CLV +1); Medtech Field Surgeon (HEL +2) / Triage (a blank -> TRI2); Techie Heavy Turret
(TUR +1) / Relay (+1 RAM per turn); Sniper Deadeye (MRK +1) / Hollow Points (PRC +1).

## Enemies
Enemy dice are intents. Threat scaling (UnitDB.THREAT_HP / THREAT_DMG, RunState.ELITE_CHANCE):
HP x (1 + 0.05 x (threat - 1)); every intent gets +0 / +1 / +2 / +3 / +3 pips at threat 1-5; waves have
2 + row / 3 + threat / 2 enemies (2-4); each regular wave has a (threat - 1) x 30% chance of an affixed enemy.

| Role | HP | Die (intents) | Rule / question |
|---|---|---|---|
| Ganger | 4 | ATK2 ATK2 ATK3 ATK1 ATK2 — | swarm |
| Rusher | 3 | RUSH3 RUSH3 RUSH2 RUSH4 ATK2 — | rush hits the back merc |
| Gunman | 4 | SHT2 SHT2 SHT3 SHT1 SHT2 — | random merc |
| Drone | 3 | SHT1 SHT2 SHT1 SHT2 SHT1 — | flying (no melee), machine |
| Shieldbearer | 7 | ATK2 ATK3 GUARD3 ATK2 GUARD2 ATK1 | front shield blocks SHT; GUARD shields an ally |
| Sniper | 4 | AIM (always) | backline; AIM then next turn SNIPE 6 at the same merc unless stunned |
| Grenadier | 4 | BLAST2 BLAST2 SHT2 BLAST3 SHT1 — | blast hits the target and its neighbours |
| Netrunner | 4 | UPL2 UPL2 UPL3 SHT1 UPL2 — | backline; upload: damage + 6 Trace, blocked by Firewall / Analog |
| Turret | 7 | SHT3 SHT3 SHT2 SHT4 SHT3 — | static, machine |
| Heavy | 10 | ATK4 ATK4 ATK3 ATK5 ATK3 — | armor 1 (each hit -1 unless pierce / breach) |
| Cyberpsycho (boss) | 30 | ATK4 CHARGE7 RAMPAGE2 ATK5 CHARGE7 SUMMON | armor 1; enrages at half HP (+1 all); summon adds a ganger |

Elite affixes: Chromed (+50% HP), Shielded (4 shield every turn), Overclocked (+1 on every intent).

## Fixer
- **RAM:** starts at 2 (full with Warm Boot), +2 per turn, cap 6 (+ RAM Buffer). RAM faces add more.
- **Rerolls:** 2 per turn (+1 Steady Hands, +1 Packet Sniffer daemon).
- **Heat:** +1 per hack (Overclock +2). Cools 2 per turn. At the cap (6) the deck **overheats**: no hacks
  next turn and +6 Trace.
- **Trace:** +4 per fight (elite +6, target +5), +6 per landed upload, +10 per Hijack, +6 per overheat.
  At 50 a gunman joins every wave; at 100 the run is burned.

### Hacks (active, slotted; 4 slots)
| Hack | RAM | Effect |
|---|---|---|
| Short Circuit | 3 | cancel an enemy's intent (also breaks an Aim) |
| Spoof | 3 | the enemy's intent hits another enemy instead |
| Overclock | 1 | +2 on a rolled die (+2 Heat) |
| Echo | 3 | a used die can be used again |
| Breach | 2 | the enemy loses shield and armor and takes +1 from every hit this turn |
| Ping | 2 | 2 damage to any enemy |
| Patch | 2 | heal a merc 3 |
| Firewall | 2 | 3 shield on a merc, blocks uploads |
| Hijack | 4 | a machine's intent turns on its own side; +10 Trace |
| Bandwidth | 1 | +1 reroll |

### Daemons (passive, 3 slots) — what threads became
| Daemon | Trigger -> effect |
|---|---|
| Data Siphon | on kill: +1 RAM |
| Wave Primer | wave start: +2 RAM |
| Guardian | a merc drops under 40%: 2 shield (once per merc per fight) |
| Static Discharge | a shield face is used: +1 RAM |
| Packet Sniffer | +1 reroll per turn |
| ICE Sentry | end of turn: 1 damage to a random enemy |
| Cooling Loop | Heat cools +1 per turn |
| Dodge Relay (port) | a merc dodges: +1 RAM |
| Shrapnel Link (port) | a blast face is used: +1 damage to the front enemy |
| Recoil Loop (port) | an ATK5 knockback face is used: stun the target |

Port daemons are **dark** while no living merc has the implant. Tier II (recompile): hacks cost -1 RAM
(min 1) or gain +1 effect; daemons +1.

Starting deck: hacks Short Circuit, Overclock, Patch; daemon Data Siphon; spare Breach, Firewall.

## Run layer changes
- Crews are always 3 mercs (the 2-merc offer is gone; 3 offers).
- Fights: 2 waves (elites and the target 3), 2-4 enemies per wave, max 5 on screen.
- Merc HP is stored as a fraction of max, as before; patch-up 20% after a fight; downed mercs get a scar.
- Loot fit preview shows the die change (e.g. "gear: SHT2 -> PRC3").
- Deck editor: hack slots and daemon slots instead of threads.
- Skill tree keeps its shape; nodes now speak dice. Small numbers make +HP / +damage very strong, so
  those nodes are short and expensive:

| Node | Effect |
|---|---|
| RAM Buffer (5) | +1 RAM cap per rank |
| Overclocked Bus (3) | +1 RAM at fight start per rank |
| ICEbreaker (2) | +1 on Ping, Patch, Firewall, Breach per rank |
| Warm Boot | fights start with full RAM |
| Heat Sink (3) | +1 Heat cap per rank |
| Wide Bus | +1 hack slot |
| Cheap Cycles | every hack -1 RAM (min 1) |
| Neural Overflow | +2 RAM cap, kills give 1 RAM |
| Smart Ammo (1, 20 shards) | +1 on gear damage faces |
| Subdermal Mesh (3) | +1 merc max HP per rank |
| Steady Hands | +1 reroll per turn |
| Plated Chrome (2) | the front merc starts each turn with +1 shield per rank |
| Reflex Mesh | a blank gear face becomes Shield 1 |
| Trauma Team | once per fight, the first merc down comes back at 30% |
| Recon Drones | enemies spawn with 1 less HP |

## Balance (tools/sim_dice.gd, 80 runs per cell, no skill tree)
Policies: **random** (no rerolls, no hacks, random targets), **greedy** (rerolls blanks, hits the weakest,
shields the weakest, no hacks), **smart** (rerolls weak faces, hacks the scariest intents, threat-aware
scoring of every die / target pair).

| Threat | random | greedy | smart | smart, turns per fight | smart, mid tree (60 runs) |
|---|---|---|---|---|---|
| 1 | 8% | 67% | 97% | 4.1 | 100% |
| 2 | 0% | 22% | 93% | 5.2 | 98% |
| 3 | 0% | 3% | 68% | 6.5 | 96% |
| 4 | 0% | 0% | 42% | 6.2 | 71% |
| 5 | 0% | 0% | 38% | 6.4 | 68% |

Smart play averages 6-12 hacks and 10-24 cancelled intents per run; Trace ends around 30-40%.
"Mid tree" is about 30 runs of shards (RAM Buffer 3, Overclocked Bus 2, ICEbreaker 1, Heat Sink 1,
Subdermal Mesh 2, Plated Chrome 1, Ripperdoc on Call 2, Trace Scrubber 3, Data Miner 2, Seed Money 2).
