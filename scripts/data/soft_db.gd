class_name SoftDB
extends RefCounted
## Static definitions of all soft (programs). See docs/DESIGN.md.
##
## Active soft fields: name, kind="active", ram, cd, charges (0 = unlimited),
## target ("enemy" | "ally" | "none"), rarity, desc, color, plus effect params.
## Passive soft fields: name, kind="passive", rarity, desc, color, plus effect params.

const RARITY_PRICE := {"common": 150, "uncommon": 300, "rare": 550}

const DEFS := {
	# --- actives ---------------------------------------------------------
	"short_circuit": {
		"name": "Short Circuit", "kind": "active", "ram": 4, "cd": 5.0, "charges": 0,
		"target": "enemy", "rarity": "common", "color": Color("2de2e6"),
		"desc": "45 dmg + stun 1.5s. Interrupts casts.",
		"damage": 45.0, "stun": 1.5,
	},
	"nano_patch": {
		"name": "Nano-Patch", "kind": "active", "ram": 3, "cd": 6.0, "charges": 0,
		"target": "ally", "rarity": "common", "color": Color("4cff8f"),
		"desc": "Heal 70, then 5 HP/s for 4s.",
		"heal": 70.0, "hot": 5.0, "duration": 4.0,
	},
	"overclock": {
		"name": "Overclock", "kind": "active", "ram": 3, "cd": 10.0, "charges": 0,
		"target": "ally", "rarity": "common", "color": Color("f9c80e"),
		"desc": "+60% attack speed for 8s.",
		"haste": 0.6, "duration": 8.0,
	},
	"weapon_glitch": {
		"name": "Weapon Glitch", "kind": "active", "ram": 3, "cd": 8.0, "charges": 0,
		"target": "enemy", "rarity": "common", "color": Color("ff9f1c"),
		"desc": "Enemy deals -60% dmg for 8s.",
		"weaken": 0.6, "duration": 8.0,
	},
	"contagion": {
		"name": "Contagion", "kind": "active", "ram": 5, "cd": 12.0, "charges": 0,
		"target": "enemy", "rarity": "uncommon", "color": Color("9bff3d"),
		"desc": "8 dmg/s for 6s. Spreads to enemies within 70px.",
		"dot": 8.0, "duration": 6.0, "radius": 70.0,
	},
	"firewall": {
		"name": "Firewall", "kind": "active", "ram": 6, "cd": 18.0, "charges": 0,
		"target": "none", "rarity": "uncommon", "color": Color("3d8bff"),
		"desc": "All runners: 50 shield for 10s.",
		"shield": 50.0, "duration": 10.0,
	},
	"synapse_burnout": {
		"name": "Synapse Burnout", "kind": "active", "ram": 7, "cd": 14.0, "charges": 0,
		"target": "enemy", "rarity": "rare", "color": Color("ff3d81"),
		"desc": "80 dmg. Double vs targets under 40% HP.",
		"damage": 80.0, "execute_pct": 0.4,
	},
	"optics_jam": {
		"name": "Optics Jam", "kind": "active", "ram": 4, "cd": 14.0, "charges": 0,
		"target": "none", "rarity": "uncommon", "color": Color("b388ff"),
		"desc": "All enemies 50% miss for 6s.",
		"miss": 0.5, "duration": 6.0,
	},
	"smart_link": {
		"name": "Smart Link", "kind": "active", "ram": 4, "cd": 12.0, "charges": 0,
		"target": "ally", "rarity": "uncommon", "color": Color("ffe066"),
		"desc": "Every hit crits for 6s.",
		"duration": 6.0,
	},
	"cyberpsychosis": {
		"name": "Cyberpsychosis", "kind": "active", "ram": 8, "cd": 25.0, "charges": 0,
		"target": "enemy", "rarity": "rare", "color": Color("ff2a2a"),
		"desc": "Non-boss enemy fights its allies for 8s.",
		"duration": 8.0, "no_boss": true,
	},
	"system_collapse": {
		"name": "System Collapse", "kind": "active", "ram": 10, "cd": 0.0, "charges": 1,
		"target": "enemy", "rarity": "rare", "color": Color("ffffff"),
		"desc": "Kills a non-boss. 300 dmg to a boss. 1 charge per mission.",
		"boss_damage": 300.0,
	},
	# --- passives (daemons) ----------------------------------------------
	"ram_expansion": {
		"name": "RAM Expansion", "kind": "passive", "rarity": "common", "color": Color("2de2e6"),
		"desc": "+3 max RAM.", "max_ram": 3,
	},
	"turbo_coprocessor": {
		"name": "Turbo Coprocessor", "kind": "passive", "rarity": "common", "color": Color("2de2e6"),
		"desc": "+30% RAM regen.", "ram_regen_pct": 0.3,
	},
	"targeting_uplink": {
		"name": "Targeting Uplink", "kind": "passive", "rarity": "uncommon", "color": Color("ff3d81"),
		"desc": "Runners deal +15% dmg.", "dmg_pct": 0.15,
	},
	"biomonitor": {
		"name": "Biomonitor", "kind": "passive", "rarity": "common", "color": Color("4cff8f"),
		"desc": "Runners regen 1.5 HP/s.", "regen": 1.5,
	},
	"data_siphon": {
		"name": "Data Siphon", "kind": "passive", "rarity": "uncommon", "color": Color("9bff3d"),
		"desc": "Each kill restores 1 RAM.", "ram_on_kill": 1.0,
	},
	"ice_sentry": {
		"name": "ICE Sentry", "kind": "passive", "rarity": "uncommon", "color": Color("3d8bff"),
		"desc": "Every 4s: 12 dmg to a random enemy.", "interval": 4.0, "damage": 12.0,
	},
	"bounty_scraper": {
		"name": "Bounty Scraper", "kind": "passive", "rarity": "common", "color": Color("f9c80e"),
		"desc": "+25% eddies from kills.", "bounty_pct": 0.25,
	},
	"kiroshi_link": {
		"name": "Kiroshi Link", "kind": "passive", "rarity": "uncommon", "color": Color("ff9f1c"),
		"desc": "Hacks deal +25% dmg.", "hack_pct": 0.25,
	},
	"autopilot": {
		"name": "Autopilot Daemon", "kind": "passive", "rarity": "rare", "color": Color("b388ff"),
		"desc": "When RAM is full, auto-casts the first ready soft.",
	},
}

const STARTER_OWNED := ["short_circuit", "nano_patch", "overclock", "ram_expansion"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func is_active(id: String) -> bool:
	return get_def(id).get("kind", "") == "active"


static func price(id: String) -> int:
	return RARITY_PRICE.get(get_def(id).get("rarity", "common"), 150)


static func all_ids() -> Array:
	return DEFS.keys()
