extends SceneTree
## Dev tool: renders the run screens and saves screenshots. Run WITHOUT --headless.
##   godot --path . --script res://tools/shot_run.gd -- <out_prefix> [screens...]
## Screens: draft map preview loot deck crew fence ripper subnet safehouse event over
## (default: all). NOTE: this resets user://save.json.

const ALL := ["draft", "map", "preview", "loot", "deck", "crew", "fence", "ripper", "subnet", "safehouse", "event", "over"]

var _out := "/tmp/run"


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	root.get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved %s_%s.png" % [_out, name])


func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(360, 640)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var want: Array = args.slice(1) if args.size() > 1 else ALL
	var game: Node = root.get_node("Game")
	game.new_game()
	await _frames(30)
	for s in want:
		var run := RunState.create(game.make_contract(2), game.fixer_stats(), 777)
		game.run = run
		if s != "draft":
			run.choose_draft(0)
			run.crew[0].implants = ["kerenzikov", "gorilla_arms", "synaptic"]
			run.crew[0].scars = 1
			run.crew[1].weapon = "smart_rifle"
			run.crew[1].hp_pct = 0.55
			run.spare.append_array(["dodge_relay", "spoof", "breach+", "ice_sentry"])
			run.hacks[3] = "ping"
		match s:
			"map", "preview", "deck", "crew":
				run.pos = run.reachable()[0]
				run.node(run.pos).done = true
				run.trace = 23.0
			"loot":
				run.pos = run.reachable()[0]
				run.last_fight = {"outcome": "won", "bag": 31, "kills": 7, "trace_gain": 6.0, "type": "fight", "downed": 1, "duration": 52.0}
				run.pending = {"loot": run._loot_options(run.node(run.pos), {"killed_kinds": ["netrunner", "ganger"], "fried": 0, "kills": 7}, false)}
				run.phase = "loot"
			"fence", "ripper", "subnet", "safehouse", "event":
				var id := -1
				for n in run.map:
					if n.type == s and id < 0:
						id = n.id
				if id < 0:
					id = run.map[1].id
					run.map[1].type = s
					if s == "event":
						run.map[1].event = "toll"
				run.pos = id
				run.phase = "map"
				run.node(id).row = 0
				run.pos = -1
				run.eddies = 140
				run.enter(id)
				if run.crew.size() < 3 and s == "fence":
					pass
			"over":
				run.outcome = "won"
				run.phase = "over"
				run.fights_won = 6
				run.kills = 41
				run.trace = 64.0
		var scene: Node = load("res://scenes/run.tscn").instantiate()
		root.add_child(scene)
		await _frames(20)
		match s:
			"preview":
				scene._preview(run.reachable()[0], true)
				await _frames(20)
			"loot":
				scene._view._select(0)
				await _frames(5)
			"deck":
				scene.open_deck()
				await _frames(10)
				var ed: Node = scene._overlay
				ed._on_spare(ed.run.spare.size() - 2)
				await _frames(10)
			"crew":
				scene.open_crew()
				await _frames(15)
		await _shot(s)
		scene.queue_free()
		await _frames(2)
	game.run = null
	quit()
