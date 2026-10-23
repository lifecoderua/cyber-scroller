extends SceneTree
## Headless balance harness: plays whole runs (draft -> map -> fights -> boss) with a bot.
## Usage: godot --headless --path . --script res://tools/sim_mission.gd -- [runs] [threat] [policy] [tree]
##   threat 0 = 1..5, policy: "idle" (never touches EXEC, takes loot 0) | "bot" (fires manual
##   threads on their own selector, takes the first loot that fits) | both (default),
##   tree: "none" | "mid" | "full".
## Columns: win% | fights (avg won) | reach (avg map row reached) | trace (avg at end) |
##   traced% | f_dur (avg fight seconds) | downs (merc downs per run) | intr (interrupts/run)

const DT := 1.0 / 20.0
const MAX_FIGHT := 400.0

const TREE_MID := {"core": 1, "n_ram": 4, "n_regen": 4, "n_hack": 2, "n_boot": 1, "n_cool": 2, "c_dmg": 4,
	"c_hp": 4, "c_crit": 1, "c_armor": 2, "c_patch": 2, "c_trauma": 1, "i_xp": 3, "i_shards": 2, "i_scout": 1}

var game: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 20
	var only := int(args[1]) if args.size() > 1 else 0
	var policy: String = args[2] if args.size() > 2 else "both"
	var tree: String = args[3] if args.size() > 3 else "none"
	game = load("res://scripts/game.gd").new()
	game.rng.seed = 12345
	game.tree_ranks = TREE_MID.duplicate() if tree == "mid" else {}
	if tree == "full":
		for id in TreeDB.all_ids():
			game.tree_ranks[id] = TreeDB.max_rank(id)
	print("Run harness: %d runs per cell, tree %s" % [runs, tree])
	print("%-6s %-3s %6s %6s %6s %6s %7s %6s %6s %6s" % ["policy", "T", "win%", "fights", "reach", "trace", "traced%", "f_dur", "downs", "intr"])
	var policies := ["idle", "bot"] if policy == "both" else [policy]
	for p in policies:
		for threat in range(1, 6):
			if only > 0 and threat != only:
				continue
			_cell(p, threat, runs)
	game.free()
	quit()


func _cell(policy: String, threat: int, runs: int) -> void:
	var wins := 0
	var traced := 0
	var fights := 0
	var reach := 0
	var trace := 0.0
	var dur := 0.0
	var n_fights := 0
	var downs := 0
	var intr := 0
	for n in runs:
		var r := RunState.create(game.make_contract(threat), game.fixer_stats(), 1000 + n * 17 + threat)
		r.choose_draft(n % r.drafts.size())
		var guard := 0
		while r.phase != "over" and guard < 60:
			guard += 1
			_step(r, policy)
			if r.phase == "fight":
				var res := _fight(r, policy)
				dur += float(res.duration)
				n_fights += 1
				intr += int(res.interrupts)
				for c in res.crew:
					downs += 1 if c.down else 0
				r.finish_fight(res)
		reach += r.current_row()
		fights += r.fights_won
		trace += r.trace
		if r.outcome == "won":
			wins += 1
		elif r.outcome == "traced":
			traced += 1
	print("%-6s %-3d %5d%% %6.1f %6.1f %6.0f %6d%% %6.0f %6.1f %6.1f" % [policy, threat, 100 * wins / runs,
		float(fights) / runs, float(reach) / runs, trace / runs, 100 * traced / runs,
		dur / maxf(1, n_fights), float(downs) / runs, float(intr) / runs])


## Map / node decisions: the bot heads for fights early, rests late.
func _step(r: RunState, policy: String) -> void:
	match r.phase:
		"map":
			var opts := r.reachable()
			var best: int = opts[0]
			for id in opts:
				var t: String = r.node(id).type
				if policy == "bot" and t in ["safehouse", "subnet"] and (r.trace > 50.0 or _crew_hp(r) < 0.6):
					best = id
			r.enter(best)
		"loot":
			var opts: Array = r.pending.loot
			for i in opts.size():
				var o: Dictionary = opts[i]
				if o.kind == "chip" or o.kind == "scrap":
					r.take_loot(i)
					return
				for m in r.crew.size():
					var fit := r.fit_preview(o.ref, m)
					if fit.ok and fit.replaces != "?" and not fit.warn:
						r.take_loot(i, m)
						return
			r.skip_loot()
		"subnet":
			if r.trace > 35.0:
				r.subnet_scrub()
			else:
				r.subnet_take(0)
		"safehouse":
			r.safehouse_heal()
		"event":
			var res := r.event_choose(0)
			if res.get("denied", false):
				r.event_choose(EventDB.get_event(r.pending.event).choices.size() - 1)
		"fence", "ripper":
			r.complete_node()
	var p := r.perk_pending()
	if p >= 0:
		r.choose_perk(p, UnitDB.perk_choices(r.crew[p])[0].id)


func _crew_hp(r: RunState) -> float:
	var t := 0.0
	for m in r.crew:
		t += float(m.hp_pct)
	return t / maxf(1, r.crew.size())


func _fight(r: RunState, policy: String) -> Dictionary:
	var sim := CombatSim.new()
	var fx: Dictionary = game.fixer_stats()
	fx.trace = r.trace
	sim.setup(r.pending.fight, r.crew, r.threads, fx, r.rng.randi())
	while sim.outcome == "" and sim.time < MAX_FIGHT:
		sim.step(DT)
		if policy == "bot":
			for i in sim.deck.threads.size():
				if sim.deck.is_manual(i) and sim.deck.block_reason(i) == "":
					sim.deck.execute(i, -1)
		sim.pop_events()
	if sim.outcome == "":
		sim.outcome = "wiped"
	return sim.result()
