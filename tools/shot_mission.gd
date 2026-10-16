extends SceneTree
## Dev tool: runs the mission scene and saves screenshots of combat, the targeting pause
## and the end overlay. Needs rendering (run WITHOUT --headless):
##   godot --path . --script res://tools/shot_mission.gd -- <out_prefix> [threat] [width]
## Writes <out_prefix>_combat.png, _target.png, _boss.png, _end.png

var _out := "/private/tmp/claude-501/mission"
var _threat := 1
var _width := 640


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_threat = int(args[1])
	if args.size() > 2:
		_width = int(args[2])
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, name])
	print("saved %s_%s.png" % [_out, name])


func _run() -> void:
	root.size = Vector2i(_width * 2, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		push_error("Game autoload missing")
		quit(1)
		return
	game.current_contract = game.make_contract(_threat)
	if game.deck_active.size() < 4 and not "firewall" in game.deck_active:
		game.deck_active.append("firewall")
	var m: Node = load("res://scenes/mission.tscn").instantiate()
	root.add_child(m)
	await _frames(5)
	print("stage: started")
	var sim: CombatSim = m.sim
	# Walk into the first fight and let it develop.
	m.speed_idx = 2
	var guard := 0
	while not sim.in_combat() and guard < 2000:
		await _frames(1)
		guard += 1
	guard = 0
	print("stage: combat ", sim.time)
	while guard < 600:
		await _frames(1)
		guard += 1
		var engaged := false
		for u in sim.enemies():
			if u.engaged:
				engaged = true
		if engaged and guard > 200:
			break
	m.speed_idx = 0
	await _wait(0.3)
	await _shot("combat")
	# Targeting pause.
	m._on_card(0)
	await _wait(0.5)
	var foes := sim.enemies()
	if not foes.is_empty():
		m.hover_id = foes[0].id
	await _shot("target")
	if not foes.is_empty():
		m._cast_on(foes[0].id)
	await _frames(6)
	await _shot("cast")
	# Fast-forward to the boss with a cheat-y heal loop so the squad survives.
	while sim.outcome == "" and sim.active_encounter != sim.total_encounters() - 1:
		for r in sim.runners():
			r.hp = r.max_hp
		sim.step(0.5)
		await _frames(1)
	print("stage: boss ", sim.time)
	m.speed_idx = 2
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and sim.outcome == "":
		await _frames(1)
		for r in sim.runners():
			r.hp = maxf(r.hp, r.max_hp * 0.5)
		var boss_casting := false
		for e in sim.enemies():
			if e.boss and e.is_casting() and e.cast_t < e.cast_total * 0.5:
				boss_casting = true
		if boss_casting:
			break
	m.paused = true
	await _wait(0.4)
	await _shot("boss")
	m.paused = false
	while sim.outcome == "":
		for r in sim.runners():
			r.hp = r.max_hp
		sim.step(0.5)
		await _frames(1)
	await _wait(3.0)
	await _shot("end")
	quit()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout
