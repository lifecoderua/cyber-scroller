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
##   fixer_stats():  max_ram, start_ram, full_ram, hack_power, hack_disc, heat_cap, slots,
##                   ram_on_kill, gear_dmg, merc_hp, rerolls, front_shield, blank_shield,
##                   patch_pct, revive, enemy_hp, trace_pct
##   Run economy:    bounty_pct, start_eddies, fence_disc, skip_pct, loot_options,
##                   fail_shards, stash_slots, extract_items, subnet_bonus, contracts,
##                   threat_bonus, shard_pct, boss_shards, crew_offers, reveal

const UNIT := Vector2(46.0, 41.0)  # px per graph unit (x, y)

const BRANCHES := {
	"core": {"name": "CORE", "color": Color("e6e6f0"), "sign": Vector2(0, 0)},
	"net": {"name": "NETRUNNING", "color": Color("2de2e6"), "sign": Vector2(-1, -1),
		"blurb": "RAM, Heat, hacks"},
	"cred": {"name": "STREET CRED", "color": Color("ff3d81"), "sign": Vector2(1, -1),
		"blurb": "Tougher, deadlier mercs"},
	"biz": {"name": "STREET BIZ", "color": Color("f9c80e"), "sign": Vector2(1, 1),
		"blurb": "Eddies, loot, stash"},
	"intel": {"name": "INTEL", "color": Color("4cff8f"), "sign": Vector2(-1, 1),
		"blurb": "Trace, shards, better jobs"},
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

	# --- NETRUNNING: the deck -------------------------------------------------------
	{"id": "n_ram", "branch": "net", "name": "RAM Buffer", "icon": "RAM", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"max_ram": 1.0}, "show": ["max_ram", 1, "+%d RAM cap"],
		"desc": "Extra memory banks. Hold more RAM between turns."},
	{"id": "n_regen", "branch": "net", "name": "Overclocked Bus", "icon": "REG", "cost": [3, 6, 10], "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"start_ram": 1.0}, "show": ["start_ram", 1, "+%d RAM at fight start"],
		"desc": "The deck boots warm. Start every fight with more RAM."},
	{"id": "n_hack", "branch": "net", "name": "ICEbreaker", "icon": "ICE", "cost": [6, 14], "req": ["n_ram"],
		"at": Vector2(3.1, 0.35), "fx": {"hack_power": 1.0}, "show": ["hack_power", 1, "+%d on Ping, Patch, Firewall, Breach"],
		"desc": "Sharper routines. Damage, heal, shield and breach hacks hit harder."},
	{"id": "n_boot", "branch": "net", "name": "Warm Boot", "icon": "BT", "cost": [10], "req": ["n_ram"],
		"at": Vector2(2.55, 1.5), "fx": {"full_ram": 1.0},
		"desc": "Pre-load the deck. Fights start with full RAM."},
	{"id": "n_cool", "branch": "net", "name": "Heat Sink", "icon": "HS", "cost": [4, 8, 14], "req": ["n_regen"],
		"at": Vector2(1.5, 2.5), "fx": {"heat_cap": 1.0}, "show": ["heat_cap", 1, "+%d Heat capacity"],
		"desc": "More thermal headroom before the deck overheats."},
	{"id": "n_charge", "branch": "net", "name": "Wide Bus", "icon": "+SL", "cost": [16], "req": ["n_hack"],
		"at": Vector2(4.4, 0.9), "fx": {"slots": 1.0},
		"desc": "One more hack slot in the deck."},
	{"id": "n_auto", "branch": "net", "name": "Cheap Cycles", "icon": "-$", "cost": [16], "req": ["n_cool"],
		"at": Vector2(2.9, 2.75), "fx": {"hack_disc": 1.0},
		"desc": "Optimized compilers: every hack costs 1 RAM less (minimum 1)."},
	{"id": "n_cap", "branch": "net", "name": "Neural Overflow", "icon": "NX", "cost": [40], "req": ["n_boot", "n_auto"],
		"at": Vector2(4.05, 2.15), "fx": {"max_ram": 2.0, "ram_on_kill": 1.0},
		"desc": "CAPSTONE. +2 RAM cap and every kill feeds 1 RAM back into the deck."},

	# --- STREET CRED: the crew --------------------------------------------------------
	{"id": "c_dmg", "branch": "cred", "name": "Smart Ammo", "icon": "DMG", "cost": [20], "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"gear_dmg": 1.0}, "show": ["gear_dmg", 1, "+%d on gear damage faces"],
		"desc": "Self-guiding rounds: every gear damage face hits harder."},
	{"id": "c_hp", "branch": "cred", "name": "Subdermal Mesh", "icon": "HP", "cost": [4, 9, 16], "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"merc_hp": 1.0}, "show": ["merc_hp", 1, "+%d merc max HP"],
		"desc": "Mesh under the skin. Mercs take longer to drop."},
	{"id": "c_crit", "branch": "cred", "name": "Steady Hands", "icon": "RR", "cost": [16], "req": ["c_dmg"],
		"at": Vector2(3.1, 0.35), "fx": {"rerolls": 1.0},
		"desc": "+1 reroll every turn."},
	{"id": "c_armor", "branch": "cred", "name": "Plated Chrome", "icon": "ARM", "cost": [6, 14], "req": ["c_hp"],
		"at": Vector2(2.55, 1.5), "fx": {"front_shield": 1.0}, "show": ["front_shield", 1, "Front merc starts each turn with %d shield"],
		"desc": "Dermal plating for whoever stands in front."},
	{"id": "c_patch", "branch": "cred", "name": "Ripperdoc on Call", "icon": "DOC", "cost": [3, 6, 10], "req": ["c_hp"],
		"at": Vector2(1.5, 2.5), "fx": {"patch_pct": 0.5}, "show": ["patch_pct", 100, "+%d%% patch-up after fights"],
		"desc": "A doc on speed dial. Mercs heal more between fights."},
	{"id": "c_reflex", "branch": "cred", "name": "Reflex Mesh", "icon": "SHD", "cost": [10], "req": ["c_crit"],
		"at": Vector2(4.4, 0.9), "fx": {"blank_shield": 1.0},
		"desc": "One blank gear face of every merc becomes Shield 1."},
	{"id": "c_trauma", "branch": "cred", "name": "Trauma Team", "icon": "TT", "cost": [15], "req": ["c_patch"],
		"at": Vector2(2.9, 2.75), "fx": {"revive": 1.0},
		"desc": "Platinum plan. Once per fight, the first merc to go down is pulled back at 30% HP."},
	{"id": "c_cap", "branch": "cred", "name": "Pick of the Litter", "icon": "SQD", "cost": [40], "req": ["c_armor", "c_trauma"],
		"at": Vector2(4.05, 2.15), "fx": {"crew_offers": 1.0},
		"desc": "CAPSTONE. One more crew to pick from, and every crew comes with 3 mercs."},

	# --- STREET BIZ: the run economy -------------------------------------------------------
	{"id": "b_bounty", "branch": "biz", "name": "Bounty Board", "icon": "BNT", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"bounty_pct": 0.08}, "show": ["bounty_pct", 100, "+%d%% eddies from kills"],
		"desc": "Know who's worth what. Kills pay more."},
	{"id": "b_reward", "branch": "biz", "name": "Seed Money", "icon": "€$", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"start_eddies": 15.0}, "show": ["start_eddies", 1, "+%d €$ at run start"],
		"desc": "Start every run with a fatter wallet."},
	{"id": "b_market", "branch": "biz", "name": "Fence Contacts", "icon": "MKT", "cost": [3, 6, 10], "req": ["b_bounty"],
		"at": Vector2(3.1, 0.35), "fx": {"fence_disc": 0.08}, "show": ["fence_disc", 100, "-%d%% Fence and Ripperdoc prices"],
		"desc": "Friends in the back alleys."},
	{"id": "b_hire", "branch": "biz", "name": "Salvager", "icon": "SLV", "cost": [3, 6, 10], "req": ["b_reward"],
		"at": Vector2(2.55, 1.5), "fx": {"skip_pct": 0.35}, "show": ["skip_pct", 100, "+%d%% eddies for skipped loot"],
		"desc": "Unpicked loot sells for more."},
	{"id": "b_gigs", "branch": "biz", "name": "Scavenger Net", "icon": "+LT", "cost": [18], "req": ["b_reward"],
		"at": Vector2(1.5, 2.5), "fx": {"loot_options": 1.0},
		"desc": "One more loot option after every fight."},
	{"id": "b_insure", "branch": "biz", "name": "Insurance Policy", "icon": "INS", "cost": [6, 12], "req": ["b_market"],
		"at": Vector2(4.4, 0.9), "fx": {"fail_shards": 0.25}, "show": ["fail_shards", 100, "+%d%% shards from failed runs"],
		"desc": "Even a burned run pays out a little more."},
	{"id": "b_pool", "branch": "biz", "name": "Stash Locker", "icon": "STH", "cost": [6, 12], "req": ["b_hire"],
		"at": Vector2(2.9, 2.75), "fx": {"stash_slots": 2.0}, "show": ["stash_slots", 1, "+%d stash slots"],
		"desc": "More room in the safehouse for extracted gear."},
	{"id": "b_cap", "branch": "biz", "name": "Fixer Empire", "icon": "EMP", "cost": [40], "req": ["b_hire", "b_pool"],
		"at": Vector2(4.05, 2.15), "fx": {"bounty_pct": 0.1, "fence_disc": 0.1, "extract_items": 1.0},
		"desc": "CAPSTONE. +10% kill eddies, -10% prices, and extract 2 items after a won run."},

	# --- INTEL: Trace and the board ------------------------------------------------------------
	{"id": "i_xp", "branch": "intel", "name": "Trace Scrubber", "icon": "TRC", "cost": T1, "req": ["core"],
		"at": Vector2(1.7, 0.55), "fx": {"trace_pct": 0.05}, "show": ["trace_pct", 100, "-%d%% Trace gain"],
		"desc": "Bounce the connection through more proxies."},
	{"id": "i_shards", "branch": "intel", "name": "Data Miner", "icon": "DAT", "cost": T1, "req": ["core"],
		"at": Vector2(0.7, 1.45), "fx": {"shard_pct": 0.1}, "show": ["shard_pct", 100, "+%d%% Data Shards"],
		"desc": "Scrape every server you pass. More shards from every run."},
	{"id": "i_drop", "branch": "intel", "name": "Subnet Mastery", "icon": "SUB", "cost": [4, 7, 12], "req": ["i_xp"],
		"at": Vector2(3.1, 0.35), "fx": {"subnet_bonus": 5.0}, "show": ["subnet_bonus", 1, "Subnets scrub +%d more Trace"],
		"desc": "You know these nets. Subnet nodes clean your Trace better."},
	{"id": "i_offer", "branch": "intel", "name": "Wider Network", "icon": "JOB", "cost": [10], "req": ["i_xp"],
		"at": Vector2(2.55, 1.5), "fx": {"contracts": 1.0},
		"desc": "More clients know your handle: a 4th contract on the board."},
	{"id": "i_scout", "branch": "intel", "name": "Recon Drones", "icon": "REC", "cost": [14], "req": ["i_shards"],
		"at": Vector2(1.5, 2.5), "fx": {"enemy_hp": 1.0},
		"desc": "Drones mark weak points: enemies spawn with 1 less HP."},
	{"id": "i_threat", "branch": "intel", "name": "Rep Broker", "icon": "THR", "cost": [14], "req": ["i_drop"],
		"at": Vector2(4.4, 0.9), "fx": {"threat_bonus": 1.0},
		"desc": "Buy your way onto bigger jobs: +1 max contract threat (still capped at 5)."},
	{"id": "i_dossier", "branch": "intel", "name": "Boss Dossier", "icon": "BOS", "cost": [6, 10, 16], "req": ["i_scout"],
		"at": Vector2(2.9, 2.75), "fx": {"boss_shards": 1.0}, "show": ["boss_shards", 1, "+%d shards per boss kill"],
		"desc": "Bosses carry the juiciest data."},
	{"id": "i_cap", "branch": "intel", "name": "Oracle Feed", "icon": "ORC", "cost": [40], "req": ["i_offer", "i_dossier"],
		"at": Vector2(4.05, 2.15), "fx": {"shard_pct": 0.25, "reveal": 1.0, "trace_pct": 0.1},
		"desc": "CAPSTONE. +25% shards, -10% Trace gain, and the map shows what every node holds."},
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
