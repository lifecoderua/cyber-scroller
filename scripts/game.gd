extends Node
## Autoload "Game": persistent meta state, economy, save/load, contracts.
##
## Hub and mission talk to each other only through this node:
##   hub      -> Game.start_mission(contract_index)   (emits mission_requested)
##   mission  -> Game.finish_mission(result)          (emits mission_finished)
## Result dictionary from the mission:
##   {outcome: "success"|"extracted"|"wiped", bag: int, kills: int,
##    encounters_cleared: int, downed: Array[runner_id], duration: float}

signal state_changed
signal mission_requested
signal mission_finished

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const SQUAD_MAX := 3
const HIRE_POOL_SIZE := 4
const HIRE_REROLL_COST := 20
const MARKET_SIZE := 4
const ACTIVE_SLOT_PRICES := [400, 800]
const PASSIVE_SLOT_PRICES := [500, 1000]
const BASE_MAX_RAM := 10.0
const BASE_RAM_REGEN := 0.7
const SOFT_DROP_CHANCE := 0.4

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


func _ready() -> void:
	rng.randomize()
	if not load_game():
		new_game()


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
	refresh_hire_pool()
	refresh_contracts()
	refresh_market()
	save_game()
	state_changed.emit()


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"eddies": eddies, "rep": rep, "missions_run": missions_run,
		"roster": roster, "squad": squad, "hire_pool": hire_pool,
		"owned_soft": owned_soft, "deck_active": deck_active, "deck_passive": deck_passive,
		"active_slots": active_slots, "passive_slots": passive_slots,
		"contracts": contracts, "market": market,
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
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
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
	return mini(5, 1 + rep / 4)


## Combined fixer stats from the passive deck and squad (used by the mission).
func fixer_stats() -> Dictionary:
	var s := {
		"max_ram": BASE_MAX_RAM, "ram_regen": BASE_RAM_REGEN, "dmg_pct": 0.0, "regen": 0.0,
		"ram_on_kill": 0.0, "bounty_pct": 0.0, "hack_pct": 0.0, "ice_sentry": false,
		"autopilot": false,
	}
	var regen_pct := 0.0
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


# --- crew ----------------------------------------------------------------

func refresh_hire_pool() -> void:
	hire_pool = []
	for i in HIRE_POOL_SIZE:
		var r := UnitDB.make_runner(UnitDB.random_class(rng), rng)
		# Higher rep brings better candidates.
		if rng.randf() < rep * 0.04:
			r.level += 1
		hire_pool.append(r)


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
	var cost := UnitDB.hire_cost(r)
	if eddies < cost:
		return false
	eddies -= cost
	hire_pool.remove_at(index)
	roster.append(r)
	if squad.size() < SQUAD_MAX:
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
	elif squad.size() < SQUAD_MAX:
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
		cheapest = mini(cheapest, UnitDB.hire_cost(r))
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
	var cost := SoftDB.price(id)
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

func refresh_contracts() -> void:
	contracts = []
	var top := max_threat()
	for i in 3:
		# Spread offers: one easier, one at the top, one random.
		var threat := clampi(top - 1, 1, 5) if i == 0 else (top if i == 1 else rng.randi_range(1, top))
		contracts.append(make_contract(threat))


func make_contract(threat: int) -> Dictionary:
	var target: String = TARGETS[rng.randi() % TARGETS.size()]
	var encounters := []
	var pool := UnitDB.enemy_pool(threat)
	for e in 3 + threat:
		var group := []
		var size := rng.randi_range(2, mini(5, 2 + threat / 2 + e / 2))
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
	else:
		summary.bag = int(result.get("bag", 0))
		eddies += summary.bag
		if outcome == "success":
			summary.reward = int(c.get("reward", 0))
			summary.rep = threat
			eddies += summary.reward
			rep += threat
			if rng.randf() < SOFT_DROP_CHANCE:
				var pool := SoftDB.all_ids().filter(func(id): return not id in owned_soft)
				if not pool.is_empty():
					summary.soft_drop = pool[rng.randi() % pool.size()]
					owned_soft.append(summary.soft_drop)
		# XP for everyone who went.
		var xp := 15 * threat * (int(result.get("encounters_cleared", 0)) + (2 if outcome == "success" else 0))
		for id in squad_ids:
			var r := get_runner(id)
			if r.is_empty():
				continue
			r.xp += xp
			while r.level < UnitDB.MAX_LEVEL and r.xp >= UnitDB.xp_to_next(r.level):
				r.xp -= UnitDB.xp_to_next(r.level)
				r.level += 1
				summary.level_ups.append("%s -> L%d" % [r.name, r.level])
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
