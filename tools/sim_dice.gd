extends SceneTree
## Headless balance harness: plays whole runs (draft -> map -> dice fights -> target) with a bot.
## Usage: godot --headless --path . --script res://tools/sim_dice.gd -- [runs] [threat] [policy] [tree]
##   threat 0 = 1..5, policy: random | greedy | smart | all (default), tree: none | mid | full.
## Columns: win% | fights (avg won) | reach (map row) | trace (end) | traced% | turns (per fight) |
##   downs (merc downs per run) | hacks (per fight) | intr (intents cancelled per run)

const MAX_TURNS := 40

## Roughly 30 runs of shards.
const TREE_MID := {"core": 1, "n_ram": 3, "n_regen": 2, "n_hack": 1, "n_cool": 1,
	"c_hp": 2, "c_armor": 1, "c_patch": 2, "i_xp": 3, "i_shards": 2, "b_reward": 2}

var game: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 20
	var only := int(args[1]) if args.size() > 1 else 0
	var policy: String = args[2] if args.size() > 2 else "all"
	var tree: String = args[3] if args.size() > 3 else "none"
	game = load("res://scripts/game.gd").new()
	game.rng.seed = 12345
	game.tree_ranks = TREE_MID.duplicate() if tree == "mid" else {}
	if tree == "full":
		for id in TreeDB.all_ids():
			game.tree_ranks[id] = TreeDB.max_rank(id)
	print("Dice run harness: %d runs per cell, tree %s" % [runs, tree])
	print("%-7s %-3s %6s %6s %6s %6s %7s %6s %6s %6s %6s" % ["policy", "T", "win%", "fights", "reach", "trace", "traced%", "turns", "downs", "hacks", "intr"])
	var policies := ["random", "greedy", "smart"] if policy == "all" else [policy]
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
	var turns := 0
	var n_fights := 0
	var downs := 0
	var hacks := 0
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
				turns += int(res.turns)
				hacks += int(res.hacks)
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
	print("%-7s %-3d %5d%% %6.1f %6.1f %6.0f %6d%% %6.1f %6.1f %6.1f %6.1f" % [policy, threat, 100 * wins / runs,
		float(fights) / runs, float(reach) / runs, trace / runs, 100 * traced / runs,
		float(turns) / maxf(1, n_fights), float(downs) / runs, float(hacks) / maxf(1, n_fights), float(intr) / runs])


## Map / node decisions (same for every policy so only the fights differ).
func _step(r: RunState, policy: String) -> void:
	match r.phase:
		"map":
			var opts := r.reachable()
			var best: int = opts[0]
			for id in opts:
				var t: String = r.node(id).type
				if t in ["safehouse", "subnet"] and (r.trace > 45.0 or _crew_hp(r) < 0.6):
					best = id
			r.enter(best)
		"loot":
			var opts: Array = r.pending.loot
			for i in opts.size():
				var o: Dictionary = opts[i]
				if o.kind == "chip" or o.kind == "scrap":
					r.take_loot(i)
					_slot_spare(r, policy)
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
				_slot_spare(r, policy)
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


## New chips go into free slots (the random policy never edits its deck).
func _slot_spare(r: RunState, policy: String) -> void:
	if policy == "random":
		return
	var i := r.spare.size() - 1
	var list := r.slots_of(ChipDB.kind(r.spare[i]))
	var free := list.find("")
	if free >= 0:
		r.place_chip(free, i)


func _crew_hp(r: RunState) -> float:
	var t := 0.0
	for m in r.crew:
		t += float(m.hp_pct)
	return t / maxf(1, r.crew.size())


func _fight(r: RunState, policy: String) -> Dictionary:
	var c := DiceCombat.new()
	var fx: Dictionary = game.fixer_stats()
	fx.trace = r.trace
	c.setup(r.pending.fight, r.crew, r.hacks, r.daemons, fx, r.rng.randi())
	var hacks := 0
	while c.outcome == "" and c.turn < MAX_TURNS:
		DiceBot.play_turn(c, policy)
		for ev in c.pop_events():
			if ev.type == "hack":
				hacks += 1
	if c.outcome == "":
		c.outcome = "wiped"
	var res := c.result()
	res.hacks = hacks
	return res
