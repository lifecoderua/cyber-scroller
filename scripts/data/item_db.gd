class_name ItemDB
extends RefCounted
## Merc gear as dice changes (docs/DICE_DESIGN.md). Weapons and armor rewrite the gear die
## ("mod"), implants fill a chrome-die socket ("face") and may carry a port event daemons hook.
##
## Item reference: "kevlar" (tier 1) or "kevlar+" (tier 2, upgraded at a Ripperdoc: +1 pip on
## the faces it adds or changes). Fields: name, slot (weapon | armor | implant), chrome
## (implants), port, rarity, desc, theme (loot location tags), mod / face / hp / *_turn.

const RARITY_PRICE := {"common": 35, "uncommon": 60, "rare": 95}
const SLOT_ICONS := {"weapon": "W", "armor": "A", "implant": "I"}
const SLOT_COLORS := {"weapon": Color("ff6a2a"), "armor": Color("8ab4ff"), "implant": Color("ff6ad5")}

const DEFS := {
	# --- weapons: rewrite the gear die -----------------------------------------------
	"mono_wire": {"name": "Mono-wire", "slot": "weapon", "rarity": "rare", "theme": ["armory", "street"],
		"mod": "atk_to_cleave", "plus": 0, "ram_on_kill": 1, "desc": "Gear ATK faces become Cleave. Kills refund 1 RAM."},
	"smart_rifle": {"name": "Smart Rifle", "slot": "weapon", "rarity": "uncommon", "theme": ["armory"],
		"mod": "shot_to_pierce", "plus": 1, "desc": "Gear SHT faces become Pierce +1."},
	"riot_shotgun": {"name": "Riot Shotgun", "slot": "weapon", "rarity": "uncommon", "theme": ["armory", "street"],
		"mod": "atk_to_cleave", "plus": 1, "desc": "Gear ATK faces become Cleave +1."},
	"rail_pistol": {"name": "Rail Pistol", "slot": "weapon", "rarity": "common", "theme": ["armory", "street"],
		"mod": "dmg_plus", "plus": 1, "desc": "+1 on every gear damage face."},
	"thermal_katana": {"name": "Thermal Katana", "slot": "weapon", "rarity": "uncommon", "theme": ["armory"],
		"mod": "burn", "desc": "Gear damage faces also burn 1 for 2 turns."},
	# --- armor -------------------------------------------------------------------------
	"kevlar": {"name": "Kevlar Vest", "slot": "armor", "rarity": "common", "theme": ["street", "clinic"],
		"hp": 3, "mod": "blank_shield", "desc": "+3 max HP. A gear blank becomes Shield 2."},
	"riot_plating": {"name": "Riot Plating", "slot": "armor", "rarity": "uncommon", "theme": ["armory"],
		"mod": "shield_plus", "plus": 2, "desc": "Gear Shield faces +2."},
	"ablative": {"name": "Ablative Coat", "slot": "armor", "rarity": "uncommon", "theme": ["server", "armory"],
		"shield_turn": 2, "desc": "2 shield at the start of every turn."},
	"nanoweave": {"name": "Nanoweave", "slot": "armor", "rarity": "rare", "theme": ["clinic"],
		"heal_turn": 1, "hp": 1, "desc": "Heal 1 at the start of every turn. +1 max HP."},
	# --- implants: fill a chrome-die socket --------------------------------------------
	"kerenzikov": {"name": "Kerenzikov", "slot": "implant", "chrome": 2, "port": "dodge", "rarity": "uncommon",
		"theme": ["clinic", "street"], "face": ["dodge", 0], "desc": "Socket: Dodge. PORT: On Dodge."},
	"gorilla_arms": {"name": "Gorilla Arms", "slot": "implant", "chrome": 2, "port": "knock", "rarity": "uncommon",
		"theme": ["clinic", "armory"], "face": ["atk", 5], "desc": "Socket: ATK5 (knockback). PORT: On Knockback."},
	"proj_launcher": {"name": "Projectile Launcher", "slot": "implant", "chrome": 3, "port": "blast", "rarity": "rare",
		"theme": ["armory"], "face": ["blast", 2], "desc": "Socket: Blast 2 (every enemy). PORT: On Blast."},
	"subdermal": {"name": "Subdermal Armor", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["clinic", "street"], "face": ["shield", 3], "hp": 1, "desc": "Socket: Shield 3. +1 max HP."},
	"pain_editor": {"name": "Pain Editor", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["clinic"], "face": ["shield", 5], "desc": "Socket: Shield 5."},
	"synaptic": {"name": "Synaptic Booster", "slot": "implant", "chrome": 2, "rarity": "common",
		"theme": ["clinic", "server"], "face": ["atk", 4], "desc": "Socket: ATK4."},
	"biomonitor": {"name": "Biomonitor", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["clinic"], "face": ["heal", 4], "desc": "Socket: Heal 4."},
	"kiroshi": {"name": "Kiroshi Optics", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["street", "server"], "face": ["mark", 2], "desc": "Socket: Mark 2."},
	"neural_link": {"name": "Neural Link", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["server"], "face": ["focus", 2], "desc": "Socket: Focus 2 (next die +2)."},
	"adrenal": {"name": "Adrenal Pump", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["clinic", "street"], "face": ["rage", 6], "desc": "Socket: Rage 6 (the merc takes 1)."},
	"relay_booster": {"name": "Relay Booster", "slot": "implant", "chrome": 1, "rarity": "uncommon",
		"theme": ["server"], "face": ["ram", 2], "desc": "Socket: RAM 2."},
}

static var _cache := {}


static func base_id(ref: String) -> String:
	return ref.trim_suffix("+")


static func tier(ref: String) -> int:
	return 2 if ref.ends_with("+") else 1


static func upgraded(ref: String) -> String:
	return base_id(ref) + "+"


static func get_def(ref: String) -> Dictionary:
	if ref == "":
		return {}
	if _cache.has(ref):
		return _cache[ref]
	var base: Dictionary = DEFS.get(base_id(ref), {})
	if base.is_empty():
		return {}
	var d := base.duplicate()
	d["id"] = base_id(ref)
	d["tier"] = tier(ref)
	_cache[ref] = d
	return d


static func display_name(ref: String) -> String:
	var d := get_def(ref)
	return String(d.get("name", ref)) + (" II" if d.get("tier", 1) == 2 else "")


## Description with tier-2 numbers ("x1.5" note instead of rewriting every string).
static func desc(ref: String) -> String:
	var d := get_def(ref)
	var s := String(d.get("desc", ""))
	if d.get("tier", 1) == 2:
		s += " (upgraded: +1)"
	return s


static func slot_color(slot: String) -> Color:
	return SLOT_COLORS.get(slot, UITheme.TEXT_DIM)


static func price(ref: String) -> int:
	return int(RARITY_PRICE.get(get_def(ref).get("rarity", "common"), 35) * (1.6 if tier(ref) == 2 else 1.0))


static func all_ids() -> Array:
	return DEFS.keys()


static func ids_for_theme(theme: String) -> Array:
	return DEFS.keys().filter(func(id): return theme in DEFS[id].get("theme", []))
