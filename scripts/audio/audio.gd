extends Node
## Audio autoload: procedural SFX (SfxSynth) + procedural synthwave loops (MusicGen).
##
##   Audio.play("hit")                    # name from SfxPresets, optional volume_db / pitch
##   Audio.set_music("mission")           # "hub" | "mission" | "boss" | "" (silence)
##   Audio.attach_mission(self)           # mission scene: pause whoosh, music filter, mute button
##   Audio.on_sim_event(ev)               # mission scene: CombatSim event -> SFX
##
## Everything is generated at startup in small jobs spread over frames (no threads, no
## assets). A sound requested before its turn is rendered on the spot.
## Web: audio stays silent until the first tap/click/key (browser autoplay policy); music
## starts then. The active-pause "muffle" is a pre-rendered low-passed copy of each loop
## crossfaded in sync, because web Sample playback does not support bus effects.

const SETTINGS_PATH := "user://settings.cfg"
const POOL_SIZE := 12
const GEN_BUDGET_USEC := 3000
const MUSIC_DB := -9.0
const MUSIC_FADE_TIME := 1.2
const MUFFLE_SPEED := 5.0       # 1/s, pause filter sweep speed
## Generated first: needed right away in the hub / on the first card tap.
const PRIORITY := ["ui_click", "ui_error", "pause_in", "pause_out", "hack_cast", "purchase", "hire",
	"shot", "pistol", "melee_slash", "hit", "crit", "enemy_death", "coin", "encounter_start"]

var sfx_muted := false
var music_muted := false

var _presets := {}
var _streams := {}               # name -> AudioStreamWAV
var _gen_queue: Array[String] = []
var _gen_cur := ""
var _gen_st := {}
var _gen_layer := 0
var _players: Array[AudioStreamPlayer] = []
var _last_play := {}             # name -> msec
var _unlocked := true
## Dummy driver (headless): run all logic but never start players. Nothing is audible
## anyway, and players still playing at quit make the engine report leaked playbacks.
var _dummy := false
var _rng := RandomNumberGenerator.new()

var _music := {}                 # track -> MusicGen
var _music_want := ""
var _decks: Array[Dictionary] = []   # {dry, muf, track, fade, target}
var _muffle := 0.0
var _duck := 1.0
var _duck_target := 1.0

var _mission: Node = null
var _frozen := false
var _mission_btn: Button = null
var _snap := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_unlocked = not OS.has_feature("web")
	_dummy = AudioServer.get_driver_name() == "Dummy"
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in 2:
		var d := AudioStreamPlayer.new()
		var m := AudioStreamPlayer.new()
		d.bus = "Music"
		m.bus = "Music"
		add_child(d)
		add_child(m)
		_decks.append({"dry": d, "muf": m, "track": "", "fade": 0.0, "target": 0.0})
	_load_settings()
	_presets = SfxPresets.all()
	for n in PRIORITY:
		if _presets.has(n):
			_gen_queue.append(n)
	for n in _presets:
		if not n in _gen_queue:
			_gen_queue.append(n)
	get_tree().node_added.connect(_on_node_added)
	var game := get_node_or_null("/root/Game")
	if game:
		game.state_changed.connect(_on_game_changed)
		game.mission_requested.connect(func(): set_music("mission"))
		game.mission_finished.connect(func():
			_duck_target = 1.0
			set_music("hub"))
		_snap = _snapshot()
	set_music("hub")


# --- public API ---------------------------------------------------------------------

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if sfx_muted or not _unlocked:
		return
	var rule: Array = SfxPresets.RULES.get(sound, SfxPresets.DEFAULT_RULE)
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -100000)) < int(rule[1]):
		return
	var stream := _get_stream(sound)
	if stream == null:
		return
	_last_play[sound] = now
	# Voice limiting: steal the oldest voice of this sound, else a free one, else the oldest.
	var same := 0
	var oldest_same: AudioStreamPlayer = null
	var free: AudioStreamPlayer = null
	var oldest: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			if free == null:
				free = p
			continue
		var t := int(p.get_meta("t", 0))
		if oldest == null or t < int(oldest.get_meta("t", 0)):
			oldest = p
		if p.get_meta("sfx", "") == sound:
			same += 1
			if oldest_same == null or t < int(oldest_same.get_meta("t", 0)):
				oldest_same = p
	var p: AudioStreamPlayer = oldest_same if same >= int(rule[0]) else (free if free else oldest)
	if p == null:
		return
	var pv := float(rule[2])
	p.stop()
	p.stream = stream
	p.volume_db = float(rule[3]) + volume_db
	p.pitch_scale = clampf(pitch * (1.0 + _rng.randf_range(-pv, pv)), 0.25, 4.0)
	p.set_meta("sfx", sound)
	p.set_meta("t", now)
	if not _dummy:
		p.play()


## Plays a sound after a delay (real time).
func play_later(sound: String, delay: float, volume_db := 0.0, pitch := 1.0) -> void:
	get_tree().create_timer(delay, true, false, true).timeout.connect(play.bind(sound, volume_db, pitch))


func set_music(track: String) -> void:
	_music_want = track
	if track != "" and not _music.has(track):
		_queue_music(track)
	_update_music_decks()


func set_sfx_muted(v: bool) -> void:
	sfx_muted = v
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), v)
	if v:
		for p in _players:
			p.stop()
	_save_settings()
	_refresh_mute_button()


func set_music_muted(v: bool) -> void:
	music_muted = v
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), v)
	if v:
		for d in _decks:
			_stop_deck(d)
	_save_settings()
	_update_music_decks()
	_refresh_mute_button()


## One-button toggle (mission top bar): mutes everything unless everything is muted.
func toggle_all() -> void:
	var mute := not (sfx_muted and music_muted)
	set_music_muted(mute)
	set_sfx_muted(mute)
	if not mute:
		play("ui_click")


## Row of SFX / MUSIC toggles for the hub SYS menu.
func mute_row(font_size := 12) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var sfx := HubW.button("", func(): pass, font_size, UITheme.CYAN)
	var mus := HubW.button("", func(): pass, font_size, UITheme.CYAN)
	for b in [sfx, mus]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var refresh := func():
		sfx.text = "SFX: " + ("OFF" if sfx_muted else "ON")
		mus.text = "MUSIC: " + ("OFF" if music_muted else "ON")
	refresh.call()
	sfx.pressed.connect(func():
		set_sfx_muted(not sfx_muted)
		refresh.call())
	mus.pressed.connect(func():
		set_music_muted(not music_muted)
		refresh.call())
	return row


## Hub results modal: debrief stingers.
func play_result(res: Dictionary) -> void:
	if String(res.get("outcome", "")) == "wiped":
		play("runner_down")
		return
	for i in 3:
		play_later("coin", 0.3 + i * 0.12, -2.0, 1.0 + i * 0.12)
	if not (res.get("level_ups", []) as Array).is_empty():
		play_later("level_up", 0.75)


# --- mission ---------------------------------------------------------------------------

func attach_mission(m: Node) -> void:
	_mission = m
	_frozen = false
	_duck_target = 1.0
	set_music("mission")
	_add_mission_button(m)


func on_sim_event(ev: Dictionary) -> void:
	var sim: CombatSim = _mission.get("sim") if is_instance_valid(_mission) else null
	match String(ev.get("type", "")):
		"attack":
			var a: CombatSim.Unit = sim.get_unit(ev.src) if sim else null
			if a == null:
				return
			if a.team == CombatSim.RUNNER:
				if a.melee:
					play("melee_slash")
				elif a.kind == "gunner":
					play("shot")
				else:
					play("pistol", -1.0, 1.15 if a.kind == "techie" else 1.0)
			else:
				if a.boss:
					play("melee_slash", 1.0, 0.6)
				elif a.melee:
					play("melee_slash", -3.0, 0.8)
				elif a.flying:
					play("pistol", -5.0, 1.4)
				else:
					play("pistol", -3.0, 0.78)
		"damage":
			var kind := String(ev.get("kind", ""))
			var t: CombatSim.Unit = sim.get_unit(ev.target) if sim else null
			var on_runner := t != null and t.team == CombatSim.RUNNER
			if float(ev.get("absorbed", 0.0)) > 0.0 and float(ev.absorbed) >= float(ev.amount) - 0.5:
				play("zap", -8.0, 1.8)
			elif kind == "charge":
				play("slam", 2.0, 0.8)
			elif kind == "dot":
				play("hit", -8.0, 1.4)
			elif ev.get("crit", false):
				play("crit")
			elif kind in ["melee", "ranged", "hack"]:
				play("hit", 2.0 if kind == "hack" else 0.0, 0.85 if on_runner else 1.0)
		"heal":
			if not ev.get("quiet", false):
				play("heal")
		"death":
			var u: CombatSim.Unit = sim.get_unit(ev.unit) if sim else null
			if u and u.team == CombatSim.RUNNER:
				play("runner_down")
			else:
				play("enemy_death")
				if u and u.boss:
					play("explosion", 2.0, 0.7)
		"loot":
			var n := clampi(floori(float(ev.get("amount", 1)) / 6.0) + 1, 1, 3)
			for i in n:
				play_later("coin", 0.25 + i * 0.09, 0.0, 1.0 + i * 0.1)
		"cast":
			var d: Dictionary = SoftDB.get_def(String(ev.get("soft", "")))
			var col: Color = ev.get("color", Color.WHITE)
			# Each soft gets its own chirp pitch from its color family.
			var pitch := 0.8 + col.h * 0.6 if col.s > 0.1 else 0.7
			play("hack_cast", 0.0, pitch)
			if d.has("heal"):
				play_later("heal", 0.05)
			elif d.has("shield"):
				play_later("shield", 0.05)
			elif d.has("stun"):
				play_later("zap", 0.05)
			elif d.has("boss_damage") or float(d.get("damage", 0.0)) >= 60.0:
				play_later("explosion", 0.08, -2.0, 1.2)
		"skill":
			match String(ev.get("skill", "")):
				"gorilla_slam":
					play("slam")
				"trauma_kit":
					play("heal", -2.0, 0.9)
				"shock_grenade":
					play("explosion")
					play_later("zap", 0.1, -2.0)
		"telegraph":
			var u: CombatSim.Unit = sim.get_unit(ev.unit) if sim else null
			play("telegraph", 2.0 if u and u.boss else 0.0, 0.8 if u and u.boss else 1.0)
		"interrupt":
			play("interrupted")
		"cast_fire":
			if String(ev.get("name", "")) == "berserk_charge":
				play("slam", 0.0, 0.9)
			else:
				play("zap", 0.0, 0.7)
		"enrage":
			play("enrage")
		"ice":
			play("zap", -4.0, 1.4)
		"encounter_start":
			if ev.get("boss", false):
				play("boss_warning")
				set_music("boss")
			else:
				play("encounter_start")
		"encounter_cleared":
			play("hire", -2.0, 1.12)
		"outcome":
			_duck_target = 0.45
			match String(ev.get("outcome", "")):
				"success":
					play("mission_success")
				"wiped":
					play("flatlined")
				"extracted":
					play("extract")


func _poll_mission() -> void:
	var frozen := false
	var targeting := false
	if is_instance_valid(_mission) and _mission.is_inside_tree():
		var sim: CombatSim = _mission.get("sim")
		targeting = int(_mission.get("targeting")) >= 0
		frozen = (bool(_mission.get("paused")) or targeting) and sim != null and sim.outcome == ""
	elif _mission != null:
		_mission = null
	if frozen != _frozen:
		_frozen = frozen
		if frozen:
			play("pause_in", -2.0 if targeting else 0.0)
		else:
			play("pause_out")


func _add_mission_button(m: Node) -> void:
	var pb := m.get("pause_btn") as Control
	if pb == null or pb.get_parent() == null:
		return
	var row := pb.get_parent()
	var b := UITheme.button("", toggle_all, 10)
	b.icon = _speaker_icon(false)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(26, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Sound on/off"
	row.add_child(b)
	row.move_child(b, 0)
	if row is Control:
		(row as Control).offset_left -= 30.0
	_mission_btn = b
	_refresh_mute_button()


func _refresh_mute_button() -> void:
	if not is_instance_valid(_mission_btn):
		return
	var all_muted := sfx_muted and music_muted
	_mission_btn.icon = _speaker_icon(all_muted)
	_mission_btn.modulate = Color(1, 0.5, 0.55, 0.8) if all_muted else Color.WHITE


## Tiny pixel-art speaker icon (the default font has no music glyph).
func _speaker_icon(muted: bool) -> ImageTexture:
	var rows := [
		"....#.....",
		"...##..#..",
		"#####...#.",
		"#####.#.#.",
		"#####.#.#.",
		"#####...#.",
		"...##..#..",
		"....#.....",
	] if not muted else [
		"....#.....",
		"...##.....",
		"#####.#..#",
		"#####..##.",
		"#####..##.",
		"#####.#..#",
		"...##.....",
		"....#.....",
	]
	var img := Image.create(10, 8, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in (rows[y] as String).length():
			if rows[y][x] == "#":
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


# --- hub ---------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var g := get_node_or_null("/root/Game")
	if g == null:
		return {}
	return {"eddies": g.eddies, "roster": g.roster.size(), "runs": g.missions_run}


## Purchases and hires are detected from Game state diffs (no hooks in every tab).
func _on_game_changed() -> void:
	var s := _snapshot()
	if not _snap.is_empty() and int(s.runs) == int(_snap.runs) and not is_instance_valid(_mission):
		if int(s.roster) > int(_snap.roster):
			play("hire")
		elif int(s.eddies) < int(_snap.eddies):
			play("purchase")
	_snap = s


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("no_click"):
		n.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play("ui_click")


# --- frame loop ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		_unlocked = true
		_update_music_decks()


func _process(delta: float) -> void:
	_generate(GEN_BUDGET_USEC)
	_poll_mission()
	_muffle = move_toward(_muffle, 1.0 if _frozen else 0.0, delta * MUFFLE_SPEED)
	_duck = move_toward(_duck, _duck_target, delta * 0.8)
	for d in _decks:
		d.fade = move_toward(d.fade, d.target, delta / MUSIC_FADE_TIME)
		var dry: AudioStreamPlayer = d.dry
		var muf: AudioStreamPlayer = d.muf
		if d.fade <= 0.0 and d.target <= 0.0:
			if dry.playing:
				_stop_deck(d)
			continue
		# Equal-power crossfade between the dry loop and its low-passed twin, plus a dip.
		var k := float(d.fade) * _duck
		var m := _muffle
		dry.volume_db = MUSIC_DB + linear_to_db(maxf(0.0001, k * cos(m * PI * 0.5)))
		muf.volume_db = MUSIC_DB - 1.5 + linear_to_db(maxf(0.0001, k * sin(m * PI * 0.5)))


func _generate(budget: int) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget:
		# Order: priority SFX -> the music that is wanted now -> other SFX -> other loops.
		var sfx_left := _gen_cur != "" or not _gen_queue.is_empty()
		var in_priority := _gen_cur in PRIORITY or (not _gen_queue.is_empty() and _gen_queue[0] in PRIORITY)
		var want: MusicGen = _music.get(_music_want)
		var want_pending := want != null and not want.done and _unlocked and not music_muted
		if sfx_left and (in_priority or not want_pending):
			_gen_sfx_step()
			continue
		var g := _next_music_gen()
		if g == null:
			return
		g.step(maxi(500, budget - (Time.get_ticks_usec() - t0)))
		if g.done:
			if g.track != "mission":
				g.release()
			_update_music_decks()


## Renders one layer of the current SFX (or starts the next one).
func _gen_sfx_step() -> void:
	if _gen_cur == "":
		_gen_cur = _gen_queue.pop_front()
		if _streams.has(_gen_cur):
			_gen_cur = ""
			return
		_gen_st = SfxSynth.begin(_presets[_gen_cur])
		_gen_layer = 0
		return
	SfxSynth.step_layer(_gen_st, _gen_layer)
	_gen_layer += 1
	if _gen_layer >= SfxSynth.layer_count(_gen_st):
		_streams[_gen_cur] = SfxSynth.to_wav(SfxSynth.finish(_gen_st))
		_gen_cur = ""
		_gen_st = {}


func _get_stream(sound: String) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	if not _presets.has(sound):
		push_warning("Audio: unknown sound '%s'" % sound)
		_streams[sound] = null
		return null
	if _gen_cur == sound:
		while _gen_cur == sound:
			_gen_sfx_step()
	else:
		_gen_queue.erase(sound)
		_streams[sound] = SfxSynth.make(_presets[sound])
	return _streams[sound]


func _queue_music(track: String) -> void:
	if track == "boss":
		if not _music.has("mission"):
			_queue_music("mission")
		return  # created once the mission loop is done (it reuses that buffer)
	_music[track] = MusicGen.create(track)


## Wanted track first, then hub -> mission -> boss in the background.
func _next_music_gen() -> MusicGen:
	var order := [_music_want, "hub", "mission", "boss"]
	if _music_want == "boss":
		order = ["mission", "boss", "hub"]
	for t in order:
		if t == "":
			continue
		if not _music.has(t):
			if t == "boss":
				var base: MusicGen = _music.get("mission")
				if base == null or not base.done:
					continue
				_music[t] = MusicGen.create("boss", base)
			else:
				_queue_music(t)
		var g: MusicGen = _music[t]
		if not g.done:
			return g
	# All done: the mission float buffer is no longer needed once boss is built.
	if _music.has("boss") and _music.has("mission"):
		(_music.mission as MusicGen).release()
	return null


func _update_music_decks() -> void:
	if not _unlocked or music_muted:
		return
	var want := _music_want
	var g: MusicGen = _music.get(want)
	var ci := _active_deck()
	var cur: Dictionary = _decks[ci] if ci >= 0 else {}
	if want == "" or g == null or not g.done:
		# Boss not ready yet: keep whatever plays. Silence requested: fade out.
		if want == "" and ci >= 0:
			cur.target = 0.0
		return
	if ci >= 0 and cur.track == want:
		cur.target = 1.0
		return
	var pos := 0.0
	var quick := false
	if ci >= 0 and ((cur.track == "mission" and want == "boss") or (cur.track == "boss" and want == "mission")):
		# Same length and tempo: continue at the same spot for a seamless switch.
		pos = (cur.dry as AudioStreamPlayer).get_playback_position()
		quick = true
	var nd: Dictionary = _decks[1 if ci == 0 else 0]
	_stop_deck(nd)
	nd.track = want
	nd.fade = 0.6 if quick else 0.0
	nd.target = 1.0
	var dry: AudioStreamPlayer = nd.dry
	var muf: AudioStreamPlayer = nd.muf
	dry.stream = g.stream
	muf.stream = g.muffled
	dry.volume_db = -80.0
	muf.volume_db = -80.0
	if not _dummy:
		dry.play(pos)
		muf.play(pos)
	if ci >= 0:
		cur.target = 0.0


## Index of the deck currently fading in / playing, or -1.
func _active_deck() -> int:
	for i in _decks.size():
		if _decks[i].target > 0.0:
			return i
	return -1


func _stop_deck(d: Dictionary) -> void:
	(d.dry as AudioStreamPlayer).stop()
	(d.muf as AudioStreamPlayer).stop()
	d.fade = 0.0
	d.target = 0.0
	d.track = ""


# --- setup -----------------------------------------------------------------------------------

func _setup_buses() -> void:
	for bus in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sfx_muted = bool(cfg.get_value("audio", "sfx_muted", false))
		music_muted = bool(cfg.get_value("audio", "music_muted", false))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_muted)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep other sections if present
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.save(SETTINGS_PATH)


func _exit_tree() -> void:
	for g in _music.values():
		(g as MusicGen).cancel()
	_music.clear()
	# Stop playback so the AudioServer releases its stream playbacks before shutdown.
	for d in _decks:
		_stop_deck(d)
		(d.dry as AudioStreamPlayer).stream = null
		(d.muf as AudioStreamPlayer).stream = null
	for p in _players:
		p.stop()
		p.stream = null
