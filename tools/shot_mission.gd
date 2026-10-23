extends SceneTree
## Dev tool: runs a fight and saves screenshots of combat, the EXEC targeting slow-mo, an
## intel sheet, the boss telegraph and the end panel. Needs rendering (run WITHOUT --headless):
##   godot --path . --script res://tools/shot_mission.gd -- <out_prefix> [threat] [node: fight|elite|boss]
## Writes <out_prefix>_combat.png, _target.png, _intel.png, _late.png, _end.png
## NOTE: this resets user://save.json.

var _out := "/tmp/fight"
var _threat := 2
var _type := "fight"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_threat = int(args[1])
	if args.size() > 2:
		_type = args[2]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		_unpause()


## The fight auto-pauses when the window loses focus (mobile / tab switch); tools run unfocused.
var _m: Node = null
var _hold_pause := false


func _unpause() -> void:
	if _m and not _hold_pause:
		_m.paused = false


func _shot(name: String) -> void:
	await _frames(2)
	root.get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved %s_%s.png" % [_out, name])


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await _frames(1)


func _run() -> void:
	# macOS stops presenting frames for occluded windows: keep the capture window on top.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(360, 640)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var game: Node = root.get_node("Game")
	game.new_game()
	game.run = RunState.create(game.make_contract(_threat), game.fixer_stats(), 4242)
	var run: RunState = game.run
	run.choose_draft(0)
	run.crew[0].implants = ["kerenzikov"]
	run.threads[1] = ["on_dodge", "sel_self", "firewall", ""]
	run.spare.append("on_low")
	# Pick a node of the wanted type and jump there.
	var target := -1
	for n in run.map:
		if n.type == _type:
			target = n.id
			break
	run.pos = -1
	run.phase = "map"
	run.node(target).row = 0  # make it reachable from the start
	run.enter(target)
	var m: Node = load("res://scenes/mission.tscn").instantiate()
	root.add_child(m)
	_m = m
	await _frames(5)
	var sim: CombatSim = m.sim
	m.speed_idx = 2
	var guard := 0
	while guard < 1500:
		await _frames(1)
		guard += 1
		var casting := false
		for e in sim.enemies():
			casting = casting or (e.is_casting() and e.cast_t < e.cast_total * 0.6)
		if sim.time > 9.0 and (casting or sim.time > 18.0):
			break
	m.speed_idx = 0
	await _wait(0.3)
	await _shot("combat")
	m._on_exec(2)
	await _wait(0.5)
	var foes := sim.enemies()
	if not foes.is_empty():
		m.hover_id = foes[0].id
	await _shot("target")
	m._auto_target()
	await _frames(4)
	await _wait(0.2)
	if not foes.is_empty():
		m._open_info(foes[foes.size() - 1].id)
	await _wait(0.3)
	await _shot("intel")
	m._close_info()
	m.speed_idx = 2
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and sim.outcome == "":
		await _frames(1)
		for u in sim.mercs():
			u.hp = maxf(u.hp, u.max_hp * 0.4)
	_hold_pause = true
	m.paused = true
	await _wait(0.3)
	await _shot("late")
	_hold_pause = false
	m.paused = false
	while sim.outcome == "":
		for u in sim.mercs():
			u.hp = u.max_hp
		sim.step(0.5)
		await _frames(1)
	await _wait(2.6)
	await _shot("end")
	quit()
