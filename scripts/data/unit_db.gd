class_name UnitDB
extends RefCounted
## Merc archetypes, enemy roles (intent dice), traits, perks and name generation.
## See docs/DICE_DESIGN.md. Merc dice are built by DiceDB.merc_dice().

const PERK_FIGHTS := 3      # fights survived before a merc earns a Rep perk
const THREAT_HP := 0.05     # enemy HP x (1 + THREAT_HP * (threat - 1))
const THREAT_DMG := [0, 1, 2, 3, 3]  # +pips on every enemy intent by threat

## row: 0 front, 1 mid, 2 back (crew order on the battlefield).
const CLASSES := {
	"solo": {"name": "Solo", "row": 0, "hp": 9, "sockets": 2, "chrome": 5, "weapon": "Dual blades",
		"skill_name": "Sandevistan", "skill_desc": "Slice faces hit the 3 front enemies; Dodge", "color": Color("ff3d81")},
	"borg": {"name": "Borg", "row": 0, "hp": 12, "sockets": 3, "chrome": 7, "weapon": "Shotgun",
		"skill_name": "Bulwark", "skill_desc": "Taunt faces pull every single-target intent", "color": Color("ff9f1c")},
	"medtech": {"name": "Medtech", "row": 1, "hp": 7, "sockets": 2, "chrome": 5, "weapon": "SMG",
		"skill_name": "Stim", "skill_desc": "Big heals and a Triage face", "color": Color("4cff8f")},
	"techie": {"name": "Techie", "row": 2, "hp": 7, "sockets": 2, "chrome": 5, "weapon": "Pistol",
		"skill_name": "Deploy", "skill_desc": "Turret, RAM and Stun faces", "color": Color("2de2e6")},
	"sniper": {"name": "Sniper", "row": 2, "hp": 6, "sockets": 1, "chrome": 4, "weapon": "Rifle",
		"skill_name": "Mark", "skill_desc": "Mark faces and a Pierce 5", "color": Color("f9c80e")},
}

## Enemy intent keywords: what an enemy face does when it resolves.
const INTENTS := {
	"atk": {"tag": "ATK", "name": "Attack", "who": "front", "desc": "%d damage to the front merc."},
	"rush": {"tag": "RSH", "name": "Rush", "who": "back", "desc": "%d damage to the back merc."},
	"shot": {"tag": "SHT", "name": "Shot", "who": "random", "desc": "%d damage to a merc."},
	"blast": {"tag": "BLS", "name": "Grenade", "who": "random", "desc": "%d damage to a merc and its neighbours."},
	"aim": {"tag": "AIM", "name": "Aim", "who": "random", "desc": "Aiming. Next turn: Snipe %d unless stunned."},
	"snipe": {"tag": "SNP", "name": "Snipe", "who": "fixed", "desc": "%d damage, ignores shields."},
	"upload": {"tag": "UPL", "name": "Upload", "who": "chrome", "desc": "%d damage and +6 Trace. Firewall or Analog blocks it."},
	"guard": {"tag": "GRD", "name": "Guard", "who": "ally", "desc": "%d shield on an ally."},
	"charge": {"tag": "CHG", "name": "Berserk Charge", "who": "front", "desc": "%d damage to the front merc."},
	"rampage": {"tag": "RMP", "name": "Rampage", "who": "all", "desc": "%d damage to every merc."},
	"summon": {"tag": "SUM", "name": "Call Gang", "who": "none", "desc": "A ganger joins the fight."},
	"blank": {"tag": "-", "name": "Idle", "who": "none", "desc": "Does nothing."},
}

const ENEMIES := {
	"ganger": {"name": "Ganger", "role": "Swarm", "hp": 4, "min_threat": 1, "bounty": 3,
		"die": [["atk", 2], ["atk", 2], ["atk", 3], ["atk", 1], ["atk", 2], ["blank", 0]],
		"hint": "Cheap melee. Comes in numbers."},
	"rusher": {"name": "Rusher", "role": "Rusher", "hp": 3, "min_threat": 1, "bounty": 3,
		"die": [["rush", 3], ["rush", 3], ["rush", 2], ["rush", 4], ["atk", 2], ["blank", 0]],
		"hint": "Rush hits your back merc. Taunt pulls it."},
	"gunman": {"name": "Gunman", "role": "Shooter", "hp": 4, "min_threat": 1, "bounty": 3,
		"die": [["shot", 2], ["shot", 2], ["shot", 3], ["shot", 1], ["shot", 2], ["blank", 0]],
		"hint": "Shoots a random merc."},
	"drone": {"name": "Drone", "role": "Drone", "hp": 3, "min_threat": 1, "bounty": 3, "flying": true, "machine": true,
		"die": [["shot", 1], ["shot", 2], ["shot", 1], ["shot", 2], ["shot", 1], ["blank", 0]],
		"hint": "Flying: melee can't reach it. Hijackable."},
	"shield": {"name": "Shieldbearer", "role": "Shield", "hp": 7, "min_threat": 1, "bounty": 4, "front_shield": true,
		"die": [["atk", 2], ["atk", 3], ["guard", 3], ["atk", 2], ["guard", 2], ["atk", 1]],
		"hint": "Its front shield blocks Shot faces. Pierce, melee, Blast or Breach."},
	"esniper": {"name": "Sniper", "role": "Sniper", "hp": 4, "min_threat": 2, "bounty": 4, "backline": true,
		"die": [["aim", 6], ["aim", 6], ["aim", 6], ["aim", 6], ["aim", 6], ["aim", 6]],
		"hint": "Backline. Aims, then snipes for 6. Stun it or kill it first."},
	"grenadier": {"name": "Grenadier", "role": "Grenadier", "hp": 4, "min_threat": 2, "bounty": 4,
		"die": [["blast", 2], ["blast", 2], ["shot", 2], ["blast", 3], ["shot", 1], ["blank", 0]],
		"hint": "Grenades hit a merc and its neighbours."},
	"netrunner": {"name": "Netrunner", "role": "Netrunner", "hp": 4, "min_threat": 2, "bounty": 4, "backline": true,
		"die": [["upload", 2], ["upload", 2], ["upload", 3], ["shot", 1], ["upload", 2], ["blank", 0]],
		"hint": "Backline. Uploads hit the most chromed merc and add Trace. Firewall blocks them."},
	"turret": {"name": "Turret", "role": "Turret", "hp": 7, "min_threat": 2, "bounty": 4, "machine": true,
		"die": [["shot", 3], ["shot", 3], ["shot", 2], ["shot", 4], ["shot", 3], ["blank", 0]],
		"hint": "Static, hits hard. Hijack it or burst it."},
	"heavy": {"name": "Heavy", "role": "Heavy", "hp": 10, "min_threat": 3, "bounty": 5, "armor": 1,
		"die": [["atk", 4], ["atk", 4], ["atk", 3], ["atk", 5], ["atk", 3], ["blank", 0]],
		"hint": "Armor 1: every hit deals 1 less. Pierce and Breach ignore it."},
	"cyberpsycho": {"name": "Cyberpsycho", "role": "Boss", "hp": 30, "min_threat": 99, "bounty": 25, "armor": 1, "boss": true,
		"die": [["atk", 4], ["charge", 7], ["rampage", 2], ["atk", 5], ["charge", 7], ["summon", 0]],
		"hint": "Berserk Charge hits the front merc for 7. Enrages at half HP (+1 to everything)."},
}

## Elite affixes (elite nodes give one enemy per wave an affix).
const AFFIXES := {
	"chromed": {"name": "Chromed", "desc": "+50% HP"},
	"shielded": {"name": "Shielded", "desc": "4 shield every turn"},
	"overclocked": {"name": "Overclocked", "desc": "+1 on every intent"},
}

const TRAITS := {
	"chromehead": {"name": "Chromehead", "desc": "+1 socket and +1 chrome capacity", "sockets": 1, "chrome": 1},
	"analog": {"name": "Analog", "desc": "-1 socket, +3 HP, immune to uploads", "sockets": -1, "hp": 3, "analog": true},
	"glass_jaw": {"name": "Glass Jaw", "desc": "+1 on gear damage faces, -2 HP", "dmg": 1, "hp": -2},
	"show_off": {"name": "Show-off", "desc": "+1 on signature faces", "show_off": 1},
	"scavenger": {"name": "Scavenger", "desc": "+1 loot option after each fight", "loot": 1},
	"loyal": {"name": "Loyal", "desc": "Never glitches, even over the chrome cap", "loyal": true},
	"old_wound": {"name": "Old Wound", "desc": "Starts with a scar, +1 on gear damage faces", "scar": 1, "dmg": 1},
}

const PERKS := {
	"solo": [
		{"id": "blade_dance", "name": "Blade Dance", "desc": "Slice faces +1"},
		{"id": "adrenaline", "name": "Adrenaline", "desc": "Gear Attack faces +1"},
	],
	"borg": [
		{"id": "iron_wall", "name": "Iron Wall", "desc": "Taunt faces +2"},
		{"id": "heavy_hitter", "name": "Heavy Hitter", "desc": "Gear Cleave faces +1"},
	],
	"medtech": [
		{"id": "field_surgeon", "name": "Field Surgeon", "desc": "Chrome Heal faces +2"},
		{"id": "triage", "name": "Triage", "desc": "A free socket becomes Triage 2"},
	],
	"techie": [
		{"id": "twin_turret", "name": "Heavy Turret", "desc": "Turret faces +1"},
		{"id": "relay", "name": "Relay", "desc": "+1 RAM every turn"},
	],
	"sniper": [
		{"id": "deadeye", "name": "Deadeye", "desc": "Mark faces +1"},
		{"id": "hollow_points", "name": "Hollow Points", "desc": "Chrome Pierce +1"},
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
static func make_merc(cls: String, rng: RandomNumberGenerator, with_trait := true, taken: Array = []) -> Dictionary:
	var handle: String = HANDLES[rng.randi() % HANDLES.size()]
	for i in 8:
		if not handle in taken:
			break
		handle = HANDLES[rng.randi() % HANDLES.size()]
	var m := {
		"id": "%d_%d" % [Time.get_ticks_usec(), rng.randi()],
		"cls": cls,
		"name": "%s \"%s\"" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], handle],
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
	return clampi(int(CLASSES[m.cls].sockets) + int(trait_def(m).get("sockets", 0)), 0, 3)


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


static func max_hp(m: Dictionary, bonus := {}) -> int:
	return int(DiceDB.merc_dice(m, bonus).hp)


## Enemy stats at a threat level: hp, die (faces), flags.
static func enemy_stats(kind: String, threat: int) -> Dictionary:
	var e: Dictionary = ENEMIES[kind].duplicate(true)
	e.hp = int(round(float(e.hp) * (1.0 + THREAT_HP * (threat - 1))))
	e["dmg_plus"] = THREAT_DMG[clampi(threat, 1, 5) - 1]
	return e


## Enemy kinds that can appear in regular waves at this threat.
static func enemy_pool(threat: int) -> Array:
	var out := []
	for k in ENEMIES:
		if not ENEMIES[k].get("boss", false) and ENEMIES[k].min_threat <= threat:
			out.append(k)
	return out


static func intent_tag(f: Dictionary) -> String:
	var k := String(f.k)
	if k in ["blank", "summon"]:
		return String(INTENTS[k].tag)
	return "%s%d" % [INTENTS[k].tag, int(f.v)]


static func intent_desc(f: Dictionary) -> String:
	var d: Dictionary = INTENTS[String(f.k)]
	var s := String(d.desc)
	if s.contains("%d"):
		s = s % int(f.v)
	return "%s: %s" % [d.name, s]


static func short_name(m: Dictionary) -> String:
	var n: String = m.get("name", "")
	var q := n.find("\"")
	if q >= 0:
		var q2 := n.find("\"", q + 1)
		if q2 > q:
			return n.substr(q + 1, q2 - q - 1)
	return n
