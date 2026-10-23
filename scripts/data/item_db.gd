class_name ItemDB
extends RefCounted
## Merc gear: weapons, armor and implants. Item design rule (DESIGN.md): an implant adds a
## port EVENT the deck can hook, or a RULE, or it is a plain stat stick (common filler).
##
## Item reference: "kevlar" (tier 1) or "kevlar+" (tier 2, upgraded at a Ripperdoc;
## numbers x TIER2_POWER). Fields: name, slot (weapon | armor | implant), chrome
## (implants), port (implant event), rarity, desc, theme (loot location tags), stats.

const TIER2_POWER := 1.5
const RARITY_PRICE := {"common": 35, "uncommon": 60, "rare": 95}
const SLOT_ICONS := {"weapon": "W", "armor": "A", "implant": "I"}
const SLOT_COLORS := {"weapon": Color("ff6a2a"), "armor": Color("8ab4ff"), "implant": Color("ff6ad5")}

const DEFS := {
	# --- weapons (replace the archetype's weapon behaviour) -----------------------
	"mono_wire": {"name": "Mono-wire", "slot": "weapon", "rarity": "rare", "theme": ["armory", "street"],
		"cleave": 1, "ram_on_kill": 1.0, "desc": "Hits 1 extra enemy. Each kill refunds 1 RAM."},
	"smart_rifle": {"name": "Smart Rifle", "slot": "weapon", "rarity": "uncommon", "theme": ["armory"],
		"dmg_pct": 0.2, "pierce": true, "desc": "+20% damage. Shots pierce shields."},
	"riot_shotgun": {"name": "Riot Shotgun", "slot": "weapon", "rarity": "uncommon", "theme": ["armory", "street"],
		"cleave": 1, "dmg_pct": 0.15, "range_pct": -0.2, "desc": "Hits 1 extra enemy, +15% damage, -20% range."},
	"rail_pistol": {"name": "Rail Pistol", "slot": "weapon", "rarity": "common", "theme": ["armory", "street"],
		"haste": 0.2, "desc": "+20% attack speed."},
	"thermal_katana": {"name": "Thermal Katana", "slot": "weapon", "rarity": "uncommon", "theme": ["armory"],
		"burn_on_hit": 4.0, "dmg_pct": 0.1, "desc": "Hits burn for 4 dmg/s (3s). +10% damage."},
	# --- armor -------------------------------------------------------------------------
	"kevlar": {"name": "Kevlar Vest", "slot": "armor", "rarity": "common", "theme": ["street", "clinic"],
		"hp": 40.0, "desc": "+40 max HP."},
	"riot_plating": {"name": "Riot Plating", "slot": "armor", "rarity": "uncommon", "theme": ["armory"],
		"armor": 4.0, "haste": -0.1, "desc": "+4 armor, -10% attack speed."},
	"ablative": {"name": "Ablative Coat", "slot": "armor", "rarity": "uncommon", "theme": ["server", "armory"],
		"wave_shield": 30.0, "desc": "30 shield at the start of every wave."},
	"nanoweave": {"name": "Nanoweave", "slot": "armor", "rarity": "rare", "theme": ["clinic"],
		"regen": 2.5, "desc": "Regenerate 2.5 HP/s."},
	# --- implants --------------------------------------------------------------------
	"kerenzikov": {"name": "Kerenzikov", "slot": "implant", "chrome": 2, "port": "dodge", "rarity": "uncommon",
		"theme": ["clinic", "street"], "dodge_cd": 6.0, "desc": "Dodge the first attack every 6s. PORT: On Dodge."},
	"gorilla_arms": {"name": "Gorilla Arms", "slot": "implant", "chrome": 2, "port": "knock", "rarity": "uncommon",
		"theme": ["clinic", "armory"], "knock_every": 4, "dmg_pct": 0.1,
		"desc": "Every 4th attack knocks back. +10% damage. PORT: On Knockback."},
	"proj_launcher": {"name": "Projectile Launcher", "slot": "implant", "chrome": 3, "port": "blast", "rarity": "rare",
		"theme": ["armory"], "blast_every": 5, "desc": "Every 5th attack is a 25 dmg grenade. PORT: On Blast."},
	"subdermal": {"name": "Subdermal Armor", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["clinic", "street"], "armor": 2.0, "hp": 15.0, "desc": "+2 armor, +15 HP."},
	"pain_editor": {"name": "Pain Editor", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["clinic"], "dr": 0.18, "desc": "-18% damage taken."},
	"synaptic": {"name": "Synaptic Booster", "slot": "implant", "chrome": 2, "rarity": "common",
		"theme": ["clinic", "server"], "haste": 0.18, "desc": "+18% attack speed."},
	"biomonitor": {"name": "Biomonitor", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["clinic"], "emergency_heal": 40.0, "desc": "Once per fight: heal 40 when under 35% HP."},
	"kiroshi": {"name": "Kiroshi Optics", "slot": "implant", "chrome": 1, "rarity": "common",
		"theme": ["street", "server"], "crit": 0.12, "desc": "+12% crit chance."},
	"neural_link": {"name": "Neural Link", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["server"], "skill_cd_pct": 0.25, "desc": "Signature cooldown -25%."},
	"adrenal": {"name": "Adrenal Pump", "slot": "implant", "chrome": 2, "rarity": "uncommon",
		"theme": ["clinic", "street"], "low_dmg": 0.35, "desc": "+35% damage while under 50% HP."},
	"relay_booster": {"name": "Relay Booster", "slot": "implant", "chrome": 1, "rarity": "uncommon",
		"theme": ["server"], "ram_regen_pct": 0.12, "desc": "Your deck gets +12% RAM regen while this merc stands."},
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
	d["power"] = TIER2_POWER if d.tier == 2 else 1.0
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
		s += " (upgraded: x1.5)"
	return s


static func slot_color(slot: String) -> Color:
	return SLOT_COLORS.get(slot, UITheme.TEXT_DIM)


static func price(ref: String) -> int:
	return int(RARITY_PRICE.get(get_def(ref).get("rarity", "common"), 35) * (1.6 if tier(ref) == 2 else 1.0))


static func all_ids() -> Array:
	return DEFS.keys()


static func ids_for_theme(theme: String) -> Array:
	return DEFS.keys().filter(func(id): return theme in DEFS[id].get("theme", []))
