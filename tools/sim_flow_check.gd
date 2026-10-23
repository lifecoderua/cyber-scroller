extends SceneTree
## Dev tool: smoke-tests a whole run through main.tscn (headless OK):
## hub -> job -> crew draft -> map -> dice fight scene -> loot / node screens -> ... -> target
## -> run over -> hub debrief. The first fight's first turn uses the scene's own taps
## (reroll, dice, a hack, END TURN); the rest is played by the smart bot.
## Backs up and restores user://save.json.
##   godot --headless --path . --script res://tools/sim_flow_check.gd

const SAVE := "user://save.json"

var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _screen(main: Node) -> Node:
	return main.get_child(main.get_child_count() - 1)


func _run() -> void:
	var backup := FileAccess.get_file_as_string(SAVE) if FileAccess.file_exists(SAVE) else ""
	var game: Node = root.get_node("Game")
	game.new_game()
	game.stash = ["kevlar"]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	_check(_screen(main).name == "Hub", "hub loaded")
	game.start_run(0)
	await _frames(5)
	_check(_screen(main).name == "Run" and game.run.phase == "draft", "run scene, draft phase")
	_check(game.choose_draft(0, 0, 0), "draft with a stash item")
	_check(game.stash.is_empty() and game.run.stash_taken == "kevlar", "stash item moved onto the crew")
	var nodes := 0
	var fights := 0
	while game.run != null and game.run.phase != "over" and nodes < 30:
		var run: RunState = game.run
		var screen: Node = _screen(main)
		match run.phase:
			"map":
				var opts := run.reachable()
				screen._enter(opts[nodes % opts.size()])
				nodes += 1
				await _frames(3)
				if game.run.phase == "fight":
					await create_timer(0.8).timeout  # jack-in transition
			"fight":
				if _screen(main).name != "Mission":
					game.begin_fight()
					await _frames(3)
				var m: Node = _screen(main)
				_check(m.name == "Mission", "fight scene for node %d" % run.pos)
				m.instant = true
				var c: DiceCombat = m.c
				# The first turn goes through the scene's own buttons and taps.
				if fights == 0:
					m._on_reroll()
					m._on_done()
					for dv in m.die_views:
						var d: DiceCombat.Die = c.dice[dv.get_meta("die")]
						var ts := c.valid_targets(d)
						if ts.is_empty():
							continue
						m._on_die(dv)
						if ts.size() == 1 and ts[0] == d.owner:
							m._on_die(dv)
						else:
							m._on_unit_tapped(ts[0])
						await _frames(1)
					m._on_hack(0)
					var hts: Array = c.hack_targets(0) if c.hacks.size() > 0 else []
					if not hts.is_empty() and m.hack_slot == 0:
						m._on_unit_tapped(hts[0])
					m._on_done()
					await _frames(2)
				var guard := 0
				while c.outcome == "" and guard < 80:
					# Keep the crew alive so the flow reaches the target.
					for u in c.mercs():
						u.hp = maxi(u.hp, int(ceil(u.max_hp * 0.6)))
					c.trace = minf(c.trace, 60.0)
					DiceBot.play_turn(c, "smart")
					m._drain()
					guard += 1
					await _frames(2)
				await _frames(5)
				await create_timer(1.4).timeout
				_check(m.end_panel != null, "fight %d ended (%s, %d kills, %d turns)" % [fights, c.outcome, c.kills, c.turn])
				m._on_continue()
				fights += 1
				await _frames(4)
			"loot":
				screen._view._select(0)
				var o: Dictionary = run.pending.loot[0]
				if o.kind == "item":
					var placed := false
					for i in run.crew.size():
						var fit := run.fit_preview(o.ref, i)
						if fit.ok and fit.replaces != "?":
							screen._view._take(i, -1)
							placed = true
							break
					if not placed:
						screen._view._skip()
				else:
					screen._view._take(-1, -1)
				await _frames(2)
			"event":
				screen._view._choose(EventDB.get_event(run.pending.event).choices.size() - 1)
				await _frames(2)
				if game.run.phase == "fight":
					await create_timer(0.8).timeout
			_:
				run.complete_node()
				screen.changed()
				await _frames(2)
		if game.run != null and game.run.phase == "map":
			var p: int = game.run.perk_pending()
			if p >= 0:
				game.run.choose_perk(p, UnitDB.perk_choices(game.run.crew[p])[0].id)
	_check(game.run != null and game.run.outcome == "won", "run won after %d nodes, %d fights" % [nodes, fights])
	_check(_screen(main).name == "Run", "back on the run screen for the debrief")
	var items: Array = game.run.crew_items() if game.run else []
	var shards_before: int = game.shards
	game.end_run(items.slice(0, 1))
	await _frames(5)
	_check(_screen(main).name == "Hub", "back in hub")
	_check(game.shards > shards_before, "shards paid (%d)" % (game.shards - shards_before))
	_check(game.stash.size() == mini(1, items.size()), "item extracted to stash")
	_check(game.last_result.get("outcome", "") == "won", "debrief waiting in hub")
	# Save round-trip with a run in progress.
	game.start_run(0)
	await _frames(3)
	game.choose_draft(1)
	var d: Dictionary = game.run.to_dict()
	var r2 := RunState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(r2.crew.size() == game.run.crew.size() and r2.map.size() == game.run.map.size() and r2.reachable() == game.run.reachable(), "run survives a JSON save round-trip")
	if backup != "":
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("FLOW CHECK: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
