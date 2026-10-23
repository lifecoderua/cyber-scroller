class_name ChipDB
extends RefCounted
## The fixer's cyberdeck: HACKS (active, spend RAM in a turn) and DAEMONS (passive, react to
## dice events). See docs/DICE_DESIGN.md "Fixer".
##
## A chip reference is a String: "ping" (tier 1) or "ping+" (tier 2, recompiled: -1 RAM or
## +1 effect). Fields: name, kind ("hack" | "daemon"), tag (2-4 chars for the tile), ram,
## heat, trace, target ("enemy" | "machine" | "ally" | "die" | "used_die" | "none"), rarity,
## desc, desc2, port (daemons hooked to an implant event), plus effect params.

const RARITY_PRICE := {"common": 30, "uncommon": 50, "rare": 80}
const KIND_COLORS := {"hack": Color("ff3d81"), "daemon": Color("b388ff")}
const KIND_NAMES := {"hack": "HACK", "daemon": "DAEMON"}

## Deck hardware.
const CHASSIS := {
	"name": "Street Mk.I", "hack_slots": 4, "daemon_slots": 3,
	"ram_start": 2, "ram_turn": 2, "ram_cap": 6, "rerolls": 2,
	"heat_cap": 6, "heat_cool": 2, "overheat_trace": 6.0,
}

const DEFS := {
	# --- hacks ---------------------------------------------------------------------
	"short_circuit": {"name": "Short Circuit", "kind": "hack", "tag": "SC", "ram": 3, "heat": 1, "target": "enemy",
		"rarity": "common", "color": Color("7ae8ff"), "t2": {"ram": 2},
		"desc": "Cancel an enemy's intent (breaks an Aim too).", "desc2": "Costs 2 RAM."},
	"spoof": {"name": "Spoof", "kind": "hack", "tag": "SPF", "ram": 3, "heat": 1, "target": "enemy",
		"rarity": "uncommon", "color": Color("b388ff"), "t2": {"ram": 2},
		"desc": "The enemy's intent hits another enemy instead.", "desc2": "Costs 2 RAM."},
	"overclock": {"name": "Overclock", "kind": "hack", "tag": "OVC", "ram": 1, "heat": 2, "target": "die",
		"rarity": "common", "color": Color("f9c80e"), "pips": 2, "t2": {"pips": 3},
		"desc": "+2 on a rolled die. +2 Heat.", "desc2": "+3 on a rolled die."},
	"echo": {"name": "Echo", "kind": "hack", "tag": "ECH", "ram": 3, "heat": 1, "target": "used_die",
		"rarity": "rare", "color": Color("2de2e6"), "t2": {"ram": 2},
		"desc": "A die you already used can be used again.", "desc2": "Costs 2 RAM."},
	"breach": {"name": "Breach", "kind": "hack", "tag": "BRC", "ram": 2, "heat": 1, "target": "enemy",
		"rarity": "common", "color": Color("ffe066"), "vuln": 1, "t2": {"vuln": 2},
		"desc": "Strip shield, armor and front shield; +1 from every hit this turn.", "desc2": "+2 from every hit."},
	"ping": {"name": "Ping", "kind": "hack", "tag": "PNG", "ram": 2, "heat": 1, "target": "enemy",
		"rarity": "common", "color": Color("2de2e6"), "damage": 2, "t2": {"damage": 3},
		"desc": "2 damage to any enemy.", "desc2": "3 damage."},
	"patch": {"name": "Patch", "kind": "hack", "tag": "PAT", "ram": 2, "heat": 1, "target": "ally",
		"rarity": "common", "color": Color("4cff8f"), "heal": 3, "t2": {"heal": 4},
		"desc": "Heal a merc 3.", "desc2": "Heal 4."},
	"firewall": {"name": "Firewall", "kind": "hack", "tag": "FW", "ram": 2, "heat": 1, "target": "ally",
		"rarity": "uncommon", "color": Color("3d8bff"), "shield": 3, "t2": {"shield": 4},
		"desc": "3 shield on a merc; blocks uploads this turn.", "desc2": "4 shield."},
	"hijack": {"name": "Hijack", "kind": "hack", "tag": "HJK", "ram": 4, "heat": 2, "trace": 10.0, "target": "machine",
		"rarity": "rare", "color": Color("ff6ad5"), "t2": {"ram": 3},
		"desc": "A drone or turret turns its intent on its own side. +10 Trace.", "desc2": "Costs 3 RAM."},
	"bandwidth": {"name": "Bandwidth", "kind": "hack", "tag": "BW", "ram": 1, "heat": 1, "target": "none",
		"rarity": "common", "color": Color("8ab4ff"), "rerolls": 1, "t2": {"rerolls": 2},
		"desc": "+1 reroll this turn.", "desc2": "+2 rerolls."},
	# --- daemons -------------------------------------------------------------------
	"data_siphon": {"name": "Data Siphon", "kind": "daemon", "tag": "SIP", "rarity": "common", "event": "kill", "ram": 0,
		"amount": 1, "t2": {"amount": 2}, "desc": "On kill: +1 RAM.", "desc2": "On kill: +2 RAM."},
	"wave_primer": {"name": "Wave Primer", "kind": "daemon", "tag": "WAV", "rarity": "common", "event": "wave", "ram": 0,
		"amount": 2, "t2": {"amount": 3}, "desc": "Wave start: +2 RAM.", "desc2": "Wave start: +3 RAM."},
	"guardian": {"name": "Guardian", "kind": "daemon", "tag": "GRD", "rarity": "uncommon", "event": "low", "ram": 0,
		"amount": 2, "t2": {"amount": 4}, "desc": "A merc drops under 40% HP: 2 shield (once per merc per fight).", "desc2": "4 shield."},
	"static_discharge": {"name": "Static Discharge", "kind": "daemon", "tag": "STC", "rarity": "uncommon", "event": "shield_face", "ram": 0,
		"amount": 1, "t2": {"amount": 2}, "desc": "A Shield face is used: +1 RAM.", "desc2": "+2 RAM."},
	"packet_sniffer": {"name": "Packet Sniffer", "kind": "daemon", "tag": "PKT", "rarity": "uncommon", "event": "turn", "ram": 0,
		"rerolls": 1, "t2": {"rerolls": 2}, "desc": "+1 reroll every turn.", "desc2": "+2 rerolls every turn."},
	"ice_sentry": {"name": "ICE Sentry", "kind": "daemon", "tag": "ICE", "rarity": "uncommon", "event": "end", "ram": 0,
		"amount": 1, "t2": {"amount": 2}, "desc": "End of turn: 1 damage to a random enemy.", "desc2": "2 damage."},
	"cooling_loop": {"name": "Cooling Loop", "kind": "daemon", "tag": "COL", "rarity": "common", "event": "turn", "ram": 0,
		"cool": 1, "t2": {"cool": 2}, "desc": "Heat cools 1 more every turn.", "desc2": "2 more."},
	"dodge_relay": {"name": "Dodge Relay", "kind": "daemon", "tag": "DDG", "rarity": "uncommon", "event": "dodge", "port": "dodge", "ram": 0,
		"amount": 1, "t2": {"amount": 2}, "desc": "PORT Kerenzikov: a merc dodges a hit: +1 RAM.", "desc2": "+2 RAM."},
	"shrapnel_link": {"name": "Shrapnel Link", "kind": "daemon", "tag": "SHR", "rarity": "rare", "event": "blast", "port": "blast", "ram": 0,
		"amount": 1, "t2": {"amount": 2}, "desc": "PORT Projectile Launcher: a Blast face is used: +1 damage to every enemy.", "desc2": "+2."},
	"recoil_loop": {"name": "Recoil Loop", "kind": "daemon", "tag": "RCL", "rarity": "uncommon", "event": "knock", "port": "knock", "ram": 0,
		"desc": "PORT Gorilla Arms: its ATK5 face also stuns the target.", "desc2": "Also +1 RAM.", "t2": {"amount": 1}},
}

const STARTER_HACKS := ["short_circuit", "overclock", "patch"]
const STARTER_DAEMONS := ["data_siphon"]
const STARTER_SPARE := ["breach", "firewall"]

static var _cache := {}


static func base_id(ref: String) -> String:
	return ref.trim_suffix("+")


static func tier(ref: String) -> int:
	return 2 if ref.ends_with("+") else 1


static func upgraded(ref: String) -> String:
	return base_id(ref) + "+"


## Resolved definition for a chip reference (tier 2 overrides applied). {} if unknown.
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
	if d.tier == 2:
		for k in base.get("t2", {}):
			d[k] = base.t2[k]
	if not d.has("color"):
		d["color"] = KIND_COLORS[d.kind]
	_cache[ref] = d
	return d


static func kind(ref: String) -> String:
	return get_def(ref).get("kind", "")


static func color(ref: String) -> Color:
	return get_def(ref).get("color", UITheme.TEXT_DIM)


static func kind_color(k: String) -> Color:
	return KIND_COLORS.get(k, UITheme.TEXT_DIM)


static func display_name(ref: String) -> String:
	var d := get_def(ref)
	return String(d.get("name", ref)) + (" II" if d.get("tier", 1) == 2 else "")


static func desc(ref: String) -> String:
	var d := get_def(ref)
	if d.get("tier", 1) == 2 and d.has("desc2"):
		return "%s %s" % [d.desc, d.desc2]
	return String(d.get("desc", ""))


static func price(ref: String) -> int:
	var p: int = RARITY_PRICE.get(get_def(ref).get("rarity", "common"), 30)
	return p * (2 if tier(ref) == 2 else 1)


static func all_ids() -> Array:
	return DEFS.keys()


static func ids_of(k: String) -> Array:
	return DEFS.keys().filter(func(id): return DEFS[id].kind == k)


## RAM cost of a hack (tier and skill tree discounts applied).
static func cost(ref: String) -> int:
	return int(get_def(ref).get("ram", 0))


## A port daemon is dark while no living merc carries its implant.
static func is_dark(ref: String, ports: Array) -> bool:
	var d := get_def(ref)
	return d.has("port") and not d.port in ports
