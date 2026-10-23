class_name UnitDB
extends RefCounted
## Merc archetypes, enemy roles, traits, perks and name generation. See docs/DESIGN.md.

const THREAT_SCALE := 0.15  # +15% enemy HP / dmg per threat level above 1
const SCAR_HP := 0.1        # each scar: -10% max HP for the rest of the run
const PERK_FIGHTS := 3      # fights survived before a merc earns a Rep perk
const STRESS_MAX := 100.0

## row: 0 front, 1 mid, 2 back (formation order).
const CLASSES := {
	"solo": {
		"name": "Solo", "row": 0, "hp": 210.0, "armor": 4.0, "dmg": 12.0, "interval": 0.85, "range": 30.0,
		"melee": true, "sockets": 2, "chrome": 5, "weapon": "Dual blades",
		"skill": "sandevistan", "skill_cd": 10.0, "skill_name": "Sandevistan",
		"skill_desc": "Dash through the line: 3 fast hits on 3 enemies", "color": Color("ff3d81"),
	},
	"borg": {
		"name": "Borg", "row": 0, "hp": 300.0, "armor": 7.0, "dmg": 15.0, "interval": 1.35, "range": 44.0,
		"melee": true, "sockets": 3, "chrome": 7, "weapon": "Shotgun", "cleave": 1,
		"skill": "bulwark", "skill_cd": 11.0, "skill_name": "Bulwark",
		"skill_desc": "Taunt nearby enemies, -50% damage taken for 4s", "color": Color("ff9f1c"),
	},
	"medtech": {
		"name": "Medtech", "row": 1, "hp": 140.0, "armor": 2.0, "dmg": 6.0, "interval": 0.7, "range": 150.0,
		"melee": false, "sockets": 2, "chrome": 5, "weapon": "SMG",
		"skill": "stim", "skill_cd": 7.0, "skill_name": "Stim",
		"skill_desc": "Heal the weakest ally 40 and speed them up 3s", "color": Color("4cff8f"),
	},
	"techie": {
		"name": "Techie", "row": 2, "hp": 130.0, "armor": 2.0, "dmg": 7.0, "interval": 0.85, "range": 170.0,
		"melee": false, "sockets": 2, "chrome": 5, "weapon": "Pistol", "ram_regen_pct": 0.15,
		"skill": "deploy", "skill_cd": 14.0, "skill_name": "Deploy",
		"skill_desc": "Drop a turret for 12s (a chrome ally your deck can target). +15% RAM regen",
		"color": Color("2de2e6"),
	},
	"sniper": {
		"name": "Sniper", "row": 2, "hp": 120.0, "armor": 1.0, "dmg": 30.0, "interval": 2.1, "range": 290.0,
		"melee": false, "sockets": 1, "chrome": 4, "weapon": "Rifle", "pierce": true,
		"skill": "mark", "skill_cd": 9.0, "skill_name": "Mark",
		"skill_desc": "Next shot crits x2.5; the target takes +30% from hacks for 6s",
		"color": Color("f9c80e"),
	},
}

const TURRET := {"name": "Turret", "hp": 90.0, "armor": 3.0, "dmg": 6.0, "interval": 0.6, "range": 190.0, "life": 12.0}

## Enemy roles. Each one asks the player a different question (see DESIGN.md).
const ENEMIES := {
	"ganger": {"name": "Ganger", "role": "Swarm", "hp": 150.0, "armor": 0.0, "dmg": 8.0, "interval": 1.1,
		"range": 24.0, "speed": 34.0, "bounty": 4, "melee": true, "min_threat": 1,
		"hint": "Cheap melee. Comes in numbers."},
	"rusher": {"name": "Rusher", "role": "Rusher", "hp": 110.0, "armor": 0.0, "dmg": 11.0, "interval": 0.9,
		"range": 22.0, "speed": 72.0, "bounty": 5, "melee": true, "rusher": true, "min_threat": 1,
		"hint": "Sprints past the front line to the back row."},
	"gunman": {"name": "Gunman", "role": "Shooter", "hp": 120.0, "armor": 1.0, "dmg": 6.0, "interval": 1.0,
		"range": 170.0, "speed": 26.0, "bounty": 5, "melee": false, "min_threat": 1,
		"hint": "Ranged, picks random targets."},
	"drone": {"name": "Drone", "role": "Drone", "hp": 70.0, "armor": 0.0, "dmg": 4.0, "interval": 0.6,
		"range": 150.0, "speed": 46.0, "bounty": 4, "melee": false, "flying": true, "machine": true, "min_threat": 1,
		"hint": "Flies over the front line. Hijackable."},
	"shield": {"name": "Shieldbearer", "role": "Shield", "hp": 230.0, "armor": 3.0, "dmg": 9.0, "interval": 1.3,
		"range": 26.0, "speed": 22.0, "bounty": 7, "melee": true, "front_shield": 0.75, "min_threat": 1,
		"hint": "Frontal shield blocks 75% of gunfire. Breach it, hack it, or let the Sniper pierce."},
	"esniper": {"name": "Sniper", "role": "Sniper", "hp": 90.0, "armor": 0.0, "dmg": 4.0, "interval": 1.6,
		"range": 330.0, "speed": 20.0, "bounty": 7, "melee": false, "min_threat": 2, "backline": true,
		"cast": "aim", "cast_cd": 9.0, "cast_time": 3.0, "cast_damage": 70.0, "first_cast": 3.0,
		"hint": "3s aim, then a massive shot. Stun or shock it, or shield the target."},
	"grenadier": {"name": "Grenadier", "role": "Grenadier", "hp": 110.0, "armor": 1.0, "dmg": 5.0, "interval": 1.2,
		"range": 190.0, "speed": 24.0, "bounty": 6, "melee": false, "min_threat": 2,
		"cast": "grenade", "cast_cd": 8.0, "cast_time": 1.6, "cast_damage": 30.0, "radius": 40.0, "first_cast": 4.0,
		"hint": "Lobs a grenade at clustered mercs. Interrupt it or kill it first."},
	"netrunner": {"name": "Netrunner", "role": "Netrunner", "hp": 100.0, "armor": 0.0, "dmg": 3.0, "interval": 1.2,
		"range": 230.0, "speed": 22.0, "bounty": 8, "melee": false, "min_threat": 2, "backline": true,
		"cast": "upload", "cast_cd": 8.0, "cast_time": 1.8, "cast_dot": 7.0, "cast_duration": 5.0,
		"cast_trace": 8.0, "first_cast": 3.0,
		"hint": "Quickhacks the most chromed merc (burn + Trace). Firewall blocks it; Analog mercs are immune."},
	"turret": {"name": "Turret", "role": "Turret", "hp": 200.0, "armor": 4.0, "dmg": 9.0, "interval": 0.55,
		"range": 280.0, "speed": 0.0, "bounty": 8, "melee": false, "machine": true, "static": true, "min_threat": 2,
		"hint": "Static, hits hard. Hijack it (Trace) or burst it down."},
	"heavy": {"name": "Heavy", "role": "Heavy", "hp": 420.0, "armor": 7.0, "dmg": 17.0, "interval": 1.8,
		"range": 26.0, "speed": 18.0, "bounty": 9, "melee": true, "min_threat": 3,
		"hint": "Armored. Hacks ignore armor; Breach strips it."},
	"cyberpsycho": {"name": "Cyberpsycho", "role": "Boss", "hp": 1700.0, "armor": 4.0, "dmg": 22.0, "interval": 1.4,
		"range": 30.0, "speed": 22.0, "bounty": 60, "melee": true, "boss": true, "min_threat": 99,
		"cast": "berserk_charge", "cast_cd": 11.0, "cast_time": 2.0, "cast_damage": 85.0, "first_cast": 5.0,
		"enrage_pct": 0.5, "enrage_haste": 0.4,
		"hint": "Berserk Charge (2s telegraph) hits the front merc hard. Enrages at 50%."},
}

## Elite affixes (elite nodes give one enemy per wave an affix).
const AFFIXES := {
	"chromed": {"name": "Chromed", "desc": "+40% HP, drops an implant"},
	"shielded": {"name": "Shielded", "desc": "Starts with a 60 shield"},
	"overclocked": {"name": "Overclocked", "desc": "Telegraphs and attacks 30% faster"},
}

const TRAITS := {
	"chromehead": {"name": "Chromehead", "desc": "+1 implant socket, +1 chrome capacity, stress builds 50% faster", "sockets": 1, "chrome": 1, "stress": 0.5},
	"analog": {"name": "Analog", "desc": "-1 socket, +25% HP, immune to enemy quickhacks", "sockets": -1, "hp": 0.25, "analog": true},
	"glass_jaw": {"name": "Glass Jaw", "desc": "+25% damage, -20% HP", "dmg": 0.25, "hp": -0.2},
	"show_off": {"name": "Show-off", "desc": "Signature deals +50% if an enemy is mid-telegraph", "show_off": 0.5},
	"scavenger": {"name": "Scavenger", "desc": "+1 loot option after each fight", "loot": 1},
	"loyal": {"name": "Loyal", "desc": "Never goes cyberpsycho", "loyal": true},
	"old_wound": {"name": "Old Wound", "desc": "Starts with a scar, but +15% damage", "scar": 1, "dmg": 0.15},
}

## Rep perks: after PERK_FIGHTS fights a merc picks 1 of their 2.
const PERKS := {
	"solo": [
		{"id": "blade_dance", "name": "Blade Dance", "desc": "Sandevistan hits 5 enemies"},
		{"id": "adrenaline", "name": "Adrenaline", "desc": "+20% attack speed"},
	],
	"borg": [
		{"id": "iron_wall", "name": "Iron Wall", "desc": "Bulwark lasts 7s"},
		{"id": "heavy_hitter", "name": "Heavy Hitter", "desc": "+25% damage"},
	],
	"medtech": [
		{"id": "field_surgeon", "name": "Field Surgeon", "desc": "Stim heals +60%"},
		{"id": "triage", "name": "Triage", "desc": "Stim also heals the second weakest ally"},
	],
	"techie": [
		{"id": "twin_turret", "name": "Heavy Turret", "desc": "Turret has +60% HP and damage"},
		{"id": "relay", "name": "Relay", "desc": "+20% RAM regen for the deck"},
	],
	"sniper": [
		{"id": "deadeye", "name": "Deadeye", "desc": "Mark every 6s"},
		{"id": "hollow_points", "name": "Hollow Points", "desc": "+30% damage"},
	],
}

const FIRST_NAMES := [
	"Jax", "Vex", "Rook", "Nyx", "Kade", "Mira", "Tank", "Zero", "Saki", "Dex", "Ivy", "Brick",
	"Echo", "Rune", "Kai", "Lux", "Moxie", "Rex", "Tess", "Juno", "Hex", "Oni", "Pike", "Wren",
]
const HANDLES := [
	"Razor", "Chrome", "Static", "Ghost", "Byte", "Neon", "Torque", "Volt", "Glitch", "Scrap",
	"Ronin", "Spike", "Patch", "Sable", "Cipher", "Flux", "Rust", "Viper", "Kilo", "Halo",
]


## A fresh merc record (plain Dictionary, JSON-serializable). HP is stored as a fraction
## of max so HP bonuses never desync it.
static func make_merc(cls: String, rng: RandomNumberGenerator, with_trait := true) -> Dictionary:
	var m := {
		"id": "%d_%d" % [Time.get_ticks_usec(), rng.randi()],
		"cls": cls,
		"name": "%s \"%s\"" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], HANDLES[rng.randi() % HANDLES.size()]],
		"trait": "",
		"seed": rng.randi() % 1000,
		"hp_pct": 1.0,
		"scars": 0,
		"weapon": "",
		"armor": "",
		"implants": [],
		"fights": 0,
		"perk": "",
		"perk_ready": false,
	}
	if with_trait and rng.randf() < 0.7:
		var keys := TRAITS.keys()
		m.trait = keys[rng.randi() % keys.size()]
		m.scars += int(TRAITS[m.trait].get("scar", 0))
	return m


static func random_class(rng: RandomNumberGenerator) -> String:
	var keys := CLASSES.keys()
	return keys[rng.randi() % keys.size()]


static func trait_def(m: Dictionary) -> Dictionary:
	return TRAITS.get(m.get("trait", ""), {})


static func sockets(m: Dictionary) -> int:
	return maxi(0, int(CLASSES[m.cls].sockets) + int(trait_def(m).get("sockets", 0)))


static func chrome_cap(m: Dictionary) -> int:
	return int(CLASSES[m.cls].chrome) + int(trait_def(m).get("chrome", 0))


static func chrome_load(m: Dictionary) -> int:
	var n := 0
	for ref in m.get("implants", []):
		n += int(ItemDB.get_def(ref).get("chrome", 0))
	return n


## Port events this merc's implants provide ("dodge", "knock", "blast").
static func ports(m: Dictionary) -> Array:
	var out := []
	for ref in m.get("implants", []):
		var p := String(ItemDB.get_def(ref).get("port", ""))
		if p != "":
			out.append(p)
	return out


static func perk_choices(m: Dictionary) -> Array:
	return PERKS.get(m.cls, [])


static func perk_name(m: Dictionary) -> String:
	for p in perk_choices(m):
		if p.id == m.get("perk", ""):
			return p.name
	return ""


## Effective combat stats for a merc: class + trait + scars + gear + perk + skill tree
## bonuses (Game.fixer_stats(): merc_hp_pct, merc_armor, merc_crit, merc_haste, dmg_pct).
static func merc_stats(m: Dictionary, bonus := {}) -> Dictionary:
	var c: Dictionary = CLASSES[m.cls]
	var t := trait_def(m)
	var s := {
		"hp": c.hp, "armor": c.armor, "dmg": c.dmg, "interval": c.interval, "range": c.range,
		"melee": c.melee, "crit": float(bonus.get("merc_crit", 0.0)), "skill": c.skill, "skill_cd": c.skill_cd,
		"cleave": int(c.get("cleave", 0)), "pierce": c.get("pierce", false), "dr": 0.0, "regen": 0.0,
		"dodge_cd": 0.0, "knock_every": 0, "blast_every": 0, "burn_on_hit": 0.0, "ram_on_kill": 0.0,
		"skill_cd_pct": 0.0, "low_dmg": 0.0, "emergency_heal": 0.0, "wave_shield": 0.0,
		"ram_regen_pct": float(c.get("ram_regen_pct", 0.0)), "analog": t.get("analog", false),
		"loyal": t.get("loyal", false), "stress_mul": 1.0 + float(t.get("stress", 0.0)),
		"show_off": float(t.get("show_off", 0.0)), "perk": String(m.get("perk", "")),
	}
	var hp_pct := float(t.get("hp", 0.0)) + float(bonus.get("merc_hp_pct", 0.0))
	var dmg_pct := float(t.get("dmg", 0.0))
	var haste := float(bonus.get("merc_haste", 0.0))
	s.armor += float(bonus.get("merc_armor", 0.0))
	for ref in [m.get("weapon", ""), m.get("armor", "")] + Array(m.get("implants", [])):
		var d := ItemDB.get_def(ref)
		if d.is_empty():
			continue
		var p := float(d.power)
		hp_pct += float(d.get("hp_pct", 0.0)) * p
		s.hp += float(d.get("hp", 0.0)) * p
		s.armor += float(d.get("armor", 0.0)) * p
		dmg_pct += float(d.get("dmg_pct", 0.0)) * p
		var h := float(d.get("haste", 0.0))
		haste += h * (p if h > 0.0 else 1.0)  # upgrades never make a drawback worse
		s.crit += float(d.get("crit", 0.0)) * p
		s.range *= 1.0 + float(d.get("range_pct", 0.0))
		s.cleave += int(d.get("cleave", 0))
		s.pierce = s.pierce or d.get("pierce", false)
		s.dr += float(d.get("dr", 0.0)) * p
		s.regen += float(d.get("regen", 0.0)) * p
		s.burn_on_hit += float(d.get("burn_on_hit", 0.0)) * p
		s.ram_on_kill += float(d.get("ram_on_kill", 0.0))
		s.skill_cd_pct += float(d.get("skill_cd_pct", 0.0)) * p
		s.low_dmg += float(d.get("low_dmg", 0.0)) * p
		s.emergency_heal += float(d.get("emergency_heal", 0.0)) * p
		s.wave_shield += float(d.get("wave_shield", 0.0)) * p
		s.ram_regen_pct += float(d.get("ram_regen_pct", 0.0)) * p
		if d.has("dodge_cd"):
			s.dodge_cd = float(d.dodge_cd) / p
		if d.has("knock_every"):
			s.knock_every = int(d.knock_every)
		if d.has("blast_every"):
			s.blast_every = int(d.blast_every)
	match s.perk:
		"adrenaline": haste += 0.2
		"heavy_hitter": dmg_pct += 0.25
		"hollow_points": dmg_pct += 0.3
		"relay": s.ram_regen_pct += 0.2
		"deadeye": s.skill_cd = 6.0
	s.hp = round(s.hp * maxf(0.2, 1.0 + hp_pct) * maxf(0.3, 1.0 - SCAR_HP * int(m.get("scars", 0))))
	s.dmg = s.dmg * (1.0 + dmg_pct + float(bonus.get("dmg_pct", 0.0)))
	s.interval = s.interval / (1.0 + haste)
	s.skill_cd = s.skill_cd * (1.0 - clampf(s.skill_cd_pct, 0.0, 0.6))
	return s


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


## Enemy kinds that can appear in regular waves at this threat.
static func enemy_pool(threat: int) -> Array:
	var out := []
	for k in ENEMIES:
		if not ENEMIES[k].get("boss", false) and ENEMIES[k].min_threat <= threat:
			out.append(k)
	return out


static func short_name(m: Dictionary) -> String:
	var n: String = m.get("name", "")
	var q := n.find("\"")
	if q >= 0:
		var q2 := n.find("\"", q + 1)
		if q2 > q:
			return n.substr(q + 1, q2 - q - 1)
	return n
