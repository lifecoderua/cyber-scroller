extends SceneTree
## Dev tool: smoke-tests the Audio autoload (headless OK): background generation finishes,
## every sound plays, mission hooks (pause muffle, boss music, mute button), mute persistence.
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

	# 3. Mission hooks.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	_check(audio._music_want == "hub", "hub music wanted in hub")
	game.start_mission(0)
	await _frames(5)
	var m: Node = main.get_child(main.get_child_count() - 1)
	_check(audio._mission == m, "mission attached")
	_check(audio._music_want == "mission", "mission music wanted")
	_check(is_instance_valid(audio._mission_btn) and audio._mission_btn.is_inside_tree(), "mute button in mission top bar")
	m.paused = true
	await create_timer(0.6).timeout
	_check(audio._frozen and audio._muffle > 0.9, "pause -> music muffled (%.2f)" % audio._muffle)
	m.paused = false
	await create_timer(0.6).timeout
	_check(not audio._frozen and audio._muffle < 0.1, "unpause -> music clear (%.2f)" % audio._muffle)
	m.targeting = 0
	await _frames(2)
	_check(audio._frozen, "targeting freezes too")
	m.targeting = -1
	# Feed synthetic events through the mission's handler path.
	var sim: CombatSim = m.sim
	for u in sim.units:
		audio.on_sim_event({"type": "attack", "src": u.id, "target": u.id, "ranged": not u.melee, "missed": false})
	for ev in [
		{"type": "damage", "target": 0, "amount": 10.0, "absorbed": 0.0, "crit": true, "kind": "melee", "src": 0, "color": Color.WHITE},
		{"type": "cast", "slot": 0, "soft": "short_circuit", "target": 0, "color": Color("2de2e6")},
		{"type": "skill", "unit": 0, "skill": "shock_grenade", "x": 0.0, "radius": 50.0, "target": 0},
		{"type": "telegraph", "unit": 0, "name": "x", "duration": 1.0, "target": 0},
		{"type": "interrupt", "unit": 0},
		{"type": "loot", "unit": 0, "amount": 12},
		{"type": "encounter_start", "index": 4, "boss": true},
	]:
		audio.on_sim_event(ev)
	_check(audio._music_want == "boss", "boss encounter -> boss music")
	audio.toggle_all()
	_check(audio.sfx_muted and audio.music_muted, "mute button mutes all")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_check(cfg.get_value("audio", "music_muted", false) == true, "mute persisted to settings.cfg")
	audio.toggle_all()
	_check(not audio.sfx_muted and not audio.music_muted, "toggle again unmutes")
	await _frames(70)  # let the tween-free timers fire (coins etc.)

	# 4. Back to hub; purchase detection.
	m.sim.extract()
	m._drain_events()
	await create_timer(2.0).timeout
	m._on_continue()
	await _frames(5)
	_check(audio._music_want == "hub", "hub music after mission")
	var hub: Node = main.get_child(main.get_child_count() - 1)
	hub._open_menu()
	await _frames(2)
	var found := false
	for b in hub.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("MUSIC:"):
			found = true
	_check(found, "SYS menu has SFX/MUSIC toggles")
	var before: int = game.eddies
	audio._last_play.erase("purchase")
	game.reroll_hire_pool()
	await _frames(1)
	_check(game.eddies >= before or audio._last_play.has("purchase"), "spending eddies plays 'purchase'")

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
