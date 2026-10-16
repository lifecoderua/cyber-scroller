class_name UnitDB
extends RefCounted
## Runner classes, enemy archetypes, traits and name generation. See docs/DESIGN.md.

const LEVEL_SCALE := 0.12  # +12% HP / dmg per runner level above 1
const THREAT_SCALE := 0.20  # +20% enemy HP / dmg per threat level above 1
const MAX_LEVEL := 10

const CLASSES := {
	"solo": {
		"name": "Solo", "hp": 240.0, "armor": 6.0, "dmg": 14.0, "interval": 1.2, "range": 28.0,
		"melee": true, "skill": "gorilla_slam", "skill_cd": 9.0,
		"skill_name": "Gorilla Slam", "skill_desc": "30 dmg around + taunt 4s",
		"color": Color("ff3d81"),
	},
	"gunner": {
		"name": "Gunner", "hp": 130.0, "armor": 2.0, "dmg": 10.0, "interval": 0.75, "range": 190.0,
		"melee": false, "skill": "burst_fire", "skill_cd": 7.0,
		"skill_name": "Burst Fire", "skill_desc": "4 rapid shots",
		"color": Color("f9c80e"),
	},
	"medtech": {
		"name": "Medtech", "hp": 120.0, "armor": 1.0, "dmg": 5.0, "interval": 1.0, "range": 160.0,
		"melee": false, "skill": "trauma_kit", "skill_cd": 5.0,
		"skill_name": "Trauma Kit", "skill_desc": "Heal weakest ally 35",
		"color": Color("4cff8f"),
	},
	"techie": {
		"name": "Techie", "hp": 140.0, "armor": 3.0, "dmg": 7.0, "interval": 0.9, "range": 170.0,
		"melee": false, "skill": "shock_grenade", "skill_cd": 10.0,
		"skill_name": "Shock Grenade", "skill_desc": "25 AoE dmg + stun 1s. +20% RAM regen",
		"color": Color("2de2e6"), "ram_regen_pct": 0.2,
	},
}

const ENEMIES := {
	"ganger": {
		"name": "Ganger", "hp": 140.0, "armor": 0.0, "dmg": 9.0, "interval": 1.1, "range": 24.0,
		"speed": 32.0, "bounty": 6, "melee": true, "min_threat": 1,
	},
	"gunman": {
		"name": "Gunman", "hp": 110.0, "armor": 1.0, "dmg": 7.0, "interval": 1.0, "range": 170.0,
		"speed": 26.0, "bounty": 7, "melee": false, "min_threat": 1,
	},
	"drone": {
		"name": "Drone", "hp": 70.0, "armor": 0.0, "dmg": 4.0, "interval": 0.6, "range": 150.0,
		"speed": 44.0, "bounty": 5, "melee": false, "flying": true, "min_threat": 2,
	},
	"heavy": {
		"name": "Heavy", "hp": 420.0, "armor": 7.0, "dmg": 18.0, "interval": 1.8, "range": 26.0,
		"speed": 18.0, "bounty": 15, "melee": true, "min_threat": 2,
	},
	"netrunner": {
		"name": "Netrunner", "hp": 120.0, "armor": 0.0, "dmg": 3.0, "interval": 1.2, "range": 210.0,
		"speed": 22.0, "bounty": 12, "melee": false, "min_threat": 3,
		"cast": "overheat", "cast_cd": 8.0, "cast_time": 1.5, "cast_dot": 7.0, "cast_duration": 5.0,
	},
	"cyberpsycho": {
		"name": "Cyberpsycho", "hp": 2200.0, "armor": 4.0, "dmg": 24.0, "interval": 1.4, "range": 30.0,
		"speed": 22.0, "bounty": 120, "melee": true, "boss": true, "min_threat": 99,
		"cast": "berserk_charge", "cast_cd": 12.0, "cast_time": 2.0, "cast_damage": 70.0,
		"enrage_pct": 0.5, "enrage_haste": 0.4,
	},
}

const TRAITS := {
	"chromed": {"name": "Chromed", "desc": "+25% HP, +15% cost", "hp": 0.25, "cost": 0.15},
	"trigger_happy": {"name": "Trigger-happy", "desc": "-20% interval, -10% dmg", "interval": -0.2, "dmg": -0.1},
	"cheap": {"name": "Cheap", "desc": "-30% cost, -10% HP", "hp": -0.1, "cost": -0.3},
	"veteran": {"name": "Veteran", "desc": "Starts at level 2", "level": 1},
	"lucky": {"name": "Lucky", "desc": "10% crit chance", "crit": 0.1},
	"glass_jaw": {"name": "Glass Jaw", "desc": "-20% HP, +20% dmg, -20% cost", "hp": -0.2, "dmg": 0.2, "cost": -0.2},
}

const FIRST_NAMES := [
	"Jax", "Vex", "Rook", "Nyx", "Kade", "Mira", "Tank", "Zero", "Saki", "Dex", "Ivy", "Brick",
	"Echo", "Rune", "Kai", "Lux", "Moxie", "Rex", "Tess", "Juno", "Hex", "Oni", "Pike", "Wren",
]
const HANDLES := [
	"Razor", "Chrome", "Static", "Ghost", "Byte", "Neon", "Torque", "Volt", "Glitch", "Scrap",
	"Ronin", "Spike", "Patch", "Sable", "Cipher", "Flux", "Rust", "Viper", "Kilo", "Halo",
]


## Builds a new runner record (plain Dictionary, JSON-serializable).
static func make_runner(cls: String, rng: RandomNumberGenerator, with_trait := true) -> Dictionary:
	var r := {
		"id": "%d_%d" % [Time.get_ticks_usec(), rng.randi()],
		"cls": cls,
		"name": "%s \"%s\"" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], HANDLES[rng.randi() % HANDLES.size()]],
		"level": 1,
		"xp": 0,
		"trait": "",
		"seed": rng.randi() % 1000,  # visual variation
	}
	if with_trait and rng.randf() < 0.6:
		var keys := TRAITS.keys()
		r.trait = keys[rng.randi() % keys.size()]
		r.level += int(TRAITS[r.trait].get("level", 0))
	return r


static func random_class(rng: RandomNumberGenerator) -> String:
	var keys := CLASSES.keys()
	return keys[rng.randi() % keys.size()]


## Effective combat stats for a runner record. `bonus` carries fixer skill tree bonuses
## (Game.fixer_stats(): runner_hp_pct, runner_armor, runner_crit, runner_haste).
## Squad-wide damage % is applied by the mission (fixer dmg_pct), not here.
static func runner_stats(r: Dictionary, bonus := {}) -> Dictionary:
	var c: Dictionary = CLASSES[r.cls]
	var t: Dictionary = TRAITS.get(r.get("trait", ""), {})
	var lvl_mul := 1.0 + LEVEL_SCALE * (int(r.level) - 1)
	return {
		"hp": round(c.hp * lvl_mul * (1.0 + t.get("hp", 0.0) + float(bonus.get("runner_hp_pct", 0.0)))),
		"armor": c.armor + float(bonus.get("runner_armor", 0.0)),
		"dmg": c.dmg * lvl_mul * (1.0 + t.get("dmg", 0.0)),
		"interval": c.interval * (1.0 + t.get("interval", 0.0)) / (1.0 + float(bonus.get("runner_haste", 0.0))),
		"range": c.range,
		"melee": c.melee,
		"crit": t.get("crit", 0.0) + float(bonus.get("runner_crit", 0.0)),
		"skill": c.skill,
		"skill_cd": c.skill_cd,
		"ram_regen_pct": c.get("ram_regen_pct", 0.0),
	}


static func hire_cost(r: Dictionary) -> int:
	var t: Dictionary = TRAITS.get(r.get("trait", ""), {})
	return int(round((50 + 35 * int(r.level)) * (1.0 + t.get("cost", 0.0))))


static func xp_to_next(level: int) -> int:
	return 60 * level


## Effective enemy stats at a threat level.
static func enemy_stats(kind: String, threat: int) -> Dictionary:
	var e: Dictionary = ENEMIES[kind].duplicate()
	var mul := 1.0 + THREAT_SCALE * (threat - 1)
	e.hp = round(e.hp * mul)
	e.dmg = e.dmg * mul
	if e.has("cast_damage"):
		e.cast_damage = e.cast_damage * mul
	if e.has("cast_dot"):
		e.cast_dot = e.cast_dot * mul
	return e


## Enemy kinds that can appear in regular encounters at this threat.
static func enemy_pool(threat: int) -> Array:
	var out := []
	for k in ENEMIES:
		if not ENEMIES[k].get("boss", false) and ENEMIES[k].min_threat <= threat:
			out.append(k)
	return out
