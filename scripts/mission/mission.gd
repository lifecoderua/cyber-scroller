extends Node2D
## Fight scene (portrait): owns a CombatSim, renders the battle strip on top and the
## fixer's HUD below it (crew cards, deck threads, EXEC). Sim time = real delta * speed;
## 0 while paused / hit-stop / an info sheet is open, 25% while picking an EXEC target.
## See docs/DESIGN.md "Combat HUD".

const UnitView := preload("res://scripts/mission/unit_view.gd")
const FxLayer := preload("res://scripts/mission/fx_layer.gd")
const ThreadRow := preload("res://scripts/mission/thread_row.gd")
const CrewCard := preload("res://scripts/mission/crew_card.gd")
const DeckMeters := preload("res://scripts/mission/deck_meters.gd")
const ProgressPips := preload("res://scripts/mission/progress_pips.gd")
const ScreenFx := preload("res://scripts/mission/screen_fx.gd")
const FallbackBackdrop := preload("res://scripts/mission/fallback_backdrop.gd")

const BACKDROP_PATH := "res://scripts/art/city_backdrop.gd"
const MAIN_SCENE := "res://scenes/main.tscn"
const STREET_Y := 292.0
const WORLD_Y := -40.0           # backdrop shifted up: street sits low in the strip
const TOP_H := 44.0
const STRIP_BOTTOM := 300.0      # battle strip: y in [TOP_H, STRIP_BOTTOM]
const CAM_LEAD := 0.42           # front merc sits at this fraction of the screen width
const HITSTOP := 0.12
const SLOWMO := 0.25
const SPEEDS := [1, 2, 3]
const PICK_PAD := 16.0

var sim: CombatSim
var world: Node2D
var backdrop: Node2D
var units_layer: Node2D
var fx: FxLayer
var views := {}

var hud: CanvasLayer
var ui: Control
var tint_fx: ScreenFx
var front_fx: ScreenFx
var meters: DeckMeters
var pips: ProgressPips
var bag_label: Label
var pause_btn: Button
var speed_btn: Button
var rows: Array = []
var cards: Array = []
var bottom_hint: Label
var prompt: PanelContainer
var prompt_label: Label
var pause_note: Label
var info_sheet: PanelContainer
var banner: Label
var banner_sub: Label
var end_panel: Control

var speed_idx := 0
var paused := false
var targeting := -1        # thread index while picking an EXEC target
var info_uid := -1
var hitstop := 0.0
var shake := 0.0
var cam_x := 0.0
var display_bag := 0
var outcome_delay := -1.0
var finished := false
var hover_id := -1
var _banner_tween: Tween
var _t := 0.0
var _last_exec_tap := {}   # thread -> msec, for double-tap = AUTO


func _ready() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	_ensure_run()
	var run: RunState = Game.run
	sim = CombatSim.new()
	sim.setup(run.pending.fight, run.crew, run.threads, Game.fight_stats())
	var vs := get_viewport_rect().size
	sim.spawn_ahead = maxf(CombatSim.DEFAULT_SPAWN_AHEAD, vs.x * (1.0 - CAM_LEAD) + 30.0)
	cam_x = sim.anchor - vs.x * CAM_LEAD
	_build_world()
	_build_hud()
	_sync_views()
	var n := run.node(run.pos)
	var info: Dictionary = RunState.NODE_INFO.get(String(run.pending.fight.get("type", "fight")), RunState.NODE_INFO.fight)
	_banner(String(info.name), info.color, "%s  ·  %d waves" % [String(run.contract.get("district", "")), sim.total_waves()], 2.0)
	if n.get("type", "") == "boss":
		_banner("THE TARGET", UITheme.RED, "Last fight of the job", 2.0)
	elif run.pending.fight.get("alert", false):
		_banner("SECURITY ALERT", UITheme.RED, "Trace %d%%+: a gunman joins every wave" % int(RunState.ALERT_TRACE), 2.0)
	Audio.attach_mission(self)


func _exit_tree() -> void:
	if sim and sim.deck:
		sim.deck.sim = null  # break the sim <-> deck reference cycle


## Started on its own (F6 / tools): make a throwaway run on a first fight.
func _ensure_run() -> void:
	if Game.run != null and Game.run.phase == "fight":
		return
	Game.run = RunState.create(Game.make_contract(1), Game.fixer_stats())
	Game.run.choose_draft(0)
	Game.run.enter(Game.run.reachable()[0])


# --- construction ---------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	if ResourceLoader.exists(BACKDROP_PATH):
		backdrop = load(BACKDROP_PATH).new()
	else:
		backdrop = FallbackBackdrop.new()
	world.add_child(backdrop)
	if backdrop.has_method("set_district"):
		backdrop.set_district(str(Game.run.contract.get("district", "Neon Row")))
	units_layer = Node2D.new()
	world.add_child(units_layer)
	fx = FxLayer.new()
	world.add_child(fx)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UITheme.get_theme()
	hud.add_child(ui)

	tint_fx = ScreenFx.new()
	tint_fx.mode = "tint"
	tint_fx.anchor_right = 1.0
	tint_fx.offset_top = TOP_H
	tint_fx.offset_bottom = STRIP_BOTTOM
	ui.add_child(tint_fx)

	# Top bar: meters on the left, sound / speed / pause and wave pips on the right.
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", _bar_box())
	bar.anchor_right = 1.0
	bar.offset_bottom = TOP_H
	ui.add_child(bar)
	meters = DeckMeters.new()
	meters.sim = sim
	meters.position = Vector2(6, 6)
	meters.size = Vector2(250, 32)
	bar.add_child(meters)
	var right := HBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 3)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -70
	right.offset_right = -4
	right.offset_top = 3
	right.offset_bottom = 23
	right.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(right)
	speed_btn = _btn("1x", _cycle_speed, 30)
	right.add_child(speed_btn)
	pause_btn = _btn("||", _toggle_pause, 30)
	right.add_child(pause_btn)
	pips = ProgressPips.new()
	pips.sim = sim
	pips.anchor_left = 1.0
	pips.anchor_right = 1.0
	pips.offset_left = -96
	pips.offset_right = -4
	pips.offset_top = 26
	pips.offset_bottom = 42
	bar.add_child(pips)

	bag_label = UITheme.label("€$ 0", 10, UITheme.YELLOW)
	bag_label.position = Vector2(6, TOP_H + 3)
	bag_label.add_theme_constant_override("outline_size", 3)
	ui.add_child(bag_label)

	# Fixer panel (everything below the strip).
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = STRIP_BOTTOM
	ui.add_child(panel)

	var crew_row := HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 4)
	crew_row.alignment = BoxContainer.ALIGNMENT_CENTER
	crew_row.anchor_right = 1.0
	crew_row.offset_left = 4
	crew_row.offset_right = -4
	crew_row.offset_top = STRIP_BOTTOM + 4
	crew_row.offset_bottom = STRIP_BOTTOM + 48
	crew_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(crew_row)
	for u in sim.mercs(false):
		var card: Control = CrewCard.new()
		card.setup(sim, u)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tapped.connect(_on_card)
		crew_row.add_child(card)
		cards.append(card)

	var deck_head := UITheme.label("CYBERDECK  //  %s" % ChipDB.CHASSIS.name.to_upper(), 8, UITheme.TEXT_DIM)
	deck_head.position = Vector2(8, STRIP_BOTTOM + 52)
	ui.add_child(deck_head)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.anchor_right = 1.0
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = STRIP_BOTTOM + 64
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(box)
	var fs := Game.fixer_stats()
	for i in sim.deck.threads.size():
		var row: Control = ThreadRow.new()
		row.sim = sim
		row.thread = i
		row.readout = ChipDB.readout(sim.deck.threads[i].chips, fs)
		row.exec_pressed.connect(_on_exec)
		row.tile_pressed.connect(_on_tile)
		box.add_child(row)
		rows.append(row)

	bottom_hint = UITheme.label("", 9, UITheme.TEXT_DIM)
	bottom_hint.anchor_top = 1.0
	bottom_hint.anchor_bottom = 1.0
	bottom_hint.anchor_right = 1.0
	bottom_hint.offset_top = -22
	bottom_hint.offset_left = 8
	bottom_hint.offset_right = -8
	bottom_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(bottom_hint)

	# Targeting prompt (thumb zone, bottom).
	prompt = PanelContainer.new()
	prompt.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.1, 0.13, 0.96), UITheme.CYAN, 1, 2, 6))
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.anchor_right = 1.0
	prompt.offset_left = 4
	prompt.offset_right = -4
	prompt.offset_top = -40
	prompt.offset_bottom = -4
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	prompt.add_child(ph)
	prompt_label = UITheme.label("", 10, UITheme.CYAN)
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.clip_text = true
	ph.add_child(prompt_label)
	ph.add_child(_btn("CANCEL", _cancel_target, 58))
	var auto := _btn("AUTO", _auto_target, 52)
	auto.tooltip_text = "Use the thread's own selector"
	ph.add_child(auto)
	prompt.visible = false
	ui.add_child(prompt)

	pause_note = UITheme.label("PAUSED", 14, UITheme.PURPLE)
	pause_note.add_theme_constant_override("outline_size", 4)
	pause_note.anchor_right = 1.0
	pause_note.offset_top = TOP_H + 4
	pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_note.visible = false
	ui.add_child(pause_note)

	banner = UITheme.label("", 20, UITheme.CYAN)
	banner.add_theme_constant_override("outline_size", 6)
	banner.anchor_right = 1.0
	banner.offset_top = TOP_H + 40
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	ui.add_child(banner)
	banner_sub = UITheme.label("", 10, UITheme.TEXT)
	banner_sub.add_theme_constant_override("outline_size", 4)
	banner_sub.anchor_right = 1.0
	banner_sub.offset_top = TOP_H + 68
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub.modulate.a = 0.0
	ui.add_child(banner_sub)

	info_sheet = PanelContainer.new()
	info_sheet.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.03, 0.08, 0.97), UITheme.CYAN, 1, 2, 10))
	info_sheet.anchor_top = 1.0
	info_sheet.anchor_bottom = 1.0
	info_sheet.anchor_right = 1.0
	info_sheet.offset_left = 4
	info_sheet.offset_right = -4
	info_sheet.offset_top = -(640 - STRIP_BOTTOM) + 4
	info_sheet.offset_bottom = -4
	info_sheet.visible = false
	info_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(info_sheet)

	front_fx = ScreenFx.new()
	front_fx.mode = "front"
	front_fx.anchor_right = 1.0
	front_fx.anchor_bottom = 1.0
	ui.add_child(front_fx)


func _bar_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.08, 0.95)
	s.border_color = UITheme.CYAN.darkened(0.55)
	s.border_width_bottom = 1
	return s


func _panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.025, 0.025, 0.06, 0.98)
	s.border_color = UITheme.CYAN.darkened(0.5)
	s.border_width_top = 1
	return s


func _btn(text: String, cb: Callable, w: float) -> Button:
	var b := UITheme.button(text, cb, 10)
	b.custom_minimum_size = Vector2(w, 22)
	b.focus_mode = Control.FOCUS_NONE
	return b


# --- main loop ------------------------------------------------------------------

func _effective_speed() -> float:
	if paused or info_uid >= 0 or hitstop > 0.0 or sim.outcome != "":
		return 0.0
	var s := float(SPEEDS[speed_idx])
	return s * SLOWMO if targeting >= 0 else s


func _process(delta: float) -> void:
	_t += delta
	hitstop = maxf(0.0, hitstop - delta)
	var sim_dt := delta * _effective_speed()
	if sim_dt > 0.0:
		sim.step(sim_dt)
	_drain_events()
	if targeting >= 0 and sim.deck.block_reason(targeting) not in ["", "ram"]:
		_cancel_target()
	_sync_views()
	var vs := get_viewport_rect().size
	# Follow the formation (not a charging melee merc) but keep the front merc on screen.
	var target := maxf(sim.anchor - vs.x * CAM_LEAD, sim.front_x() - vs.x + 70.0)
	cam_x = lerpf(cam_x, target, 1.0 - exp(-delta * 3.5))
	shake = move_toward(shake, 0.0, delta * 22.0)
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	world.position = Vector2(round(-cam_x + off.x), round(WORLD_Y + off.y))
	if backdrop.has_method("update_view"):
		backdrop.update_view(-world.position.x, Vector2(vs.x, 360))
	for id in views:
		var v: UnitView = views[id]
		var u := v.unit()
		v.highlight = 0
		v.hover = false
		if targeting >= 0 and u.alive:
			v.highlight = 1 if sim.deck.is_valid_target(targeting, id) else -1
			v.hover = id == hover_id
		elif info_uid == id:
			v.highlight = 1
		v.tick(sim_dt, delta)
	fx.tick(delta)
	_update_hud(delta)
	if outcome_delay > 0.0:
		outcome_delay -= delta
		if outcome_delay <= 0.0:
			_show_end()


func _sync_views() -> void:
	for u in sim.units:
		if not views.has(u.id):
			var v: UnitView = UnitView.new()
			v.setup(sim, u)
			units_layer.add_child(v)
			views[u.id] = v
			v.tick(0.0, 0.0)
	for id in views.keys():
		var v: UnitView = views[id]
		if v.gone:
			v.queue_free()
			views.erase(id)


func _update_hud(delta: float) -> void:
	tint_fx.tint = move_toward(tint_fx.tint, 1.0 if targeting >= 0 else 0.0, delta * 6.0)
	tint_fx.pause_tint = move_toward(tint_fx.pause_tint, 1.0 if (paused or info_uid >= 0) and targeting < 0 else 0.0, delta * 6.0)
	bag_label.text = "€$ %d" % display_bag
	speed_btn.text = "%dx" % SPEEDS[speed_idx]
	pause_btn.text = ">" if paused else "||"
	pause_note.visible = paused and targeting < 0 and info_uid < 0 and sim.outcome == ""
	prompt.visible = targeting >= 0
	bottom_hint.visible = targeting < 0
	meters.preview_cost = float(sim.deck.threads[targeting].stats.ram) if targeting >= 0 else 0.0
	for r in rows:
		r.selected = r.thread == targeting
	for c in cards:
		var u := sim.get_unit(c.uid)
		c.highlight = 1 if targeting >= 0 and u.alive and sim.deck.is_valid_target(targeting, c.uid) else 0
	bottom_hint.text = _hint_text()
	front_fx.queue_redraw()
	_draw_offscreen()


func _hint_text() -> String:
	if sim.outcome != "":
		return ""
	if sim.wave < 0:
		return "Wave %d/%d incoming..." % [mini(sim.next_wave + 1, sim.total_waves()), sim.total_waves()]
	var has_manual := false
	for i in sim.deck.threads.size():
		has_manual = has_manual or sim.deck.is_manual(i)
	return "Threads run on their own%s  ·  tap a unit for intel" % ("  ·  EXEC = manual" if has_manual else "")


## Arrows at the right edge for enemies beyond the screen.
func _draw_offscreen() -> void:
	var vs := get_viewport_rect().size
	for u in sim.enemies():
		var sx: float = u.x + world.position.x
		if sx > vs.x + 4.0:
			var y: float = STREET_Y + WORLD_Y + u.lane - (60.0 if u.flying else 24.0)
			front_fx.link(Vector2(vs.x - 14, y), Vector2(vs.x - 4, y), UITheme.RED, 2.0, 0.05)


# --- input ----------------------------------------------------------------------

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and sim and sim.outcome == "":
		paused = true


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			_on_exec(k - KEY_1)
		elif k == KEY_SPACE:
			_toggle_pause()
		elif k == KEY_ESCAPE:
			if info_uid >= 0:
				_close_info()
			else:
				_cancel_target()
		elif k == KEY_A and targeting >= 0:
			_auto_target()
		elif k == KEY_F:
			_cycle_speed()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if p.y < TOP_H or p.y > STRIP_BOTTOM:
			return
		if targeting >= 0:
			var id := _pick(p, true)
			if id >= 0:
				_execute_on(id)
			get_viewport().set_input_as_handled()
		elif sim.outcome == "":
			var id := _pick(p, false)
			if id >= 0:
				_open_info(id)
			elif info_uid >= 0:
				_close_info()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and targeting >= 0:
		hover_id = _pick(event.position, true)


## Unit under a screen position. valid_only: only legal targets for the pending EXEC.
func _pick(screen_pos: Vector2, valid_only: bool) -> int:
	var p := screen_pos - world.position
	var best := -1
	var best_d := INF
	for id in views:
		var v: UnitView = views[id]
		if not v.unit().alive:
			continue
		if valid_only and not sim.deck.is_valid_target(targeting, id):
			continue
		var half := Vector2(8.0, 12.0) * v.scale_px + Vector2(PICK_PAD, PICK_PAD)
		var d := (p - v.body_pos()).abs()
		if d.x <= half.x and d.y <= half.y:
			var score := d.x + d.y * 0.3
			if score < best_d:
				best_d = score
				best = id
	return best


func _on_exec(i: int) -> void:
	if finished or sim.outcome != "" or i < 0 or i >= sim.deck.threads.size():
		return
	if not sim.deck.is_manual(i):
		_toast("T%d runs on its own (%s)" % [i + 1, ChipDB.display_name(sim.deck.threads[i].chips[0])], UITheme.TEXT_DIM)
		return
	if targeting == i:
		# Second tap on the same EXEC: quick double-tap = AUTO, slower = cancel.
		if Time.get_ticks_msec() - int(_last_exec_tap.get(i, 0)) < 350:
			_auto_target()
		else:
			_cancel_target()
		return
	_close_info()
	var reason := sim.deck.block_reason(i)
	if reason != "":
		rows[i].deny()
		Audio.play("ui_error")
		var msg: String = {"ram": "NOT ENOUGH RAM", "cd": "THREAD CYCLING", "frozen": "DECK FROZEN", "dark": "THREAD IS DARK"}.get(reason, "")
		if msg != "":
			_toast(msg, UITheme.RED)
		return
	_last_exec_tap[i] = Time.get_ticks_msec()
	targeting = i
	hover_id = -1
	var payload := ""
	for d in sim.deck.threads[i].defs:
		if d.get("kind", "") == "payload":
			payload = String(d.name)
			break
	var team := sim.deck.first_team(i)
	prompt_label.text = "T%d: %s  ->  tap %s" % [i + 1, payload.to_upper(), "an ALLY" if team == "ally" else "an ENEMY"]


func _on_card(uid: int) -> void:
	if targeting >= 0:
		if sim.deck.is_valid_target(targeting, uid):
			_execute_on(uid)
		return
	_open_info(uid)


func _on_tile(i: int, slot: int) -> void:
	var ref: String = sim.deck.threads[i].chips[slot]
	if ref == "" or targeting >= 0:
		return
	_toast("%s: %s" % [ChipDB.display_name(ref), ChipDB.desc(ref)], ChipDB.color(ref))


func _execute_on(id: int) -> void:
	var i := targeting
	targeting = -1
	hover_id = -1
	if sim.deck.execute(i, id):
		hitstop = HITSTOP
		_drain_events()


func _auto_target() -> void:
	if targeting < 0:
		return
	var i := targeting
	targeting = -1
	hover_id = -1
	if sim.deck.execute(i, -1):
		hitstop = HITSTOP
		_drain_events()
	else:
		rows[i].deny()
		_toast("NO TARGET FOR THE SELECTOR", UITheme.RED)


func _cancel_target() -> void:
	targeting = -1
	hover_id = -1


func _toggle_pause() -> void:
	if sim.outcome != "":
		return
	paused = not paused


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


# --- unit intel sheet ---------------------------------------------------------------

func _open_info(uid: int) -> void:
	var u := sim.get_unit(uid)
	if u == null:
		return
	info_uid = uid
	for c in info_sheet.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	info_sheet.add_child(v)
	var head := HBoxContainer.new()
	var col := UITheme.GREEN if u.side() == CombatSim.MERC else UITheme.RED
	var title := UITheme.label(u.name.to_upper(), 14, col)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_btn("RESUME", _close_info, 70))
	v.add_child(head)
	var lines: Array[String] = []
	lines.append("HP %d / %d   armor %d" % [int(ceil(u.hp)), int(u.max_hp), int(u.armor)])
	if u.team == CombatSim.ENEMY:
		var e: Dictionary = UnitDB.ENEMIES.get(u.kind, {})
		lines.append("ROLE: %s" % String(e.get("role", "")).to_upper())
		lines.append(String(e.get("hint", "")))
		if u.affix != "":
			var a: Dictionary = UnitDB.AFFIXES[u.affix]
			lines.append("ELITE %s: %s" % [String(a.name).to_upper(), a.desc])
	elif u.merc_id != "":
		var c: Dictionary = UnitDB.CLASSES[u.kind]
		lines.append("%s  ·  %s" % [c.name, c.weapon])
		lines.append("SIGNATURE %s: %s" % [String(c.skill_name).to_upper(), c.skill_desc])
		var m := _merc_dict(u.merc_id)
		if not m.is_empty():
			var t := UnitDB.trait_def(m)
			if not t.is_empty():
				lines.append("TRAIT %s: %s" % [String(t.name).to_upper(), t.desc])
			lines.append("CHROME %d / %d%s" % [UnitDB.chrome_load(m), UnitDB.chrome_cap(m), "  OVER CAP: stress builds when hit" if float(u.stats.chrome_over) > 0 else ""])
			var gear := []
			for ref in [m.weapon, m.armor] + Array(m.implants):
				if ref != "":
					gear.append(ItemDB.display_name(ref))
			if not gear.is_empty():
				lines.append("GEAR: " + ", ".join(gear))
	else:
		lines.append("Deployed by the Techie. Your deck can buff it.")
	var st := []
	if u.stun > 0.0: st.append("stunned")
	if u.breach_t > 0.0: st.append("breached")
	if u.mark_t > 0.0: st.append("marked")
	if u.infect_t > 0.0: st.append("infected")
	if not u.dots.is_empty(): st.append("burning")
	if u.hijack_t > 0.0: st.append("hijacked")
	if u.is_casting(): st.append("telegraphing %s (%.1fs)" % [u.cast_name, u.cast_t])
	if not st.is_empty():
		lines.append("NOW: " + ", ".join(st))
	for ln in lines:
		var l := UITheme.label(ln, 10, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 300
		v.add_child(l)
	info_sheet.visible = true


func _merc_dict(id: String) -> Dictionary:
	for m in Game.run.crew:
		if m.id == id:
			return m
	return {}


func _close_info() -> void:
	info_uid = -1
	info_sheet.visible = false


# --- events -> juice --------------------------------------------------------------

func _drain_events() -> void:
	for ev in sim.pop_events():
		_handle(ev)


func _view(id) -> UnitView:
	return views.get(id, null)


func _face(v: UnitView) -> float:
	return -1.0 if v.unit().side() == CombatSim.ENEMY else 1.0


func _muzzle(v: UnitView) -> Vector2:
	if v.unit().flying:
		return v.body_pos() + Vector2(0, 4)
	return v.position + Vector2(7.0 * v.scale_px * _face(v), -12.5 * v.scale_px)


func _screen(world_pos: Vector2) -> Vector2:
	return world_pos + world.position


func _handle(ev: Dictionary) -> void:
	Audio.on_sim_event(ev)
	match ev.type:
		"attack":
			var a := _view(ev.src)
			var t := _view(ev.target)
			if a:
				a.on_attack()
			if a and t:
				var tp := t.body_pos() + Vector2(randf_range(-3, 3), randf_range(-6, 6))
				if ev.missed:
					tp += Vector2(_face(a) * 18.0, randf_range(-14, -8))
				var mine := a.unit().side() == CombatSim.MERC
				if ev.ranged:
					var col := UITheme.YELLOW if mine else Color("ff5a3a")
					match a.unit().kind:
						"medtech": col = UITheme.GREEN
						"techie", "turret_ally": col = UITheme.CYAN
						"sniper": col = Color("ffe066")
					fx.tracer(_muzzle(a), tp, col, 2.5 if a.unit().kind == "sniper" else 1.5)
					if not ev.missed:
						fx.burst(tp, col, 3, 40.0, 0.2, 1.0)
				else:
					fx.slash(tp, UITheme.MAGENTA if mine else Color("ff6a2a"), _face(a))
					if a.unit().boss:
						shake = maxf(shake, 2.5)
		"damage":
			var t := _view(ev.target)
			if t == null:
				return
			var u := t.unit()
			var amt := int(round(ev.amount))
			var kind: String = ev.kind
			var col := Color.WHITE
			var size := 10
			var txt := str(amt)
			match kind:
				"hack":
					col = ev.color
					size = 12
				"dot":
					col = ev.color
					size = 8
				"skill", "blast":
					col = ev.color
					size = 11
				"charge", "snipe":
					col = UITheme.RED
					size = 17
					txt = "%d!" % amt
			if ev.crit and not kind in ["charge", "snipe"]:
				col = UITheme.YELLOW
				size += 3
				txt = "%d!" % amt
			if u.team == CombatSim.MERC and kind in ["melee", "ranged"]:
				col = Color("ff9a9a")
			if ev.absorbed > 0.0 and ev.absorbed >= ev.amount - 0.5:
				txt = "(%d)" % amt
				col = Color(0.4, 0.7, 1.0)
			fx.text(t.head_pos() + Vector2(0, 4), txt, col, size)
			t.hit(Color.WHITE if kind != "hack" else ev.color, 0.9 if kind != "dot" else 0.4)
			if kind in ["snipe", "charge"]:
				shake = maxf(shake, 6.0)
		"heal":
			var t := _view(ev.target)
			if t and (not ev.quiet or ev.amount >= 2.0):
				fx.text(t.head_pos() + Vector2(0, 4), "+%d" % int(round(ev.amount)), UITheme.GREEN, 8 if ev.quiet else 11)
				if not ev.quiet:
					fx.burst(t.body_pos(), UITheme.GREEN, 6, 50.0, 0.5)
		"dodge":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos(), "DODGE", UITheme.CYAN, 10, 0.8)
		"death":
			var t := _view(ev.unit)
			if t == null:
				return
			var u := t.unit()
			if u.team == CombatSim.ENEMY:
				fx.burst(t.body_pos(), Color("ff6a2a"), 14, 120.0, 0.6)
				fx.burst(t.body_pos(), UITheme.YELLOW, 6, 80.0, 0.4)
				shake = maxf(shake, 2.0)
				if u.boss:
					shake = 10.0
					front_fx.flash = 1.0
					front_fx.flash_color = Color.WHITE
					hitstop = 0.4
					fx.burst(t.body_pos(), UITheme.RED, 40, 180.0, 1.0, 3.0)
			elif u.merc_id != "":
				fx.text(t.head_pos(), "DOWN!", UITheme.RED, 15, 1.4)
				shake = maxf(shake, 5.0)
				front_fx.flash = 0.8
				front_fx.flash_color = UITheme.RED
		"loot":
			var t := _view(ev.unit)
			var amount := int(ev.amount)
			if t == null:
				display_bag += amount
				return
			fx.text(t.head_pos() + Vector2(0, -6), "+%d €$" % amount, UITheme.YELLOW, 9, 1.0)
			var n := clampi(amount, 2, 8)
			var to := bag_label.global_position + Vector2(8, 6)
			for i in n:
				var share := amount / n + (1 if i < amount % n else 0)
				front_fx.add_coin(_screen(t.body_pos()), to, i * 0.04, func(): display_bag += share)
		"payload":
			var d := ChipDB.get_def(String(ev.chip))
			var col: Color = ev.color
			var row: Control = rows[ev.thread] if ev.thread >= 0 and ev.thread < rows.size() else null
			for id in ev.targets:
				var t := _view(id)
				if t == null:
					continue
				if row:
					front_fx.link(row.tile_center_global(int(ev.slot)), _screen(t.body_pos()), col, 1.5, 0.4)
				fx.burst(t.body_pos(), col, 8, 80.0)
				t.hit(col, 0.6)
			var first := _view(ev.targets[0]) if not ev.targets.is_empty() else null
			if first:
				fx.text(first.head_pos() + Vector2(0, -14), String(d.get("name", "")).to_upper(), col, 8, 0.9, 18.0)
			if row:
				row.flash()
		"thread_fail":
			if ev.reason == "ram" and ev.thread >= 0 and ev.thread < rows.size():
				rows[ev.thread].deny()
		"overheat":
			_banner("DECK OVERHEATED", Color("ff9f1c"), "Frozen %ds  ·  Trace +%d" % [int(ChipDB.CHASSIS.freeze), int(ChipDB.CHASSIS.overheat_trace)], 1.4)
			front_fx.flash = 0.8
			front_fx.flash_color = Color("ff9f1c")
			shake = maxf(shake, 4.0)
		"trace":
			var p := meters.global_position + Vector2(140, 8)
			var l := UITheme.label("+%d TRACE" % int(round(ev.amount)), 10, DeckMeters.trace_color(sim.trace))
			l.add_theme_constant_override("outline_size", 3)
			l.position = p + Vector2(0, 26)
			ui.add_child(l)
			var tw := l.create_tween()
			tw.tween_property(l, "position:y", p.y + 40, 0.9)
			tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
			tw.tween_callback(l.queue_free)
		"skill":
			_skill_fx(ev)
		"telegraph":
			var a := _view(ev.unit)
			if a == null:
				return
			if a.unit().boss:
				_banner("BERSERK CHARGE", UITheme.RED, "Interrupt it: stun or Sonic Shock", 1.4)
				shake = maxf(shake, 2.0)
			else:
				fx.text(a.head_pos() + Vector2(0, -18), "!!", UITheme.YELLOW, 14, 0.8, 8.0)
		"interrupt":
			var a := _view(ev.unit)
			if a:
				fx.text(a.head_pos() + Vector2(0, -12), "INTERRUPTED!", UITheme.YELLOW, 14, 1.4, 22.0)
				fx.burst(a.body_pos(), UITheme.YELLOW, 18, 140.0, 0.6, 2.5)
				var th := int(ev.get("thread", -1))
				if th >= 0 and th < rows.size():
					front_fx.link(rows[th].get_global_rect().get_center(), _screen(a.body_pos()), UITheme.YELLOW, 3.0, 0.8)
			shake = maxf(shake, 4.0)
			hitstop = maxf(hitstop, 0.15)
		"cast_fire":
			var a := _view(ev.unit)
			var t := _view(ev.target)
			match String(ev.name):
				"berserk_charge":
					shake = 9.0
					front_fx.flash = 0.9
					front_fx.flash_color = UITheme.RED
					if t:
						fx.burst(t.body_pos(), UITheme.RED, 24, 160.0, 0.7, 2.5)
						fx.ring(t.position, 40.0, UITheme.RED, 0.5)
				"aim":
					if a and t:
						fx.tracer(_muzzle(a), t.body_pos(), UITheme.RED, 4.0, 0.2)
						fx.burst(t.body_pos(), UITheme.RED, 16, 140.0, 0.5, 2.0)
					shake = maxf(shake, 5.0)
				"grenade":
					if a and t:
						fx.arc(_muzzle(a), t.position + Vector2(0, -4), Color("ff9f1c"), 0.3)
						fx.ring(t.position, 40.0, Color("ff9f1c"), 0.5)
						fx.burst(t.position + Vector2(0, -6), Color("ff9f1c"), 18, 130.0, 0.5)
					shake = maxf(shake, 3.5)
				"upload":
					if a and t:
						fx.beam(a.body_pos(), t.body_pos(), UITheme.PURPLE if not ev.blocked else Color("3d8bff"), 2.0, 0.5)
		"enrage":
			_banner("CYBERPSYCHO ENRAGED", Color("ff7a2a"), "Attack speed +40%", 1.4)
			shake = maxf(shake, 5.0)
		"psycho":
			var t := _view(ev.unit)
			_banner("CYBERPSYCHOSIS", UITheme.RED, "%s ignores your deck and hits anyone close" % (UnitDB.short_name({"name": t.unit().name}) if t else "A merc"), 1.6)
			shake = maxf(shake, 4.0)
		"status":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos() + Vector2(0, -8), ev.text, ev.color, 7, 0.7, 16.0)
		"wave_start":
			if ev.boss:
				_banner("WARNING: CYBERPSYCHO", UITheme.RED, "Interrupt the Berserk Charge.", 2.0)
				shake = maxf(shake, 3.0)
			else:
				_banner("WAVE %d / %d" % [ev.index + 1, ev.total], UITheme.MAGENTA, "", 1.0)
		"wave_cleared":
			if sim.next_wave < sim.total_waves():
				_banner("WAVE CLEAR", UITheme.CYAN, "", 0.9)
		"outcome":
			outcome_delay = 1.4
			targeting = -1
			paused = false
			_close_info()
			match ev.outcome:
				"won":
					_banner("TARGET DOWN" if sim.fight.get("boss", false) else "AREA SECURED", UITheme.GREEN, "", 1.4)
				"wiped":
					_banner("CREW FLATLINED", UITheme.RED, "", 1.4)
				"traced":
					_banner("CONNECTION BURNED", UITheme.RED, "Trace hit 100%", 1.4)


func _skill_fx(ev: Dictionary) -> void:
	var a := _view(ev.unit)
	var gy := STREET_Y + 2
	match String(ev.skill):
		"sandevistan":
			if a:
				fx.text(a.head_pos() + Vector2(0, -10), "SANDEVISTAN", UITheme.MAGENTA, 9, 0.9, 20.0)
				fx.tracer(a.body_pos(), Vector2(ev.x, a.body_pos().y), Color(UITheme.MAGENTA, 0.8), 4.0, 0.25)
			for id in ev.targets:
				var t := _view(id)
				if t:
					fx.slash(t.body_pos(), UITheme.MAGENTA, 1.0)
					fx.slash(t.body_pos() + Vector2(0, -6), Color.WHITE, -1.0)
			shake = maxf(shake, 3.0)
		"bulwark":
			fx.ring(Vector2(ev.x, gy), ev.radius, Color("ff9f1c"), 0.5)
			if a:
				fx.text(a.head_pos() + Vector2(0, -10), "BULWARK", Color("ff9f1c"), 9, 0.9, 20.0)
			shake = maxf(shake, 2.5)
		"stim":
			for id in ev.targets:
				var t := _view(id)
				if t:
					fx.ring(t.position, 22.0, UITheme.GREEN, 0.5)
		"deploy":
			fx.ring(Vector2(ev.x, gy), 20.0, UITheme.CYAN, 0.5)
			if a:
				fx.text(a.head_pos() + Vector2(0, -10), "TURRET", UITheme.CYAN, 9, 0.9, 20.0)
		"mark":
			for id in ev.targets:
				var t := _view(id)
				if t:
					fx.text(t.head_pos() + Vector2(0, -10), "MARKED", UITheme.YELLOW, 9, 0.9, 16.0)
		"blast":
			fx.ring(Vector2(ev.x, gy), ev.radius, Color("ff9f1c"), 0.45)
			fx.burst(Vector2(ev.x, STREET_Y - 6), Color("ff9f1c"), 12, 120.0, 0.45)
			shake = maxf(shake, 2.5)
		"contagion":
			fx.ring(Vector2(ev.x, gy), ev.radius, Color("9bff3d"), 0.55)
			fx.burst(Vector2(ev.x, STREET_Y - 10), Color("9bff3d"), 16, 110.0, 0.5)


func _banner(text: String, col: Color, sub := "", hold := 1.6) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	banner.pivot_offset = Vector2(banner.size.x / 2.0, 12)
	banner.scale = Vector2(1.2, 1.2)
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.12)
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner_sub, "modulate:a", 1.0, 0.2).set_delay(0.08)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.35)
	_banner_tween.tween_property(banner_sub, "modulate:a", 0.0, 0.35)


func _toast(text: String, col: Color) -> void:
	var l := UITheme.label(text, 10, col)
	l.add_theme_constant_override("outline_size", 3)
	l.anchor_right = 1.0
	l.offset_left = 8
	l.offset_right = -8
	l.offset_top = STRIP_BOTTOM - 22
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "offset_top", STRIP_BOTTOM - 40.0, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(1.0)
	tw.tween_callback(l.queue_free)


# --- end of fight -------------------------------------------------------------------

func _show_end() -> void:
	if end_panel:
		return
	display_bag = sim.bag
	var r := sim.result()
	end_panel = Control.new()
	end_panel.anchor_right = 1.0
	end_panel.anchor_bottom = 1.0
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(end_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.0)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	end_panel.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.75, 0.4)

	var o: String = r.outcome
	var boss: bool = sim.fight.get("boss", false)
	var title: String = {"won": "TARGET DOWN" if boss else "AREA SECURED", "wiped": "FLATLINED", "traced": "TRACED"}.get(o, "OVER")
	var col: Color = UITheme.GREEN if o == "won" else UITheme.RED
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.11, 0.97), col, 2, 3, 14))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(300, 0)
	end_panel.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var tl := UITheme.label(title, 24, col)
	tl.add_theme_constant_override("outline_size", 6)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var sub_text: String = {"won": "Loot is waiting." if not boss else "The job is done.", "wiped": "The whole crew is down. The run is over.",
		"traced": "Corp security found your deck. The run is over."}.get(o, "")
	var sub := UITheme.label(sub_text, 10, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var downs: int = r.crew.filter(func(c): return c.down).size()
	var lines := [
		["Kills", str(r.kills), UITheme.TEXT],
		["Eddies", "+%d €$" % r.bag, UITheme.YELLOW],
		["Trace", "+%d  (now %d%%)" % [int(round(r.trace_gain)), int(r.trace)], DeckMeters.trace_color(r.trace)],
		["Interrupts", str(r.interrupts), UITheme.CYAN],
		["Time", "%d:%02d" % [floori(r.duration / 60.0), int(r.duration) % 60], UITheme.TEXT],
	]
	if downs > 0 and o == "won":
		lines.append(["Downed (get up with a scar)", str(downs), UITheme.RED])
	if sim.deck.overheats > 0:
		lines.append(["Overheats", str(sim.deck.overheats), Color("ff9f1c")])
	for i in lines.size():
		var ln: Array = lines[i]
		var h := HBoxContainer.new()
		var a := UITheme.label(ln[0], 11, UITheme.TEXT_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UITheme.label(ln[1], 11, ln[2]))
		h.modulate.a = 0.0
		v.add_child(h)
		create_tween().tween_property(h, "modulate:a", 1.0, 0.2).set_delay(0.2 + i * 0.1)
	v.add_child(HSeparator.new())
	var cont := _btn("CONTINUE", _on_continue, 160)
	cont.custom_minimum_size = Vector2(160, 36)
	cont.add_theme_font_size_override("font_size", 14)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cont)
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)


func _on_continue() -> void:
	if finished:
		return
	finished = true
	var standalone := get_parent() == get_tree().root
	Game.finish_fight(sim.result())
	if standalone:
		get_tree().change_scene_to_file(MAIN_SCENE)
