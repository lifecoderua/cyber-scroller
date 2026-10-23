extends Node
## Autoload "Game": persistent meta state (shards, rep, skill tree, stash), the active
## run (RunState), contracts, save/load, and screen switching.
##
## Screens talk to each other only through this node:
##   hub    -> Game.start_run(contract_index)        screen "run" (crew draft)
##   run    -> Game.begin_fight()                    screen "fight"
##   fight  -> Game.finish_fight(sim.result())       screen "run" (loot / map / results)
##   run    -> Game.end_run(extract_items)           screen "hub" (debrief)
##
## Meta progression: Data Shards buy ranks in the fixer skill tree (TreeDB). Every bonus
## is read through tree_bonus(key); run and fight bonuses travel in fixer_stats().

signal state_changed
signal screen_requested(screen: String)
## Kept for the Audio autoload: fired when a fight starts / ends.
signal mission_requested
signal mission_finished

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3  # v3: roguelite runs (run, stash); v2 keeps shards, rep, tree
const CONTRACT_COUNT := 3

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

var rep := 0
var runs_played := 0
var runs_won := 0
var shards := 0
var tree_ranks: Dictionary = {}
var stash: Array = []           # item refs extracted from won runs
var contracts: Array = []
var run: RunState = null
var last_result: Dictionary = {}  # debrief for the hub; cleared by the hub
var screen := "hub"


func _ready() -> void:
	rng.randomize()
	if not load_game():
		new_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			save_game()


# --- lifecycle ---------------------------------------------------------------------

func new_game() -> void:
	rep = 0
	runs_played = 0
	runs_won = 0
	shards = 0
	tree_ranks = {}
	stash = []
	run = null
	last_result = {}
	refresh_contracts()
	save_game()
	state_changed.emit()


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION, "rep": rep, "runs_played": runs_played, "runs_won": runs_won,
		"shards": shards, "tree_ranks": tree_ranks, "stash": stash, "contracts": contracts,
		"run": run.to_dict() if run != null else null,
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
	var ver := int(data.get("version", 0))
	if ver < 1 or ver > SAVE_VERSION:
		return false
	# Older saves: keep the meta (rep, shards, skill tree); the roster game is gone.
	rep = int(data.get("rep", 0))
	shards = int(data.get("shards", 0))
	runs_played = int(data.get("runs_played", data.get("missions_run", 0)))
	runs_won = int(data.get("runs_won", 0))
	tree_ranks = {}
	var tr = data.get("tree_ranks", {})
	if typeof(tr) == TYPE_DICTIONARY:
		for k in tr:
			if not TreeDB.def(k).is_empty():
				tree_ranks[k] = clampi(int(tr[k]), 0, TreeDB.max_rank(k))
	stash = (data.get("stash", []) as Array).filter(func(s): return not ItemDB.get_def(String(s)).is_empty())
	contracts = []
	if ver >= 3:
		contracts = data.get("contracts", [])
		for c in contracts:
			c.threat = int(c.threat)
		# A run closed mid-fight resumes at the start of that fight (start_screen()).
		if typeof(data.get("run")) == TYPE_DICTIONARY:
			run = RunState.from_dict(data.run)
	if contracts.is_empty():
		refresh_contracts()
	return true


# --- screens -------------------------------------------------------------------------

func goto(s: String) -> void:
	screen = s
	screen_requested.emit(s)


## Where the game should open: an unfinished run resumes.
func start_screen() -> String:
	if run == null:
		return "hub"
	return "fight" if run.phase == "fight" else "run"


# --- queries -------------------------------------------------------------------------

func max_threat() -> int:
	return mini(5, 1 + floori(rep / 4.0) + int(tree_bonus("threat_bonus")))


## Rep needed for the next threat tier, or -1 when threat 5 is unlocked.
func next_threat_rep() -> int:
	var mt := max_threat()
	return -1 if mt >= 5 else (mt - int(tree_bonus("threat_bonus"))) * 4


func stash_cap() -> int:
	return RunState.STASH_BASE + int(tree_bonus("stash_slots"))


func extract_count() -> int:
	return 1 + int(tree_bonus("extract_items"))


## Everything the run and the fights read from the skill tree.
func fixer_stats() -> Dictionary:
	var keys := ["max_ram", "start_ram", "hack_power", "hack_disc", "heat_cap", "slots", "ram_on_kill",
		"gear_dmg", "merc_hp", "rerolls", "front_shield", "blank_shield", "patch_pct", "revive",
		"enemy_hp", "trace_pct", "bounty_pct", "start_eddies", "fence_disc", "skip_pct",
		"loot_options", "subnet_bonus", "crew_offers", "reveal"]
	var s := {}
	for k in keys:
		s[k] = tree_bonus(k)
	s.full_ram = tree_bonus("full_ram") > 0.0
	return s


## Fight stats: tree bonuses plus the run's live Trace.
func fight_stats() -> Dictionary:
	var s := fixer_stats()
	if run != null:
		s.trace = run.trace
	return s


# --- skill tree ------------------------------------------------------------------------

func tree_rank(id: String) -> int:
	return int(tree_ranks.get(id, 0))


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


## Data Shards for a finished run (see DESIGN.md "Payout").
func shards_for(outcome: String, threat: int, fights: int) -> int:
	var base := 0.0
	if outcome == "won":
		base = (fights - 1) + 3 + (threat - 1) + tree_bonus("boss_shards")
	else:
		base = maxi(1, floori(fights / 2.0)) * (1.0 + tree_bonus("fail_shards"))
	return int(round(base * (1.0 + tree_bonus("shard_pct"))))


# --- contracts ---------------------------------------------------------------------------

func contract_count() -> int:
	return CONTRACT_COUNT + int(tree_bonus("contracts"))


func refresh_contracts() -> void:
	contracts = []
	var top := max_threat()
	for i in contract_count():
		var threat := clampi(top - 1, 1, 5) if i == 0 else (top if i == 1 else rng.randi_range(1, top))
		contracts.append(make_contract(threat))


func make_contract(threat: int) -> Dictionary:
	var target: String = TARGETS[rng.randi() % TARGETS.size()]
	return {
		"title": JOBS[rng.randi() % JOBS.size()] % target,
		"client": CLIENTS[rng.randi() % CLIENTS.size()],
		"target": target,
		"district": DISTRICTS[rng.randi() % DISTRICTS.size()],
		"threat": threat,
		"shards": shards_for("won", threat, 6),
	}


# --- run flow ----------------------------------------------------------------------------

func start_run(index: int) -> void:
	if run != null or index < 0 or index >= contracts.size():
		return
	run = RunState.create(contracts[index], fixer_stats())
	_changed()
	goto("run")


## Crew pick; `stash_index` (-1 = none) moves a stash item onto crew member `target`.
func choose_draft(i: int, stash_index := -1, target := -1) -> bool:
	if run == null:
		return false
	var item := ""
	if stash_index >= 0 and stash_index < stash.size():
		item = stash[stash_index]
	if not run.choose_draft(i, item, target):
		return false
	if run.stash_taken != "":
		stash.remove_at(stash_index)
	_changed()
	return true


func begin_fight() -> void:
	if run == null or run.phase != "fight":
		return
	save_game()
	mission_requested.emit()
	goto("fight")


func finish_fight(result: Dictionary) -> void:
	if run == null:
		goto("hub")
		return
	run.finish_fight(result)
	_changed()
	mission_finished.emit()
	goto("run")


func abandon_run() -> void:
	if run == null:
		return
	run.abandon()
	_changed()


## Close a finished run. `extract` = crew item refs to keep in the stash (won runs only).
func end_run(extract: Array = []) -> void:
	if run == null:
		goto("hub")
		return
	var o := run.outcome
	var won := o == "won"
	var summary := {
		"outcome": o, "title": run.contract.get("title", ""), "threat": run.threat,
		"shards": shards_for(o, run.threat, run.fights_won), "rep": run.threat if won else 0,
		"fights": run.fights_won, "kills": run.kills, "trace": int(run.trace), "extracted": [],
		"crew": run.crew.map(func(m): return m.name),
	}
	if won:
		rep += run.threat
		runs_won += 1
		for ref in extract.slice(0, extract_count()):
			if stash.size() < stash_cap():
				stash.append(ref)
				summary.extracted.append(ref)
	shards += int(summary.shards)
	runs_played += 1
	last_result = summary
	run = null
	refresh_contracts()
	_changed()
	goto("hub")


func stash_discard(i: int) -> void:
	if i >= 0 and i < stash.size():
		stash.remove_at(i)
		_changed()


## Save after any run edit made by a screen (deck, loot, node actions).
func run_changed() -> void:
	_changed()


func _changed() -> void:
	save_game()
	state_changed.emit()
