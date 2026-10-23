class_name DiceDB
extends RefCounted
## Dice faces and how mercs' dice are built from class, gear, traits and perks.
## See docs/DICE_DESIGN.md. A face is {k: keyword, v: pips} plus optional "burn".
##
## Targets: "melee" (front enemies), "enemy" (any enemy), "ally", "self", "none".

const KEYWORDS := {
	"atk": {"tag": "ATK", "name": "Attack", "target": "melee", "dmg": true, "color": Color("ff3d81"), "desc": "%d damage (melee reach)."},
	"cleave": {"tag": "CLV", "name": "Cleave", "target": "melee", "dmg": true, "color": Color("ff6a2a"), "desc": "%d damage to the target and its neighbours."},
	"shot": {"tag": "SHT", "name": "Shot", "target": "enemy", "dmg": true, "color": Color("f9c80e"), "desc": "%d damage to any enemy. Front shields block it."},
	"pierce": {"tag": "PRC", "name": "Pierce", "target": "enemy", "dmg": true, "color": Color("ffe066"), "desc": "%d damage to any enemy, ignores shields and armor."},
	"slice": {"tag": "SLC", "name": "Slice", "target": "none", "dmg": true, "color": Color("ff3d81"), "desc": "%d damage to the 3 front enemies, past shields."},
	"blast": {"tag": "BLS", "name": "Blast", "target": "none", "dmg": true, "color": Color("ff9f1c"), "desc": "%d damage to every enemy."},
	"rage": {"tag": "RGE", "name": "Rage", "target": "melee", "dmg": true, "color": Color("ff2a2a"), "desc": "%d damage (melee reach); the merc takes 1."},
	"shield": {"tag": "SHD", "name": "Shield", "target": "ally", "color": Color("3d8bff"), "desc": "%d shield on a merc until the enemies have acted."},
	"heal": {"tag": "HEL", "name": "Heal", "target": "ally", "color": Color("4cff8f"), "desc": "Heal a merc %d."},
	"triage": {"tag": "TRI", "name": "Triage", "target": "none", "color": Color("4cff8f"), "desc": "Heal every merc %d."},
	"taunt": {"tag": "TNT", "name": "Taunt", "target": "self", "color": Color("ff9f1c"), "desc": "%d shield; every single-target intent turns to this merc."},
	"dodge": {"tag": "DDG", "name": "Dodge", "target": "self", "color": Color("2de2e6"), "desc": "The next hit on this merc this turn misses."},
	"mark": {"tag": "MRK", "name": "Mark", "target": "enemy", "color": Color("ffe066"), "desc": "The enemy takes +%d from every hit this turn."},
	"stun": {"tag": "STN", "name": "Stun", "target": "enemy", "color": Color("7ae8ff"), "desc": "Cancel an enemy's intent."},
	"ram": {"tag": "RAM", "name": "RAM", "target": "none", "color": Color("2de2e6"), "desc": "+%d RAM for the fixer."},
	"focus": {"tag": "FOC", "name": "Focus", "target": "none", "color": Color("b388ff"), "desc": "The next die you use gets +%d."},
	"turret": {"tag": "TUR", "name": "Turret", "target": "none", "color": Color("2de2e6"), "desc": "A turret shoots the front enemy for %d at the end of this and the next turn."},
	"glitch": {"tag": "GLT", "name": "Glitch", "target": "none", "color": Color("ff2a2a"), "desc": "%d damage to a random unit, your crew included. Fires by itself if unused."},
	"blank": {"tag": "-", "name": "Blank", "target": "none", "color": Color("4a4a6a"), "desc": "Nothing."},
}

## Gear die by class (weapon + armor baseline) and chrome die signature faces.
const GEAR := {
	"solo": [["atk", 3], ["atk", 3], ["atk", 4], ["atk", 2], ["shield", 2], ["blank", 0]],
	"borg": [["cleave", 2], ["cleave", 3], ["atk", 4], ["shield", 3], ["shield", 3], ["blank", 0]],
	"medtech": [["shot", 2], ["shot", 2], ["heal", 3], ["heal", 3], ["shield", 2], ["blank", 0]],
	"techie": [["shot", 2], ["shot", 3], ["ram", 1], ["ram", 1], ["shield", 2], ["blank", 0]],
	"sniper": [["pierce", 4], ["pierce", 3], ["shot", 3], ["shot", 2], ["blank", 0], ["blank", 0]],
}
const CHROME := {
	"solo": [["slice", 2], ["slice", 3], ["dodge", 0]],
	"borg": [["taunt", 3], ["taunt", 3], ["shield", 4]],
	"medtech": [["heal", 4], ["heal", 5], ["triage", 1]],
	"techie": [["turret", 2], ["ram", 2], ["stun", 0]],
	"sniper": [["mark", 2], ["mark", 2], ["pierce", 5]],
}
const GLITCH_PIPS := 3
## Rep perks that bump a face keyword: perk -> [die, keyword, pips].
const PERK_BUMP := {
	"blade_dance": ["chrome", "slice", 1], "iron_wall": ["chrome", "taunt", 2],
	"field_surgeon": ["chrome", "heal", 2], "twin_turret": ["chrome", "turret", 1],
	"deadeye": ["chrome", "mark", 1], "hollow_points": ["chrome", "pierce", 1],
	"adrenaline": ["gear", "atk", 1], "heavy_hitter": ["gear", "cleave", 1],
}


static func face(k: String, v := 0) -> Dictionary:
	return {"k": k, "v": v}


static func kw(k: String) -> Dictionary:
	return KEYWORDS.get(k, KEYWORDS.blank)


static func is_damage(f: Dictionary) -> bool:
	return kw(String(f.k)).get("dmg", false)


static func target_kind(f: Dictionary) -> String:
	return String(kw(String(f.k)).target)


static func tag(f: Dictionary) -> String:
	var k := String(f.k)
	if k == "blank":
		return "-"
	if k in ["dodge", "stun"]:
		return String(kw(k).tag)
	return "%s%d" % [kw(k).tag, int(f.v)]


static func describe(f: Dictionary) -> String:
	var d := kw(String(f.k))
	var s := String(d.desc)
	if s.contains("%d"):
		s = s % int(f.v)
	if int(f.get("burn", 0)) > 0:
		s += " Burns %d for 2 turns." % int(f.burn)
	return "%s: %s" % [String(d.name), s]


static func dice_text(faces: Array) -> String:
	return " ".join(faces.map(func(f): return tag(f)))


## Both dice of a merc: {gear: [6 faces], chrome: [6 faces], hp: max HP, extras}.
## `bonus` carries skill tree effects (Game.fixer_stats()).
static func merc_dice(m: Dictionary, bonus := {}) -> Dictionary:
	var cls: String = m.cls
	var t := UnitDB.trait_def(m)
	var perk := String(m.get("perk", ""))
	var gear: Array = GEAR[cls].map(func(p): return face(p[0], p[1]))
	var sig: Array = CHROME[cls].map(func(p): return face(p[0], p[1]))
	var hp := int(UnitDB.CLASSES[cls].hp) + int(t.get("hp", 0)) + int(bonus.get("merc_hp", 0))
	var out := {"ram_turn": 0, "shield_turn": 0, "heal_turn": 0, "ram_on_kill": 0}
	# Signature faces: show-off and perks.
	var bump: Array = PERK_BUMP.get(perk, ["", "", 0])
	for f in sig:
		if int(t.get("show_off", 0)) > 0 and f.k != "dodge" and f.k != "stun":
			f.v += 1
		if bump[0] == "chrome" and f.k == bump[1]:
			f.v += int(bump[2])
	# Implants fill sockets (the chrome die has 3 slots after the signature).
	var socket_faces: Array = []
	for ref in m.get("implants", []):
		var d := ItemDB.get_def(ref)
		if d.has("face"):
			var p: Array = d.face
			var f := face(p[0], int(p[1]) + (1 if d.tier == 2 and int(p[1]) > 0 else 0))
			socket_faces.append(f)
		hp += int(d.get("hp", 0))
	var chrome: Array = sig + socket_faces
	if perk == "triage" and chrome.size() < 6:
		chrome.append(face("triage", 2))
	while chrome.size() < 6:
		chrome.append(face("blank"))
	chrome = chrome.slice(0, 6)
	# Over the chrome cap: signature faces turn into Glitch.
	var over := UnitDB.chrome_load(m) - UnitDB.chrome_cap(m)
	if over > 0 and not t.get("loyal", false):
		for i in mini(over, 3):
			chrome[i] = face("glitch", GLITCH_PIPS)
	# Weapon and armor rewrite the gear die.
	for ref in [m.get("weapon", ""), m.get("armor", "")]:
		var d := ItemDB.get_def(ref)
		if d.is_empty():
			continue
		var up := 1 if d.tier == 2 else 0
		hp += int(d.get("hp", 0)) + (2 if up and d.has("hp") else 0)
		for f in gear:
			match String(d.get("mod", "")):
				"atk_to_cleave":
					if f.k == "atk":
						f.k = "cleave"
						f.v += int(d.get("plus", 0)) + up
				"shot_to_pierce":
					if f.k == "shot":
						f.k = "pierce"
						f.v += int(d.get("plus", 0)) + up
				"dmg_plus":
					if is_damage(f):
						f.v += int(d.get("plus", 0)) + up
				"burn":
					if is_damage(f):
						f["burn"] = 1 + up
				"shield_plus":
					if f.k == "shield":
						f.v += int(d.get("plus", 0)) + up
				"blank_shield":
					if f.k == "blank":
						f.k = "shield"
						f.v = 2 + up
						break
		out.ram_on_kill += int(d.get("ram_on_kill", 0))
		out.shield_turn += int(d.get("shield_turn", 0)) + (up if d.has("shield_turn") else 0)
		out.heal_turn += int(d.get("heal_turn", 0))
	# Traits, perks and the skill tree on the gear die.
	var dmg_plus := int(t.get("dmg", 0)) + int(bonus.get("gear_dmg", 0))
	if dmg_plus > 0:
		for f in gear:
			if is_damage(f):
				f.v += dmg_plus
	for f in gear:
		if bump[0] == "gear" and f.k == bump[1]:
			f.v += int(bump[2])
	if int(bonus.get("blank_shield", 0)) > 0:
		for f in gear:
			if f.k == "blank":
				f.k = "shield"
				f.v = 1
				break
	if perk == "relay":
		out.ram_turn += 1
	hp -= int(m.get("scars", 0))
	out.gear = gear
	out.chrome = chrome
	out.hp = maxi(2, hp)
	return out
