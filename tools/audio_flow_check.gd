extends SceneTree
## Dev tool: smoke-tests the Audio autoload (headless OK): background generation finishes,
## every sound plays, fight hooks (pause muffle, boss music, mute button), mute persistence.
## Backs up and restores user://save.json and user://settings.cfg.
##   godot --headless --path . --script res://tools/audio_flow_check.gd

const FILES := ["user://save.json", "user://settings.cfg"]

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


func _run() -> void:
	var backups := {}
	for f in FILES:
		backups[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null
	var audio: Node = root.get_node("Audio")
	var game: Node = root.get_node("Game")
	# Start unmuted whatever settings.cfg says (restored at the end).
	audio.set_sfx_muted(false)
	audio.set_music_muted(false)

	# 1. Background generation.
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while frames < 3000:
		await process_frame
		frames += 1
		if audio._gen_queue.is_empty() and audio._gen_cur == "" and audio._next_music_gen() == null:
			break
	print("generation: %d frames, %d ms wall" % [frames, Time.get_ticks_msec() - t0])
	_check(audio._streams.size() == SfxPresets.all().size(), "all SFX generated (%d)" % audio._streams.size())
	for t in ["hub", "mission", "boss"]:
		_check(audio._music.has(t) and audio._music[t].done and audio._music[t].muffled != null, "music '%s' ready" % t)

	# 2. Every sound plays without errors.
	for n in SfxPresets.all():
		audio._last_play.erase(n)
		audio.play(n)

	# 3. Fight hooks.
	game.new_game()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	_check(audio._music_want == "hub", "hub music in hub")
	game.start_run(0)
	await _frames(3)
	game.choose_draft(0)
	game.run.enter(game.run.reachable()[0])
	game.begin_fight()
	await _frames(5)
	var m: Node = main.get_child(main.get_child_count() - 1)
	_check(audio._mission == m, "fight scene attached")
	_check(audio._music_want == "mission", "mission music wanted")
	_check(is_instance_valid(audio._mission_btn) and audio._mission_btn.is_inside_tree(), "mute button in the fight top bar")
	m.paused = true
	await create_timer(0.6).timeout
	_check(audio._frozen and audio._muffle > 0.9, "pause -> music muffled (%.2f)" % audio._muffle)
	m.paused = false
	await create_timer(0.6).timeout
	_check(not audio._frozen and audio._muffle < 0.1, "unpause -> music clear (%.2f)" % audio._muffle)
	m.targeting = 2
	await _frames(2)
	_check(audio._frozen, "EXEC targeting counts as frozen")
	m.targeting = -1
	# Feed synthetic events through the audio hook.
	var sim: CombatSim = m.sim
	for u in sim.units:
		audio.on_sim_event({"type": "attack", "src": u.id, "target": u.id, "ranged": not u.melee, "missed": false})
	for ev in [
		{"type": "damage", "target": 0, "amount": 10.0, "absorbed": 0.0, "crit": true, "kind": "melee", "src": 0, "color": Color.WHITE},
		{"type": "payload", "thread": 0, "slot": 2, "chip": "shock", "targets": [], "color": Color("7ae8ff")},
		{"type": "skill", "unit": 0, "skill": "sandevistan", "x": 0.0, "radius": 0.0, "targets": []},
		{"type": "telegraph", "unit": 0, "name": "aim", "duration": 3.0, "target": 0},
		{"type": "interrupt", "unit": 0, "thread": 2},
		{"type": "overheat"},
		{"type": "loot", "unit": 0, "amount": 12},
		{"type": "wave_start", "index": 2, "total": 3, "boss": true},
	]:
		audio.on_sim_event(ev)
	_check(audio._music_want == "boss", "boss wave -> boss music")
	audio.toggle_all()
	_check(audio.sfx_muted and audio.music_muted, "mute button mutes all")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_check(cfg.get_value("audio", "music_muted", false) == true, "mute persisted to settings.cfg")
	audio.toggle_all()
	_check(not audio.sfx_muted and not audio.music_muted, "toggle again unmutes")
	await _frames(70)

	# 4. Back to the run; spending eddies plays 'purchase'.
	sim.outcome = "won"
	m._show_end()
	await _frames(3)
	m._on_continue()
	await _frames(5)
	_check(audio._music_want == "hub", "hub music after the fight")
	audio._last_play.erase("purchase")
	game.run.eddies -= 10
	game.run_changed()
	await _frames(1)
	_check(audio._last_play.has("purchase"), "spending run eddies plays 'purchase'")
	var rs: Node = main.get_child(main.get_child_count() - 1)
	rs._open_menu()
	await _frames(2)
	var found := false
	for b in rs.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("MUSIC:"):
			found = true
	_check(found, "run menu has SFX/MUSIC toggles")

	# Restore files.
	for f in FILES:
		if backups[f] != null:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_string(backups[f])
			fa.close()
		elif FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("AUDIO CHECK: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
