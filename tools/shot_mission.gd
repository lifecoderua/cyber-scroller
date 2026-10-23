extends SceneTree
## Dev tool: runs a dice fight and saves screenshots: the roll phase, a selected die with its
## targets, a hack being aimed, a later turn and the end panel. Needs rendering (run WITHOUT
## --headless):
##   godot --path . --script res://tools/shot_mission.gd -- <out_prefix> [threat] [node: fight|elite|boss]
## Writes <out_prefix>_roll.png, _die.png, _hack.png, _late.png, _end.png
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


func _shot(name: String) -> void:
	await _frames(3)
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
	run.daemons[1] = "dodge_relay"
	run.hacks[3] = "breach"
	var target := -1
	for n in run.map:
		if n.type == _type:
			target = n.id
			break
	run.pos = -1
	run.phase = "map"
	run.node(target).row = 0
	run.enter(target)
	var m: Node = load("res://scenes/mission.tscn").instantiate()
	root.add_child(m)
	await _wait(1.0)
	var c: DiceCombat = m.c
	c.dice[0].locked = true
	await _shot("roll")
	m._on_done()
	await _frames(2)
	var pick := -1
	for d in c.live_dice():
		if DiceDB.is_damage(d.face()) and not c.valid_targets(d).is_empty():
			pick = d.index
			break
	if pick >= 0:
		m._on_die(m.die_views.filter(func(x): return x.get_meta("die") == pick)[0])
	await _wait(0.4)
	await _shot("die")
	m.sel_die = -1
	m._on_hack(0)
	await _wait(0.4)
	await _shot("hack")
	m.hack_slot = -1
	m.targeting = -1
	for i in 2:
		DiceBot.play_turn(c, "smart")
		m._drain()
		await _wait(2.5)
		if c.outcome != "":
			break
	await _shot("late")
	while c.outcome == "":
		for u in c.mercs():
			u.hp = u.max_hp
		DiceBot.play_turn(c, "smart")
		m._drain()
		m.instant = true
		await _frames(3)
	await _wait(2.5)
	await _shot("end")
	quit()
