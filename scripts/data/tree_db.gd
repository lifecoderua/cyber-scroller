class_name TreeDB
extends RefCounted
## Fixer skill tree ("the net"): meta progression bought with Data Shards. See docs/DESIGN.md.
##
## Node fields:
##   id, branch, name, icon (2-3 chars drawn inside the node), desc,
##   cost: Array[int] (one entry per rank, so max rank = cost.size()),
##   req: Array[node id] (all must have rank >= 1),
##   at: Vector2 local position in graph units (mirrored into the branch quadrant),
##   fx: {effect_key: float per rank | Array[float] per-rank increments},
##   show: [effect_key, multiplier, format] used for the "NOW / NEXT" lines (optional).
##
## Effect keys are summed over all nodes by Game.tree_bonus(key). Consumers:
##   fixer_stats():  max_ram, ram_regen_pct, cd_pct, hack_pct, full_ram, charges,
##                   autopilot_pct, ram_on_kill, dmg_pct, bounty_pct,
##                   runner_hp_pct, runner_armor, runner_crit, runner_haste,
##                   patch_pct, revive, enemy_hp_pct
##   Game economy:   reward_pct, hire_disc, hire_pool, market_disc, wipe_keep, gig_rate,
##                   gig_cap_h, xp_pct, drop_pct, contracts, threat_bonus, shard_pct,
##                   boss_shards, squad_slots

const UNIT := Vector2(46.0, 41.0)  # px per graph unit (x, y)

const BRANCHES := {
	"core": {"name": "CORE", "color": Color("e6e6f0"), "sign": Vector2(0, 0)},
	"net": {"name": "NETRUNNING", "color": Color("2de2e6"), "sign": Vector2(-1, -1),
		"blurb": "RAM, regen, cooldowns, hacks"},
	"cred": {"name": "STREET CRED", "color": Color("ff3d81"), "sign": Vector2(1, -1),
		"blurb": "Tougher, deadlier runners"},
	"biz": {"name": "FIXER BUSINESS", "color": Color("f9c80e"), "sign": Vector2(1, 1),
		"blurb": "Eddies, discounts, side gigs"},
	"intel": {"name": "INTEL", "color": Color("4cff8f"), "sign": Vector2(-1, 1),
		"blurb": "XP, shards, drops, better jobs"},
}

# Shared branch shape (local units, x/y both pointing away from the core):
#   s1 (1.7,0.55)  s2 (0.7,1.45)   tier 1, linked to the core
#   s3 (3.1,0.35)  s4 (2.55,1.5)  s5 (1.5,2.5)   tier 2
#   s6 (4.4,0.9)   s7 (2.9,2.75)  tier 3
#   cap (4.05,2.15) capstone, needs s4 + s7
const T1 := [2, 3, 5, 8, 12]

const NODES := [
	{"id": "core", "branch": "core", "name": "Fixer Core", "icon": "FX", "cost": [1], "req": [],
		"at": Vector2(0, 0), "fx": {"max_ram": 1.0},
		"desc": "Jack your deck into the net. +1 max RAM and access to every branch."},

	# --- NETRUNNING ---------------------------------------------------------------
	{"id": "n_ram", "branch": "net", "name": "RAM Buffer", "icon": "RAM", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"max_ram": 1.0}, "show": ["max_ram", 1, "+%d max RAM"],
		"desc": "Extra memory banks. More RAM for soft in a pinch."},
	{"id": "n_regen", "branch": "net", "name": "Overclocked Bus", "icon": "REG", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"ram_regen_pct": 0.06}, "show": ["ram_regen_pct", 100, "+%d%% RAM regen"],
		"desc": "Faster data bus. RAM refills quicker during missions."},
	{"id": "n_hack", "branch": "net", "name": "ICEbreaker", "icon": "ICE", "cost": [4, 7, 12, 18], "req": ["n_ram"],
		"at": Vector2(3.1, 0.35), "fx": {"hack_pct": 0.08}, "show": ["hack_pct", 100, "+%d%% hack damage"],
		"desc": "Sharper attack routines. All soft and ICE damage hits harder."},
	{"id": "n_boot", "branch": "net", "name": "Warm Boot", "icon": "BT", "cost": [10], "req": ["n_ram"],
		"at": Vector2(2.55, 1.5), "fx": {"full_ram": 1.0},
		"desc": "Pre-load the deck in the van. Missions start with full RAM (instead of 60%)."},
	{"id": "n_cool", "branch": "net", "name": "Cryo Cooling", "icon": "CD", "cost": [4, 8, 14], "req": ["n_regen"],
		"at": Vector2(1.5, 2.5), "fx": {"cd_pct": 0.06}, "show": ["cd_pct", 100, "-%d%% soft cooldowns"],
		"desc": "Liquid nitrogen on the cores. Soft comes off cooldown sooner."},
	{"id": "n_charge", "branch": "net", "name": "Spare Cartridge", "icon": "CHG", "cost": [16], "req": ["n_hack"],
		"at": Vector2(4.4, 0.9), "fx": {"charges": 1.0},
		"desc": "Every soft with limited charges (System Collapse) gets +1 charge per mission."},
	{"id": "n_auto", "branch": "net", "name": "Autopilot v2", "icon": "AP", "cost": [8, 16], "req": ["n_cool"],
		"at": Vector2(2.9, 2.75), "fx": {"autopilot_pct": 0.15}, "show": ["autopilot_pct", -100, "Autopilot fires at %d%% RAM"],
		"desc": "Patch the Autopilot Daemon: it stops hoarding and casts before RAM is full."},
	{"id": "n_cap", "branch": "net", "name": "Neural Overflow", "icon": "NX", "cost": [40], "req": ["n_boot", "n_auto"],
		"at": Vector2(4.05, 2.15), "fx": {"max_ram": 2.0, "ram_on_kill": 0.5},
		"desc": "CAPSTONE. +2 max RAM and every kill feeds 0.5 RAM back into the deck."},

	# --- STREET CRED --------------------------------------------------------------
	{"id": "c_dmg", "branch": "cred", "name": "Smart Ammo", "icon": "DMG", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"dmg_pct": 0.05}, "show": ["dmg_pct", 100, "+%d%% runner damage"],
		"desc": "Self-guiding rounds for the whole crew."},
	{"id": "c_hp", "branch": "cred", "name": "Subdermal Armor", "icon": "HP", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"runner_hp_pct": 0.06}, "show": ["runner_hp_pct", 100, "+%d%% runner HP"],
		"desc": "Mesh under the skin. Runners take longer to drop."},
	{"id": "c_crit", "branch": "cred", "name": "Combat Stims", "icon": "CRT", "cost": [4, 7, 12], "req": ["c_dmg"],
		"at": Vector2(3.1, 0.35), "fx": {"runner_crit": 0.03}, "show": ["runner_crit", 100, "+%d%% crit chance"],
		"desc": "Focus in a syringe. Runners crit more often."},
	{"id": "c_armor", "branch": "cred", "name": "Plated Chrome", "icon": "ARM", "cost": [5, 9, 15], "req": ["c_hp"],
		"at": Vector2(2.55, 1.5), "fx": {"runner_armor": 1.0}, "show": ["runner_armor", 1, "+%d runner armor"],
		"desc": "Dermal plating for the crew. Flat armor against every hit."},
	{"id": "c_patch", "branch": "cred", "name": "Ripperdoc on Call", "icon": "DOC", "cost": [3, 6, 10], "req": ["c_hp"],
		"at": Vector2(1.5, 2.5), "fx": {"patch_pct": 0.5}, "show": ["patch_pct", 100, "+%d%% patch-up between fights"],
		"desc": "A doc on speed dial. Runners heal faster while walking between fights."},
	{"id": "c_reflex", "branch": "cred", "name": "Kerenzikov", "icon": "SPD", "cost": [8, 14, 22], "req": ["c_crit"],
		"at": Vector2(4.4, 0.9), "fx": {"runner_haste": 0.05}, "show": ["runner_haste", 100, "+%d%% attack speed"],
		"desc": "Reflex boosters. Runners attack faster."},
	{"id": "c_trauma", "branch": "cred", "name": "Trauma Team", "icon": "TT", "cost": [15], "req": ["c_patch"],
		"at": Vector2(2.9, 2.75), "fx": {"revive": 1.0},
		"desc": "Platinum plan. Once per mission, the first runner to go down is pulled back at 30% HP."},
	{"id": "c_cap", "branch": "cred", "name": "Full Crew", "icon": "SQD", "cost": [40], "req": ["c_armor", "c_trauma"],
		"at": Vector2(4.05, 2.15), "fx": {"squad_slots": 1.0},
		"desc": "CAPSTONE. Your rep holds a bigger crew together: +1 squad slot (4 runners)."},

	# --- FIXER BUSINESS -----------------------------------------------------------
	{"id": "b_bounty", "branch": "biz", "name": "Bounty Board", "icon": "BNT", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"bounty_pct": 0.08}, "show": ["bounty_pct", 100, "+%d%% eddies from kills"],
		"desc": "Know who's worth what. Kills drop more eddies into the bag."},
	{"id": "b_reward", "branch": "biz", "name": "Haggler", "icon": "PAY", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"reward_pct": 0.06}, "show": ["reward_pct", 100, "+%d%% contract pay"],
		"desc": "Never take the first offer. Clients pay more on success."},
	{"id": "b_market", "branch": "biz", "name": "Fence Contacts", "icon": "MKT", "cost": [3, 6, 10], "req": ["b_bounty"],
		"at": Vector2(3.1, 0.35), "fx": {"market_disc": 0.07}, "show": ["market_disc", 100, "-%d%% Black Market prices"],
		"desc": "Friends in the back alleys. Soft costs less."},
	{"id": "b_hire", "branch": "biz", "name": "Recruiter Network", "icon": "HR", "cost": [3, 6, 10], "req": ["b_reward"],
		"at": Vector2(2.55, 1.5), "fx": {"hire_disc": 0.08}, "show": ["hire_disc", 100, "-%d%% hiring costs"],
		"desc": "Word of mouth brings runners cheaper."},
	{"id": "b_gigs", "branch": "biz", "name": "Side Gigs", "icon": "GIG", "cost": [5, 10, 18], "req": ["b_reward"],
		"at": Vector2(1.5, 2.5), "fx": {"gig_rate": [1.0, 1.0, 2.0]}, "show": ["gig_rate", 1, "+%d €$ per minute away"],
		"desc": "The fixer takes small jobs on the side. Earn eddies while the game is closed (up to 8 h)."},
	{"id": "b_insure", "branch": "biz", "name": "Insurance Policy", "icon": "INS", "cost": [6, 12], "req": ["b_market"],
		"at": Vector2(4.4, 0.9), "fx": {"wipe_keep": 0.25}, "show": ["wipe_keep", 100, "Keep %d%% of the bag on a wipe"],
		"desc": "A courier picks up the loot when the squad flatlines."},
	{"id": "b_pool", "branch": "biz", "name": "Talent Scout", "icon": "+HR", "cost": [6, 12], "req": ["b_hire"],
		"at": Vector2(2.9, 2.75), "fx": {"hire_pool": 1.0}, "show": ["hire_pool", 1, "+%d hire candidates"],
		"desc": "More faces on the hiring board after every job."},
	{"id": "b_cap", "branch": "biz", "name": "Fixer Empire", "icon": "EMP", "cost": [40], "req": ["b_hire", "b_pool"],
		"at": Vector2(4.05, 2.15), "fx": {"bounty_pct": 0.1, "reward_pct": 0.1, "gig_cap_h": 4.0},
		"desc": "CAPSTONE. +10% kill eddies, +10% contract pay, and side gigs pay for up to 12 h away."},

	# --- INTEL --------------------------------------------------------------------
	{"id": "i_xp", "branch": "intel", "name": "Mentorship", "icon": "XP", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"xp_pct": 0.1}, "show": ["xp_pct", 100, "+%d%% runner XP"],
		"desc": "Old hands train the new blood. Runners level faster."},
	{"id": "i_shards", "branch": "intel", "name": "Data Miner", "icon": "DAT", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"shard_pct": 0.1}, "show": ["shard_pct", 100, "+%d%% Data Shards"],
		"desc": "Scrape every server you pass. More shards from every job."},
	{"id": "i_drop", "branch": "intel", "name": "Loot Scanner", "icon": "DRP", "cost": [4, 7, 12], "req": ["i_xp"],
		"at": Vector2(3.1, 0.35), "fx": {"drop_pct": 0.08}, "show": ["drop_pct", 100, "+%d%% soft drop chance"],
		"desc": "Scan the boss's deck before the body cools. Better odds of a soft drop."},
	{"id": "i_offer", "branch": "intel", "name": "Wider Network", "icon": "JOB", "cost": [10], "req": ["i_xp"],
		"at": Vector2(2.55, 1.5), "fx": {"contracts": 1.0},
		"desc": "More clients know your handle: a 4th contract on the board."},
	{"id": "i_scout", "branch": "intel", "name": "Recon Drones", "icon": "REC", "cost": [4, 8, 14], "req": ["i_shards"],
		"at": Vector2(1.5, 2.5), "fx": {"enemy_hp_pct": 0.04}, "show": ["enemy_hp_pct", 100, "Enemies spawn with -%d%% HP"],
		"desc": "Drones mark weak points ahead of the squad."},
	{"id": "i_threat", "branch": "intel", "name": "Rep Broker", "icon": "THR", "cost": [14], "req": ["i_drop"],
		"at": Vector2(4.4, 0.9), "fx": {"threat_bonus": 1.0},
		"desc": "Buy your way onto bigger jobs: +1 max contract threat (still capped at 5)."},
	{"id": "i_dossier", "branch": "intel", "name": "Boss Dossier", "icon": "BOS", "cost": [6, 10, 16], "req": ["i_scout"],
		"at": Vector2(2.9, 2.75), "fx": {"boss_shards": 1.0}, "show": ["boss_shards", 1, "+%d shards per boss kill"],
		"desc": "Bosses carry the juiciest data. Extra shards when you take one down."},
	{"id": "i_cap", "branch": "intel", "name": "Oracle Feed", "icon": "ORC", "cost": [40], "req": ["i_offer", "i_dossier"],
		"at": Vector2(4.05, 2.15), "fx": {"shard_pct": 0.25, "drop_pct": 0.2},
		"desc": "CAPSTONE. A line straight into the corp nets: +25% shards and +20% soft drop chance."},
]

static var _index := {}


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for n in NODES:
		_index[n.id] = n


static func def(id: String) -> Dictionary:
	_ensure_index()
	return _index.get(id, {})


static func all_ids() -> Array:
	_ensure_index()
	return _index.keys()


static func max_rank(id: String) -> int:
	return def(id).get("cost", []).size()


## Cost of the next rank, or -1 when maxed / unknown.
static func cost_for(id: String, current_rank: int) -> int:
	var c: Array = def(id).get("cost", [])
	return int(c[current_rank]) if current_rank < c.size() else -1


static func branch_color(id: String) -> Color:
	return BRANCHES[def(id).get("branch", "core")].color


## Graph position in px, relative to the core.
static func pos(id: String) -> Vector2:
	var n := def(id)
	var s: Vector2 = BRANCHES[n.get("branch", "core")].sign
	var at: Vector2 = n.get("at", Vector2.ZERO)
	return Vector2(at.x * s.x, at.y * s.y) * UNIT


## Total value of one effect key contributed by a node at `rank`.
static func effect_at(id: String, key: String, rank: int) -> float:
	var v = def(id).get("fx", {}).get(key, 0.0)
	if v is Array:
		var total := 0.0
		for i in mini(rank, v.size()):
			total += float(v[i])
		return total
	return float(v) * rank


## "+12% RAM regen" for a node at a rank, or "" when the node has no numeric line.
static func show_text(id: String, rank: int) -> String:
	var n := def(id)
	if not n.has("show"):
		return ""
	var s: Array = n.show
	var v := effect_at(id, s[0], rank) * float(s[1])
	if float(s[1]) < 0.0:
		v = 100.0 + v  # "fires at X% RAM"
	return String(s[2]) % int(round(v))
