extends Node
## Autoload "Game": persistent meta state, economy, save/load, contracts.
##
## Hub and mission talk to each other only through this node:
##   hub      -> Game.start_mission(contract_index)   (emits mission_requested)
##   mission  -> Game.finish_mission(result)          (emits mission_finished)
## Result dictionary from the mission:
##   {outcome: "success"|"extracted"|"wiped", bag: int, kills: int,
##    encounters_cleared: int, downed: Array[runner_id], duration: float}
##
## Meta progression: Data Shards buy ranks in the fixer skill tree (TreeDB). Every bonus
## is read through tree_bonus(key); mission-side bonuses travel in fixer_stats().

signal state_changed
signal mission_requested
signal mission_finished
## Side-gig income was found after being away (load / app resume). The hub shows a popup.
signal offline_income

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2  # v2 adds shards, tree_ranks, last_seen_unix, offline_pending
const SQUAD_MAX := 3  # base squad size; see squad_max()
const HIRE_POOL_SIZE := 4
const HIRE_REROLL_COST := 20
const MARKET_SIZE := 4
const ACTIVE_SLOT_PRICES := [400, 800]
const PASSIVE_SLOT_PRICES := [500, 1000]
const BASE_MAX_RAM := 10.0
const BASE_RAM_REGEN := 0.7
const SOFT_DROP_CHANCE := 0.4
const CONTRACT_COUNT := 3
const GIG_CAP_HOURS := 8.0
const GIG_MIN_AWAY := 120  # seconds away before side gigs pay out

const CLIENTS := ["Rogue", "Wakako", "Dex", "Padre", "Mr. Blue Eyes", "Regina", "El Capitan", "Muamar"]
const TARGETS := ["Maelstrom", "Tyger Claws", "Valentinos", "Arasaka", "Militech", "6th Street", "Scavs", "Biotechnica"]
const DISTRICTS := ["Kabuki", "Watson Docks", "Glen Spire", "Neon Row"]
const JOBS := [
	"Steal a data shard from %s",
	"Break a courier out of a %s hold",
	"Torch a %s chop shop",
	"Retrieve a stolen prototype from %s",
	"Flatline a %s lieutenant",
	"Plant a backdoor in a %s server room",
]

var rng := RandomNumberGenerator.new()

var eddies := 300
var rep := 0
var missions_run := 0
var roster: Array = []        # runner dicts (see UnitDB.make_runner)
var squad: Array = []         # runner ids, max SQUAD_MAX
var hire_pool: Array = []     # runner dicts
var owned_soft: Array = []    # soft ids
var deck_active: Array = []   # soft ids, size <= active_slots
var deck_passive: Array = []  # soft ids, size <= passive_slots
var active_slots := 4
var passive_slots := 2
var contracts: Array = []     # contract dicts
var market: Array = []        # soft ids for sale
var current_contract: Dictionary = {}
var last_result: Dictionary = {}  # summary for the hub to display; cleared by hub
var shards := 0                  # Data Shards: skill tree currency
var tree_ranks: Dictionary = {}  # node id -> rank
var last_seen_unix := 0          # wall clock of the last save (offline income)
var offline_pending := 0         # side-gig eddies waiting to be collected
var offline_seconds := 0         # how long the player was away (for the popup)


func _ready() -> void:
	rng.randomize()
	if not load_game():
		new_game()
	accrue_offline()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			save_game()
		NOTIFICATION_APPLICATION_RESUMED:
			accrue_offline()


# --- lifecycle -----------------------------------------------------------

func new_game() -> void:
	eddies = 300
	rep = 0
	missions_run = 0
	roster = [UnitDB.make_runner("solo", rng, false), UnitDB.make_runner("gunner", rng, false)]
	squad = [roster[0].id, roster[1].id]
	owned_soft = SoftDB.STARTER_OWNED.duplicate()
	deck_active = ["short_circuit", "nano_patch", "overclock"]
	deck_passive = ["ram_expansion"]
	active_slots = 4
	passive_slots = 2
	current_contract = {}
	last_result = {}
	shards = 0
	tree_ranks = {}
	offline_pending = 0
	offline_seconds = 0
	refresh_hire_pool()
	refresh_contracts()
	refresh_market()
	save_game()
	state_changed.emit()


func save_game() -> void:
	last_seen_unix = int(Time.get_unix_time_from_system())
	var data := {
		"version": SAVE_VERSION,
		"eddies": eddies, "rep": rep, "missions_run": missions_run,
		"roster": roster, "squad": squad, "hire_pool": hire_pool,
		"owned_soft": owned_soft, "deck_active": deck_active, "deck_passive": deck_passive,
		"active_slots": active_slots, "passive_slots": passive_slots,
		"contracts": contracts, "market": market,
		"shards": shards, "tree_ranks": tree_ranks, "offline_pending": offline_pending,
		"offline_seconds": offline_seconds, "last_seen_unix": last_seen_unix,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# Older saves load too: keys they lack keep their defaults.
	var ver := int(data.get("version", 0))
	if ver < 1 or ver > SAVE_VERSION:
		return false
	eddies = int(data.eddies)
	rep = int(data.rep)
	missions_run = int(data.get("missions_run", 0))
	roster = _fix_runners(data.roster)
	squad = data.squad
	hire_pool = _fix_runners(data.hire_pool)
	owned_soft = data.owned_soft
	deck_active = data.deck_active
	deck_passive = data.deck_passive
	active_slots = int(data.active_slots)
	passive_slots = int(data.passive_slots)
	contracts = data.contracts
	for c in contracts:
		c.threat = int(c.threat)
		c.reward = int(c.reward)
	market = data.market
	shards = int(data.get("shards", 0))
	tree_ranks = {}
	var tr = data.get("tree_ranks", {})
	if typeof(tr) == TYPE_DICTIONARY:
		for k in tr:
			if not TreeDB.def(k).is_empty():
				tree_ranks[k] = clampi(int(tr[k]), 0, TreeDB.max_rank(k))
	offline_pending = int(data.get("offline_pending", 0))
	offline_seconds = int(data.get("offline_seconds", 0))
	last_seen_unix = int(data.get("last_seen_unix", 0))
	return true


## JSON turns ints into floats; normalize runner records.
func _fix_runners(list: Array) -> Array:
	for r in list:
		r.level = int(r.level)
		r.xp = int(r.xp)
		r.seed = int(r.get("seed", 0))
	return list


# --- queries -------------------------------------------------------------

func get_runner(id: String) -> Dictionary:
	for r in roster:
		if r.id == id:
			return r
	return {}


func squad_runners() -> Array:
	var out := []
	for id in squad:
		var r := get_runner(id)
		if not r.is_empty():
			out.append(r)
	return out


func max_threat() -> int:
	return mini(5, 1 + floori(rep / 4.0) + int(tree_bonus("threat_bonus")))


## Rep needed for the next threat tier, or -1 when threat 5 is unlocked.
func next_threat_rep() -> int:
	var mt := max_threat()
	return -1 if mt >= 5 else (mt - int(tree_bonus("threat_bonus"))) * 4


func squad_max() -> int:
	return SQUAD_MAX + int(tree_bonus("squad_slots"))


func hire_pool_size() -> int:
	return HIRE_POOL_SIZE + int(tree_bonus("hire_pool"))


func hire_cost(r: Dictionary) -> int:
	return int(round(UnitDB.hire_cost(r) * (1.0 - tree_bonus("hire_disc"))))


func soft_price(id: String) -> int:
	return int(round(SoftDB.price(id) * (1.0 - tree_bonus("market_disc"))))


## Side-gig income in eddies per minute (0 without the node).
func gig_rate() -> float:
	return tree_bonus("gig_rate")


func gig_cap_hours() -> float:
	return GIG_CAP_HOURS + tree_bonus("gig_cap_h")


## Combined fixer stats from the passive deck and squad (used by the mission).
func fixer_stats() -> Dictionary:
	var s := {
		"max_ram": BASE_MAX_RAM, "ram_regen": BASE_RAM_REGEN, "dmg_pct": 0.0, "regen": 0.0,
		"ram_on_kill": 0.0, "bounty_pct": 0.0, "hack_pct": 0.0, "ice_sentry": false,
		"autopilot": false,
		# Skill tree (see TreeDB): mission rules and runner bonuses.
		"cd_pct": tree_bonus("cd_pct"), "full_ram": tree_bonus("full_ram") > 0.0,
		"charges": int(tree_bonus("charges")), "autopilot_pct": tree_bonus("autopilot_pct"),
		"runner_hp_pct": tree_bonus("runner_hp_pct"), "runner_armor": tree_bonus("runner_armor"),
		"runner_crit": tree_bonus("runner_crit"), "runner_haste": tree_bonus("runner_haste"),
		"patch_pct": tree_bonus("patch_pct"), "revive": int(tree_bonus("revive")),
		"enemy_hp_pct": tree_bonus("enemy_hp_pct"),
	}
	s.max_ram += tree_bonus("max_ram")
	s.dmg_pct += tree_bonus("dmg_pct")
	s.hack_pct += tree_bonus("hack_pct")
	s.bounty_pct += tree_bonus("bounty_pct")
	s.ram_on_kill += tree_bonus("ram_on_kill")
	var regen_pct := tree_bonus("ram_regen_pct")
	for id in deck_passive:
		var d := SoftDB.get_def(id)
		s.max_ram += d.get("max_ram", 0)
		regen_pct += d.get("ram_regen_pct", 0.0)
		s.dmg_pct += d.get("dmg_pct", 0.0)
		s.regen += d.get("regen", 0.0)
		s.ram_on_kill += d.get("ram_on_kill", 0.0)
		s.bounty_pct += d.get("bounty_pct", 0.0)
		s.hack_pct += d.get("hack_pct", 0.0)
		if id == "ice_sentry":
			s.ice_sentry = true
		if id == "autopilot":
			s.autopilot = true
	for r in squad_runners():
		regen_pct += UnitDB.CLASSES[r.cls].get("ram_regen_pct", 0.0)
	s.ram_regen *= 1.0 + regen_pct
	return s


## Runner stats with skill tree bonuses (what the mission will use).
func runner_stats(r: Dictionary) -> Dictionary:
	return UnitDB.runner_stats(r, fixer_stats())


# --- skill tree ----------------------------------------------------------

func tree_rank(id: String) -> int:
	return int(tree_ranks.get(id, 0))


## Sum of one effect key over every bought node.
func tree_bonus(key: String) -> float:
	var total := 0.0
	for id in tree_ranks:
		var r := int(tree_ranks[id])
		if r > 0:
			total += TreeDB.effect_at(id, key, r)
	return total


func node_unlocked(id: String) -> bool:
	var d := TreeDB.def(id)
	if d.is_empty():
		return false
	for req in d.get("req", []):
		if tree_rank(req) <= 0:
			return false
	return true


## Next rank cost, or -1 when maxed.
func node_cost(id: String) -> int:
	return TreeDB.cost_for(id, tree_rank(id))


## "locked" | "open" (unlocked, rank 0) | "owned" (some ranks) | "maxed".
func node_state(id: String) -> String:
	var r := tree_rank(id)
	if r >= TreeDB.max_rank(id):
		return "maxed"
	if r > 0:
		return "owned"
	return "open" if node_unlocked(id) else "locked"


func can_buy_node(id: String) -> bool:
	var c := node_cost(id)
	return c >= 0 and node_unlocked(id) and shards >= c


func buy_node(id: String) -> bool:
	if not can_buy_node(id):
		return false
	shards -= node_cost(id)
	tree_ranks[id] = tree_rank(id) + 1
	# Structural bonuses take effect right away.
	while hire_pool.size() < hire_pool_size() and TreeDB.effect_at(id, "hire_pool", 1) > 0.0:
		hire_pool.append(_new_candidate())
	while contracts.size() < contract_count() and TreeDB.effect_at(id, "contracts", 1) > 0.0:
		contracts.append(make_contract(rng.randi_range(1, max_threat())))
	_changed()
	return true


func nodes_affordable() -> int:
	var n := 0
	for id in TreeDB.all_ids():
		if can_buy_node(id):
			n += 1
	return n


## Data Shards for a finished mission (see DESIGN.md "Data Shards").
func shards_for(outcome: String, threat: int, encounters_cleared: int) -> int:
	var regular := encounters_cleared - (1 if outcome == "success" else 0)
	var base := 0.0
	match outcome:
		"success":
			base = regular + 3 + floori((threat - 1) / 2.0) + tree_bonus("boss_shards")
		"extracted":
			base = regular
		_:
			base = maxi(1, floori(regular / 2.0))
	return int(round(base * (1.0 + tree_bonus("shard_pct"))))


# --- offline income --------------------------------------------------------

## Credits side-gig income for the time since the last save; emits offline_income.
func accrue_offline() -> void:
	var now := int(Time.get_unix_time_from_system())
	var away := now - last_seen_unix
	if last_seen_unix <= 0 or away < GIG_MIN_AWAY or gig_rate() <= 0.0:
		return
	var capped := mini(away, int(gig_cap_hours() * 3600.0))
	var amount := int(floor(gig_rate() * capped / 60.0))
	if amount <= 0:
		return
	offline_pending += amount
	offline_seconds = away
	last_seen_unix = now
	save_game()  # stamps the time, so the same stretch is never paid twice
	offline_income.emit()


func collect_offline() -> int:
	var n := offline_pending
	if n <= 0:
		return 0
	eddies += n
	offline_pending = 0
	offline_seconds = 0
	_changed()
	return n


# --- crew ----------------------------------------------------------------

func refresh_hire_pool() -> void:
	hire_pool = []
	for i in hire_pool_size():
		hire_pool.append(_new_candidate())


func _new_candidate() -> Dictionary:
	var r := UnitDB.make_runner(UnitDB.random_class(rng), rng)
	# Higher rep brings better candidates.
	if rng.randf() < rep * 0.04:
		r.level += 1
	return r


func reroll_hire_pool() -> bool:
	if eddies < HIRE_REROLL_COST:
		return false
	eddies -= HIRE_REROLL_COST
	refresh_hire_pool()
	_changed()
	return true


func hire(index: int) -> bool:
	if index < 0 or index >= hire_pool.size():
		return false
	var r: Dictionary = hire_pool[index]
	var cost := hire_cost(r)
	if eddies < cost:
		return false
	eddies -= cost
	hire_pool.remove_at(index)
	roster.append(r)
	if squad.size() < squad_max():
		squad.append(r.id)
	_changed()
	return true


func dismiss(id: String) -> void:
	roster = roster.filter(func(r): return r.id != id)
	squad.erase(id)
	_ensure_not_stuck()
	_changed()


## Returns false when the squad is full.
func toggle_squad(id: String) -> bool:
	if id in squad:
		squad.erase(id)
	elif squad.size() < squad_max():
		squad.append(id)
	else:
		return false
	_changed()
	return true


## Never leave the player with nobody to send and no money to hire.
func _ensure_not_stuck() -> void:
	if not roster.is_empty():
		return
	var cheapest := 1 << 30
	for r in hire_pool:
		cheapest = mini(cheapest, hire_cost(r))
	if eddies < cheapest:
		var kid := UnitDB.make_runner(UnitDB.random_class(rng), rng, false)
		kid.name = kid.name + " (street kid)"
		roster.append(kid)
		squad.append(kid.id)


# --- deck ----------------------------------------------------------------

func is_equipped(id: String) -> bool:
	return id in deck_active or id in deck_passive


## Equip or unequip. Returns false when no slot is free.
func toggle_equip(id: String) -> bool:
	if not id in owned_soft:
		return false
	var active := SoftDB.is_active(id)
	var deck: Array = deck_active if active else deck_passive
	var slots := active_slots if active else passive_slots
	if id in deck:
		deck.erase(id)
	elif deck.size() < slots:
		deck.append(id)
	else:
		return false
	_changed()
	return true


func buy_soft(id: String) -> bool:
	var cost := soft_price(id)
	if eddies < cost or id in owned_soft:
		return false
	eddies -= cost
	owned_soft.append(id)
	market.erase(id)
	# Auto-equip into a free slot for convenience.
	var active := SoftDB.is_active(id)
	if active and deck_active.size() < active_slots:
		deck_active.append(id)
	elif not active and deck_passive.size() < passive_slots:
		deck_passive.append(id)
	_changed()
	return true


## Next upgrade price for "active" or "passive" slots, or -1 when maxed.
func slot_upgrade_price(kind: String) -> int:
	if kind == "active":
		var n := active_slots - 4
		return ACTIVE_SLOT_PRICES[n] if n < ACTIVE_SLOT_PRICES.size() else -1
	var m := passive_slots - 2
	return PASSIVE_SLOT_PRICES[m] if m < PASSIVE_SLOT_PRICES.size() else -1


func buy_slot(kind: String) -> bool:
	var p := slot_upgrade_price(kind)
	if p < 0 or eddies < p:
		return false
	eddies -= p
	if kind == "active":
		active_slots += 1
	else:
		passive_slots += 1
	_changed()
	return true


func refresh_market() -> void:
	var pool := SoftDB.all_ids().filter(func(id): return not id in owned_soft)
	pool.shuffle()
	market = pool.slice(0, MARKET_SIZE)


# --- contracts -----------------------------------------------------------

func contract_count() -> int:
	return CONTRACT_COUNT + int(tree_bonus("contracts"))


func refresh_contracts() -> void:
	contracts = []
	var top := max_threat()
	for i in contract_count():
		# Spread offers: one easier, one at the top, one random.
		var threat := clampi(top - 1, 1, 5) if i == 0 else (top if i == 1 else rng.randi_range(1, top))
		contracts.append(make_contract(threat))


func make_contract(threat: int) -> Dictionary:
	var target: String = TARGETS[rng.randi() % TARGETS.size()]
	var encounters := []
	var pool := UnitDB.enemy_pool(threat)
	for e in 3 + threat:
		var group := []
		var size := rng.randi_range(2, mini(5, 2 + floori(threat / 2.0) + floori(e / 2.0)))
		for n in size:
			group.append(pool[rng.randi() % pool.size()])
		encounters.append(group)
	# Boss encounter with a couple of guards.
	var boss_group := ["cyberpsycho"]
	for n in mini(threat, 3):
		boss_group.append(pool[rng.randi() % pool.size()])
	encounters.append(boss_group)
	return {
		"title": JOBS[rng.randi() % JOBS.size()] % target,
		"client": CLIENTS[rng.randi() % CLIENTS.size()],
		"target": target,
		"district": DISTRICTS[rng.randi() % DISTRICTS.size()],
		"threat": threat,
		"reward": int(round(120 * threat * rng.randf_range(0.8, 1.2))),
		"encounters": encounters,  # Array[Array[enemy kind]]; last one has the boss
	}


func can_start_mission() -> bool:
	return not squad_runners().is_empty()


func start_mission(index: int) -> void:
	if index < 0 or index >= contracts.size() or not can_start_mission():
		return
	current_contract = contracts[index]
	mission_requested.emit()


func finish_mission(result: Dictionary) -> void:
	var c := current_contract
	var threat := int(c.get("threat", 1))
	var outcome: String = result.get("outcome", "wiped")
	var summary := {
		"outcome": outcome, "title": c.get("title", ""), "threat": threat,
		"bag": 0, "reward": 0, "rep": 0, "soft_drop": "", "flatlined": [], "level_ups": [],
		"shards": shards_for(outcome, threat, int(result.get("encounters_cleared", 0))),
		"kills": int(result.get("kills", 0)), "duration": float(result.get("duration", 0.0)),
	}
	var squad_ids := squad.duplicate()
	if outcome == "wiped":
		for id in squad_ids:
			var r := get_runner(id)
			if not r.is_empty():
				summary.flatlined.append(r.name)
		roster = roster.filter(func(r): return not r.id in squad_ids)
		squad = []
		# Insurance Policy: a courier saves part of the bag.
		summary.bag = int(floor(int(result.get("bag", 0)) * minf(1.0, tree_bonus("wipe_keep"))))
		eddies += summary.bag
	else:
		summary.bag = int(result.get("bag", 0))
		eddies += summary.bag
		if outcome == "success":
			summary.reward = int(round(int(c.get("reward", 0)) * (1.0 + tree_bonus("reward_pct"))))
			summary.rep = threat
			eddies += summary.reward
			rep += threat
			if rng.randf() < SOFT_DROP_CHANCE + tree_bonus("drop_pct"):
				var pool := SoftDB.all_ids().filter(func(id): return not id in owned_soft)
				if not pool.is_empty():
					summary.soft_drop = pool[rng.randi() % pool.size()]
					owned_soft.append(summary.soft_drop)
		# XP for everyone who went.
		var xp := 15 * threat * (int(result.get("encounters_cleared", 0)) + (2 if outcome == "success" else 0))
		xp = int(round(xp * (1.0 + tree_bonus("xp_pct"))))
		for id in squad_ids:
			var r := get_runner(id)
			if r.is_empty():
				continue
			r.xp += xp
			while r.level < UnitDB.MAX_LEVEL and r.xp >= UnitDB.xp_to_next(r.level):
				r.xp -= UnitDB.xp_to_next(r.level)
				r.level += 1
				summary.level_ups.append("%s -> L%d" % [r.name, r.level])
	shards += int(summary.shards)
	missions_run += 1
	last_result = summary
	current_contract = {}
	refresh_contracts()
	refresh_market()
	refresh_hire_pool()
	_ensure_not_stuck()
	save_game()
	mission_finished.emit()
	state_changed.emit()


func _changed() -> void:
	save_game()
	state_changed.emit()
