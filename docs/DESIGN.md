# Cyber Scroller — Design (v0.1, vertical slice)

## Pitch
You are a **fixer / netrunner** who never sets foot on the street. You hire a squad of
mercenaries ("runners"), load your cyberdeck with **soft** (programs), and send the squad
through a side-scrolling district. Runners walk and fight on their own. You support them
from the net: quickhacks, buffs, heals. Combat is real time with a long time-to-kill,
paced like an idle game. **Using soft triggers an active pause**: time freezes while you
pick a target, so every decision is deliberate, not a reflex.

Targets: **mobile (landscape, touch) and web**. 2D chunky pixel art, all procedural for
now (see "Art"), so we ship no third-party assets yet.

## Core loop
```
SAFEHOUSE (hub)                               MISSION (side-scroller)
  Contracts -> pick 1 of 3 ------------------>  squad auto-walks right
  Crew      -> hire / pick squad (max 3)        encounters spawn ahead -> auto-combat
  Deck      -> equip soft into slots            you cast soft (active pause + target)
  Market    -> buy soft, deck upgrades          between encounters: EXTRACT or push on
       ^                                        boss guards the objective at the end
       |------------- results: eddies, rep, XP, casualties, loot <--------'
```

### Push-your-luck
- Kills drop **eddies** (€$) collected during the mission ("bag").
- Between encounters (no enemies alive), you can **Extract**: keep the bag, forfeit the
  contract reward, and the squad survives.
- Clearing the boss = bag + contract reward + rep + a chance at a soft drop.
- **Squad wipe** = the bag is lost and every runner on the mission **flatlines** (permadeath).
- On success or extraction, downed runners pull through.

## Time and active pause
- The mission runs on its own simulation clock: `sim_dt = delta * speed`, where speed is
  0 when paused, otherwise 1x / 2x / 3x. UI animations use real time.
- Tapping a soft card that needs a target **pauses** the game (scanline overlay, cyan
  tint) and highlights valid targets. Tapping a target casts it. Tapping the card again
  or Cancel aborts. Afterwards the game resumes, unless manual pause was on.
- Untargeted soft casts at once and adds a short 0.25 s hit-stop for impact.
- **Manual pause** (button or Space) lets you queue several casts in one frozen moment.
- Keyboard (web): `1..6` soft slots, `Space` pause, `Esc` cancel, `F` cycle speed.

## Resources
- **RAM**: the fixer's mana. Base max 10, regen 0.7/s. Every active soft costs RAM.
- **Cooldown** per soft, in sim seconds.
- **Charges**: a few heavy programs also have charges per mission (DnD style, refilled
  at the safehouse).
- **Deck slots**: cyberdeck Mk1 = 4 active + 2 passive. Upgrades in the Market.

## Damage model
- `taken = dmg * 10 / (10 + armor)` (armor 6 means 62.5 % gets through).
- Soft damage (hacks) **ignores armor**, which makes hacks the answer to Heavies.
- Crit: x1.75. Miss: Optics Jam gives enemies a miss chance.
- Stun interrupts telegraphed casts (Netrunner hack, boss charge). **Interrupting is the
  main skill expression.**

## Runners (hirelings)
Level-1 stats; +12 % HP and damage per level. XP comes from missions (level cap 10).

| Class   | HP  | Armor | Dmg | Interval | Range | Innate skill (auto, CD) |
|---------|-----|-------|-----|----------|-------|-------------------------|
| Solo    | 240 | 6     | 14  | 1.2      | 28    | **Gorilla Slam** (9 s): 30 dmg AoE r48 + taunt enemies 4 s |
| Gunner  | 130 | 2     | 10  | 0.75     | 190   | **Burst Fire** (7 s): 4 rapid shots |
| Medtech | 120 | 1     | 5   | 1.0      | 160   | **Trauma Kit** (5 s): heal lowest-HP% ally 35 |
| Techie  | 140 | 3     | 7   | 0.9      | 170   | **Shock Grenade** (10 s): 25 dmg AoE r50 + stun 1 s. Passive: +20 % RAM regen |

Formation: Solo in front, others 22 px behind each other. Melee runners close in;
ranged ones hold position.

**Traits** (0–1 per hire, random): *Chromed* (+25 % HP, +15 % cost), *Trigger-happy*
(-20 % interval, -10 % dmg), *Cheap* (-30 % cost, -10 % HP), *Veteran* (starts at level 2),
*Lucky* (10 % crit), *Glass Jaw* (-20 % HP, +20 % dmg, -20 % cost).

**Hire cost** = `50 + 35 * level` × trait modifiers. The hire pool has 4 candidates;
rerolling costs 20 €$. The pool refreshes for free after each mission.

## Enemies
Base stats at threat 1; +20 % HP and damage per threat level above 1.

| Enemy     | HP   | Armor | Dmg | Int | Range | Speed | Bounty | Notes |
|-----------|------|-------|-----|-----|-------|-------|--------|-------|
| Ganger    | 140  | 0     | 9   | 1.1 | 24    | 32    | 6      | melee |
| Gunman    | 110  | 1     | 7   | 1.0 | 170   | 26    | 7      | ranged |
| Heavy     | 420  | 7     | 18  | 1.8 | 26    | 18    | 15     | melee, armored |
| Drone     | 70   | 0     | 4   | 0.6 | 150   | 44    | 5      | flies (drawn higher), ranged |
| Netrunner | 120  | 0     | 3   | 1.2 | 210   | 22    | 12     | every 8 s casts **Overheat** (1.5 s telegraph): 7 dps for 5 s on a random runner. Interruptible. |
| Cyberpsycho (boss) | 2200 | 4 | 24 | 1.4 | 30 | 22 | 120 | every 12 s **Berserk Charge** (2 s telegraph): 70 dmg to frontmost runner. Interruptible. At <50 % HP: enrage, +40 % attack speed |

Targeting: melee enemies hit the taunter if any, otherwise the frontmost runner. Ranged
enemies pick a random runner and keep the target for 3 s.

## Soft (programs)
Actives:

| id | Name | RAM | CD | Charges | Target | Effect |
|----|------|-----|----|---------|--------|--------|
| short_circuit | Short Circuit | 4 | 5 | – | enemy | 45 dmg, stun 1.5 s |
| nano_patch | Nano-Patch | 3 | 6 | – | ally | heal 70, then 5 HP/s for 4 s |
| overclock | Overclock | 3 | 10 | – | ally | +60 % attack speed for 8 s |
| weapon_glitch | Weapon Glitch | 3 | 8 | – | enemy | -60 % dmg for 8 s |
| contagion | Contagion | 5 | 12 | – | enemy | 8 dps for 6 s; also hits enemies within 70 px |
| firewall | Firewall | 6 | 18 | – | none | all runners: 50 shield for 10 s |
| synapse_burnout | Synapse Burnout | 7 | 14 | – | enemy | 80 dmg, x2 if target <40 % HP |
| optics_jam | Optics Jam | 4 | 14 | – | none | all enemies 50 % miss for 6 s |
| smart_link | Smart Link | 4 | 12 | – | ally | 100 % crit for 6 s |
| cyberpsychosis | Cyberpsychosis | 8 | 25 | – | enemy (non-boss) | target fights its allies for 8 s |
| system_collapse | System Collapse | 10 | 0 | 1 | enemy | kills a non-boss; 300 dmg to a boss |

Passives (daemons):

| id | Name | Effect |
|----|------|--------|
| ram_expansion | RAM Expansion | +3 max RAM |
| turbo_coprocessor | Turbo Coprocessor | +30 % RAM regen |
| targeting_uplink | Targeting Uplink | runners +15 % dmg |
| biomonitor | Biomonitor | runners regen 1.5 HP/s |
| data_siphon | Data Siphon | each kill restores 1 RAM |
| ice_sentry | ICE Sentry | every 4 s: 12 dmg to a random enemy (ignores armor) |
| bounty_scraper | Bounty Scraper | +25 % eddies from kills |
| kiroshi_link | Kiroshi Link | hacks deal +25 % dmg |
| autopilot | Autopilot Daemon | when RAM is full, auto-casts the first ready active soft on a sensible target (idle play) |

Starting kit: Short Circuit, Nano-Patch, Overclock, RAM Expansion. 300 €$. Two free
runners (Solo, Gunner).

## Contracts
- 3 offers, regenerated after each mission. Threat level 1..min(5, 1 + rep/4).
- Encounters = `3 + threat`, plus a boss at the end.
- Each encounter is 2–5 enemies drawn from a pool that widens with threat.
- Reward = `120 * threat` + random ±20 %. Rep on success = `threat`.
- Flavor: a client, a target corp or gang, a district (Kabuki, Watson Docks, Glen Spire, Neon Row).

## Market
- 4 random soft offers (not yet owned), refreshed after each mission. Price by rarity:
  common 150, uncommon 300, rare 550.
- Upgrades: +1 active slot (400, then 800), +1 passive slot (500, then 1000).

## Fixer skill tree (planned, next iteration)
A Nodebuster-style tree bought with rep or "data shards" dropped by bosses: RAM, regen,
cooldown reduction, hire discounts, bigger hire pool, a 4th squad slot, Autopilot
improvements, and offline income ("the fixer takes side gigs").

## Art direction
- Viewport 640x360, canvas_items stretch, nearest filter. Pixel sprites are 16x24 and
  drawn at x2.
- Night city: far skyline with lit windows, mid layer with neon signs, wet street with
  reflections, rain. Palette: deep navy and violet, neon cyan `#2de2e6`, magenta
  `#ff3d81`, yellow `#f9c80e`.
- All sprites come from ASCII templates in code (`PixelSprites`), palette-swapped per
  class and enemy. They can be replaced with CC0 packs later.

## Code layout
```
scripts/game.gd            autoload "Game": persistent state, save/load, contracts, economy
scripts/data/soft_db.gd    SoftDB: soft definitions
scripts/data/unit_db.gd    UnitDB: runner classes, enemies, traits, names
scripts/art/pixel_sprites.gd  PixelSprites: procedural pixel art textures (cached)
scripts/ui/ui_theme.gd     UITheme: shared neon Theme + color constants
scripts/main.gd            switches between hub and mission scenes
scenes/hub.tscn            safehouse UI (contracts, crew, deck, market, results)
scenes/mission.tscn        side-scrolling mission
```
