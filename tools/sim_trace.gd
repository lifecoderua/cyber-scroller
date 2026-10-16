extends SceneTree
## Dev tool: prints a timeline of one CombatSim run without casting (debugging balance).
##   godot --headless --path . --script res://tools/sim_trace.gd -- [threat] [seed]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var threat := int(args[0]) if args.size() > 0 else 1
	var seed := int(args[1]) if args.size() > 1 else 7
	var game: Node = load("res://scripts/game.gd").new()
	game.rng.seed = seed
	var runners := [UnitDB.make_runner("solo", game.rng, false), UnitDB.make_runner("gunner", game.rng, false)]
	game.roster = runners
	game.squad = runners.map(func(r): return r.id)
	game.deck_passive = ["ram_expansion"]
	var sim := CombatSim.new()
	sim.setup(game.make_contract(threat), runners, [], game.fixer_stats(), seed)
	var next := 0.0
	var dealt := {}
	while sim.outcome == "" and sim.time < 600.0:
		sim.step(0.1)
		for ev in sim.pop_events():
			if ev.type == "damage":
				var u := sim.get_unit(ev.target)
				var k := "to_runners" if u.team == CombatSim.RUNNER else "to_enemies"
				dealt[k] = dealt.get(k, 0.0) + ev.amount
			elif ev.type in ["encounter_start", "encounter_cleared", "death"]:
				print("%6.1f %s %s" % [sim.time, ev.type, str(ev)])
		if sim.time >= next:
			next += 5.0
			var line := "%6.1f anchor=%.0f " % [sim.time, sim.anchor]
			for u in sim.units:
				if u.alive:
					line += "%s[x=%.0f hp=%.0f t=%d eng=%s] " % [u.kind, u.x, u.hp, u.target, u.engaged]
			print(line, " dealt=", dealt)
	print("outcome ", sim.outcome, " t=", sim.time)
	game.free()
	quit()
