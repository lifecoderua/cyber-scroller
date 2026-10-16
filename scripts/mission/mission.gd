extends Node2D
## Mission scene controller: owns a CombatSim, renders it (world + HUD) and turns sim
## events into juice. Sim time = real delta * speed (0 while paused / targeting /
## hit-stop). See docs/DESIGN.md "Time and active pause".

const UnitView := preload("res://scripts/mission/unit_view.gd")
const FxLayer := preload("res://scripts/mission/fx_layer.gd")
const SoftCard := preload("res://scripts/mission/soft_card.gd")
const SquadChip := preload("res://scripts/mission/squad_chip.gd")
const RamBar := preload("res://scripts/mission/ram_bar.gd")
const ProgressPips := preload("res://scripts/mission/progress_pips.gd")
const ScreenFx := preload("res://scripts/mission/screen_fx.gd")
const FallbackBackdrop := preload("res://scripts/mission/fallback_backdrop.gd")

const BACKDROP_PATH := "res://scripts/art/city_backdrop.gd"
const MAIN_SCENE := "res://scenes/main.tscn"
const STREET_Y := 292.0
const CAM_LEAD := 0.34  # front runner sits at this fraction of the screen width
const HITSTOP := 0.25
const SPEEDS := [1, 2, 3]
const CARD_W := 84.0
const CARD_GAP := 6.0
const PICK_PAD := 16.0  # generous touch hit area around a unit's body

var sim: CombatSim
var world: Node2D
var backdrop: Node2D
var units_layer: Node2D
var fx: FxLayer
var views := {}  # unit id -> UnitView

var hud: CanvasLayer
var ui: Control
var tint_fx: ScreenFx
var front_fx: ScreenFx
var ram_bar: RamBar
var pips: ProgressPips
var bag_label: Label
var pause_btn: Button
var speed_btn: Button
var extract_btn: Button
var cards: Array = []
var chips: Array = []
var prompt: PanelContainer
var prompt_label: Label
var pause_note: Label
var banner: Label
var banner_sub: Label
var end_panel: Control

var speed_idx := 0
var paused := false
var targeting := -1
var hitstop := 0.0
var shake := 0.0
var cam_x := 0.0
var display_bag := 0
var outcome_delay := -1.0
var finished := false
var hover_id := -1
var _banner_tween: Tween
var _t := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	if Game.current_contract.is_empty():
		Game.current_contract = Game.make_contract(1)
	var runners := Game.squad_runners()
	if runners.is_empty():
		runners = [UnitDB.make_runner("solo", Game.rng, false), UnitDB.make_runner("gunner", Game.rng, false)]
	sim = CombatSim.new()
	sim.setup(Game.current_contract, runners, Game.deck_active, Game.fixer_stats())
	var vs := get_viewport_rect().size
	sim.spawn_ahead = maxf(CombatSim.DEFAULT_SPAWN_AHEAD, vs.x * (1.0 - CAM_LEAD) + 30.0)
	cam_x = sim.front_x() - vs.x * CAM_LEAD
	_build_world()
	_build_hud()
	_sync_views()
	var c := Game.current_contract
	_banner(str(c.get("district", "")).to_upper(), UITheme.CYAN, "%s  ·  threat %d" % [c.get("title", ""), int(c.get("threat", 1))], 2.6)


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
		backdrop.set_district(str(Game.current_contract.get("district", "Neon Row")))
	units_layer = Node2D.new()
	units_layer.y_sort_enabled = false
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
	_full(tint_fx)
	ui.add_child(tint_fx)

	# Top bar.
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", _bar_box())
	bar.anchor_right = 1.0
	bar.offset_bottom = 28
	ui.add_child(bar)
	ram_bar = RamBar.new()
	ram_bar.sim = sim
	ram_bar.position = Vector2(6, 7)
	ram_bar.size = Vector2(152, 14)
	bar.add_child(ram_bar)
	bag_label = UITheme.label("€$ 0", 12, UITheme.YELLOW)
	bag_label.position = Vector2(164, 6)
	bar.add_child(bag_label)
	pips = ProgressPips.new()
	pips.sim = sim
	pips.anchor_left = 0.5
	pips.anchor_right = 0.5
	pips.offset_left = -78
	pips.offset_right = 78
	pips.offset_top = 2
	pips.offset_bottom = 26
	bar.add_child(pips)
	var right := HBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 4)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -150
	right.offset_right = -4
	right.offset_top = 3
	right.offset_bottom = 25
	right.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(right)
	extract_btn = _btn("EXTRACT", _on_extract, 70)
	right.add_child(extract_btn)
	speed_btn = _btn("1x", _cycle_speed, 32)
	right.add_child(speed_btn)
	pause_btn = _btn("||", _toggle_pause, 32)
	right.add_child(pause_btn)

	# Squad status.
	var squad_box := VBoxContainer.new()
	squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_box.add_theme_constant_override("separation", 3)
	squad_box.position = Vector2(6, 32)
	ui.add_child(squad_box)
	for u in sim.runners(false):
		var chip: SquadChip = SquadChip.new()
		chip.setup(sim, u)
		chip.tapped.connect(_on_chip)
		squad_box.add_child(chip)
		chips.append(chip)

	# Soft cards.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(CARD_GAP))
	var n := sim.slots.size()
	var w := n * CARD_W + maxf(0, n - 1) * CARD_GAP
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = -w / 2.0
	row.offset_right = w / 2.0
	row.offset_top = -54
	row.offset_bottom = -4
	ui.add_child(row)
	for i in n:
		var card: SoftCard = SoftCard.new()
		card.sim = sim
		card.slot = i
		card.custom_minimum_size = Vector2(CARD_W, 50)
		card.tapped.connect(_on_card)
		row.add_child(card)
		cards.append(card)

	# Targeting prompt.
	prompt = PanelContainer.new()
	prompt.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.1, 0.13, 0.9), UITheme.CYAN, 1, 2, 6))
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.offset_top = 33
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	prompt.add_child(ph)
	prompt_label = UITheme.label("SELECT TARGET", 11, UITheme.CYAN)
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_child(prompt_label)
	ph.add_child(_btn("CANCEL", _cancel_target, 60))
	prompt.visible = false
	ui.add_child(prompt)

	pause_note = UITheme.label("PAUSED  ·  queue soft, then resume", 11, UITheme.PURPLE)
	pause_note.anchor_left = 0.5
	pause_note.anchor_right = 0.5
	pause_note.offset_top = 36
	pause_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_note.visible = false
	ui.add_child(pause_note)

	banner = UITheme.label("", 22, UITheme.CYAN)
	banner.add_theme_constant_override("outline_size", 6)
	banner.anchor_right = 1.0
	banner.offset_top = 74
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	ui.add_child(banner)
	banner_sub = UITheme.label("", 11, UITheme.TEXT)
	banner_sub.add_theme_constant_override("outline_size", 4)
	banner_sub.anchor_right = 1.0
	banner_sub.offset_top = 104
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub.modulate.a = 0.0
	ui.add_child(banner_sub)

	front_fx = ScreenFx.new()
	front_fx.mode = "front"
	_full(front_fx)
	ui.add_child(front_fx)


func _full(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0


func _bar_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.08, 0.86)
	s.border_color = UITheme.CYAN.darkened(0.55)
	s.border_width_bottom = 1
	return s


func _btn(text: String, cb: Callable, w: float) -> Button:
	var b := UITheme.button(text, cb, 10)
	b.custom_minimum_size = Vector2(w, 22)
	b.focus_mode = Control.FOCUS_NONE
	return b


# --- main loop ------------------------------------------------------------------

func _effective_speed() -> float:
	if paused or targeting >= 0 or hitstop > 0.0 or sim.outcome != "":
		return 0.0
	return float(SPEEDS[speed_idx])


func _process(delta: float) -> void:
	_t += delta
	hitstop = maxf(0.0, hitstop - delta)
	var sim_dt := delta * _effective_speed()
	if sim_dt > 0.0:
		sim.step(sim_dt)
	_drain_events()
	_sync_views()
	var vs := get_viewport_rect().size
	# Camera follows the squad; ease with real time.
	var target := sim.front_x() - vs.x * CAM_LEAD
	cam_x = lerpf(cam_x, target, 1.0 - exp(-delta * 3.5))
	shake = move_toward(shake, 0.0, delta * 22.0)
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	world.position = Vector2(round(-cam_x + off.x), round(off.y))
	if backdrop.has_method("update_view"):
		backdrop.update_view(-world.position.x, vs)
	for id in views:
		var v: UnitView = views[id]
		var u := v.unit()
		v.highlight = 0
		v.hover = false
		if targeting >= 0 and u.alive:
			v.highlight = 1 if sim.is_valid_target(targeting, id) else -1
			v.hover = id == hover_id
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
	var tint_target := 1.0 if targeting >= 0 else 0.0
	tint_fx.tint = move_toward(tint_fx.tint, tint_target, delta * 6.0)
	tint_fx.pause_tint = move_toward(tint_fx.pause_tint, 1.0 if paused and targeting < 0 else 0.0, delta * 6.0)
	bag_label.text = "€$ %d" % display_bag
	speed_btn.text = "%dx" % SPEEDS[speed_idx]
	pause_btn.text = ">" if paused else "||"
	var can_ex := sim.can_extract() and not finished
	extract_btn.disabled = not can_ex
	extract_btn.modulate = Color.WHITE.lerp(UITheme.YELLOW, 0.5 + 0.5 * sin(_t * 5.0)) if can_ex and sim.encounters_cleared > 0 else Color.WHITE
	pause_note.visible = paused and targeting < 0 and sim.outcome == ""
	prompt.visible = targeting >= 0
	ram_bar.preview_cost = float(sim.slot_def(targeting).get("ram", 0)) if targeting >= 0 else 0.0
	for c in cards:
		c.selected = c.slot == targeting
	for chip in chips:
		var u := sim.get_unit(chip.uid)
		chip.highlight = 1 if targeting >= 0 and u.alive and sim.is_valid_target(targeting, chip.uid) else 0


# --- input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			_on_card(k - KEY_1)
		elif k == KEY_SPACE:
			_toggle_pause()
		elif k == KEY_ESCAPE:
			_cancel_target()
		elif k == KEY_F:
			_cycle_speed()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if targeting >= 0:
			var id := _pick(event.position)
			if id >= 0:
				_cast_on(id)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and targeting >= 0:
		hover_id = _pick(event.position)


## Unit under a screen position that is a valid target for the pending soft.
func _pick(screen_pos: Vector2) -> int:
	var p := screen_pos - world.position
	var best := -1
	var best_d := INF
	for id in views:
		if not sim.is_valid_target(targeting, id):
			continue
		var v: UnitView = views[id]
		var half := Vector2(8.0, 12.0) * v.scale_px + Vector2(PICK_PAD, PICK_PAD)
		var c := v.body_pos()
		var d := (p - c).abs()
		if d.x <= half.x and d.y <= half.y:
			var score := d.x + d.y * 0.3
			if score < best_d:
				best_d = score
				best = id
	return best


func _on_card(slot: int) -> void:
	if finished or sim.outcome != "" or slot < 0 or slot >= sim.slots.size():
		return
	if targeting == slot:
		_cancel_target()
		return
	var reason := sim.block_reason(slot)
	if reason != "":
		cards[slot].deny()
		var msg: String = {"ram": "NOT ENOUGH RAM", "cd": "COOLING DOWN", "charges": "NO CHARGES", "target": "NO TARGET"}.get(reason, "")
		if msg != "":
			_toast(msg, UITheme.RED)
		return
	if sim.needs_target(slot):
		targeting = slot
		hover_id = -1
		var d := sim.slot_def(slot)
		prompt_label.text = "SELECT %s  ·  %s" % ["ALLY" if d.target == "ally" else "TARGET", d.name]
		prompt_label.add_theme_color_override("font_color", d.color)
	else:
		targeting = -1
		if sim.cast(slot, -1):
			hitstop = HITSTOP
			_drain_events()


func _on_chip(uid: int) -> void:
	if targeting >= 0 and sim.is_valid_target(targeting, uid):
		_cast_on(uid)


func _cast_on(id: int) -> void:
	var slot := targeting
	targeting = -1
	hover_id = -1
	if sim.cast(slot, id):
		hitstop = 0.08
		_drain_events()


func _cancel_target() -> void:
	targeting = -1
	hover_id = -1


func _toggle_pause() -> void:
	if sim.outcome != "":
		return
	paused = not paused


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


func _on_extract() -> void:
	if sim.extract():
		targeting = -1
		_drain_events()


# --- events -> juice --------------------------------------------------------------

func _drain_events() -> void:
	for ev in sim.pop_events():
		_handle(ev)


func _view(id) -> UnitView:
	return views.get(id, null)


func _face(v: UnitView) -> float:
	return -1.0 if v.unit().team == CombatSim.ENEMY else 1.0


func _muzzle(v: UnitView) -> Vector2:
	if v.unit().flying:
		return v.body_pos() + Vector2(0, 4)
	return v.position + Vector2(7.0 * v.scale_px * _face(v), -12.5 * v.scale_px)


func _screen(world_pos: Vector2) -> Vector2:
	return world_pos + world.position


func _handle(ev: Dictionary) -> void:
	match ev.type:
		"attack":
			var a := _view(ev.src)
			var t := _view(ev.target)
			if a:
				a.on_attack()
			if a and t:
				var tp := t.body_pos() + Vector2(randf_range(-3, 3), randf_range(-6, 6))
				if ev.missed:
					tp += Vector2(-_face(a) * -18.0, randf_range(-14, -8))
				if ev.ranged:
					var col := UITheme.YELLOW if a.unit().team == CombatSim.RUNNER else Color("ff5a3a")
					if a.unit().kind == "medtech":
						col = UITheme.GREEN
					elif a.unit().kind == "techie":
						col = UITheme.CYAN
					fx.tracer(_muzzle(a), tp, col)
					if not ev.missed:
						fx.burst(tp, col, 3, 40.0, 0.2, 1.0)
				else:
					fx.slash(tp, UITheme.MAGENTA if a.unit().team == CombatSim.RUNNER else Color("ff6a2a"), _face(a))
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
					size = 13
				"dot":
					col = ev.color
					size = 8
				"skill":
					col = ev.color
					size = 11
				"charge":
					col = UITheme.RED
					size = 18
					txt = "%d!" % amt
			if ev.crit and kind != "charge":
				col = UITheme.YELLOW
				size += 4
				txt = "%d!" % amt
			if u.team == CombatSim.RUNNER and kind in ["melee", "ranged"]:
				col = Color("ff9a9a")
			if ev.absorbed > 0.0 and ev.absorbed >= ev.amount - 0.5:
				txt = "(%d)" % amt
				col = Color(0.4, 0.7, 1.0)
			fx.text(t.head_pos() + Vector2(0, 4), txt, col, size)
			t.hit(Color.WHITE if kind != "hack" else ev.color, 0.9 if kind != "dot" else 0.4)
			if kind == "hack" and ev.amount >= 60.0:
				shake = maxf(shake, 4.0)
				fx.burst(t.body_pos(), ev.color, 14, 110.0)
			var src := _view(ev.src)
			if src and src.unit().boss:
				shake = maxf(shake, 3.0)
		"heal":
			var t := _view(ev.target)
			if t and (not ev.quiet or ev.amount >= 2.0):
				fx.text(t.head_pos() + Vector2(0, 4), "+%d" % int(round(ev.amount)), UITheme.GREEN, 8 if ev.quiet else 11)
				if not ev.quiet:
					fx.burst(t.body_pos(), UITheme.GREEN, 6, 50.0, 0.5)
		"miss":
			var t := _view(ev.target)
			if t:
				fx.text(t.head_pos(), "MISS", UITheme.TEXT_DIM, 9, 0.7)
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
			else:
				fx.text(t.head_pos(), "DOWN!", UITheme.RED, 15, 1.4)
				shake = maxf(shake, 5.0)
				front_fx.flash = 0.8
				front_fx.flash_color = UITheme.RED
		"loot":
			var t := _view(ev.unit)
			if t == null:
				display_bag += int(ev.amount)
				return
			var amount := int(ev.amount)
			fx.text(t.head_pos() + Vector2(0, -6), "+%d €$" % amount, UITheme.YELLOW, 10, 1.1)
			var n := clampi(amount / 2, 3, 14)
			var to := bag_label.global_position + Vector2(8, 8)
			for i in n:
				var share := amount / n + (1 if i < amount % n else 0)
				front_fx.add_coin(_screen(t.body_pos()), to, i * 0.04, func(): display_bag += share)
		"cast":
			var col: Color = ev.color
			var t := _view(ev.target)
			var d: Dictionary = SoftDB.get_def(ev.soft)
			if t:
				var from := Vector2(t.position.x + randf_range(-70, 70), -world.position.y + 30.0)
				fx.beam(from, t.body_pos(), col, 3.0 if t.unit().team == CombatSim.ENEMY else 2.0, 0.45)
				fx.text(t.head_pos() + Vector2(0, -14), d.get("name", "").to_upper(), col, 9, 1.0, 18.0)
				fx.burst(t.body_pos(), col, 10, 90.0)
			else:
				front_fx.flash = 1.0
				front_fx.flash_color = col
				shake = maxf(shake, 3.0)
				var team := CombatSim.RUNNER if d.has("shield") else CombatSim.ENEMY
				for id in views:
					var v: UnitView = views[id]
					if v.unit().alive and v.unit().team == team:
						fx.ring(v.position, 26.0, col, 0.6)
						v.hit(col, 0.7)
				_banner(d.get("name", "").to_upper(), col, "", 0.9)
		"skill":
			var a := _view(ev.unit)
			match ev.skill:
				"gorilla_slam":
					fx.ring(Vector2(ev.x, STREET_Y + 2), ev.radius, UITheme.MAGENTA, 0.5)
					fx.burst(Vector2(ev.x, STREET_Y - 4), UITheme.MAGENTA, 12, 120.0, 0.5)
					shake = maxf(shake, 3.0)
					if a:
						fx.text(a.head_pos() + Vector2(0, -10), "GORILLA SLAM", UITheme.MAGENTA, 9, 0.9, 20.0)
				"burst_fire":
					if a:
						fx.text(a.head_pos() + Vector2(0, -10), "BURST FIRE", UITheme.YELLOW, 8, 0.8, 18.0)
				"trauma_kit":
					var t := _view(ev.target)
					if t:
						fx.ring(t.position, 22.0, UITheme.GREEN, 0.5)
				"shock_grenade":
					if a:
						fx.arc(_muzzle(a), Vector2(ev.x, STREET_Y - 4), UITheme.CYAN, 0.3)
					fx.ring(Vector2(ev.x, STREET_Y + 2), ev.radius, UITheme.CYAN, 0.55)
					fx.burst(Vector2(ev.x, STREET_Y - 6), UITheme.CYAN, 14, 130.0, 0.5)
					shake = maxf(shake, 2.5)
		"telegraph":
			var a := _view(ev.unit)
			if a == null:
				return
			if a.unit().boss:
				_banner("BERSERK CHARGE", UITheme.RED, "Stun it to interrupt!", 1.6)
				shake = maxf(shake, 2.0)
			else:
				fx.text(a.head_pos() + Vector2(0, -16), "!! OVERHEAT", UITheme.PURPLE, 10, 1.2, 12.0)
		"interrupt":
			var a := _view(ev.unit)
			if a:
				fx.text(a.head_pos() + Vector2(0, -12), "INTERRUPTED!", UITheme.YELLOW, 16, 1.4, 22.0)
				fx.burst(a.body_pos(), UITheme.YELLOW, 18, 140.0, 0.6, 2.5)
			shake = maxf(shake, 4.0)
			hitstop = maxf(hitstop, 0.15)
		"cast_fire":
			var a := _view(ev.unit)
			var t := _view(ev.target)
			if ev.name == "berserk_charge":
				shake = 9.0
				front_fx.flash = 0.9
				front_fx.flash_color = UITheme.RED
				if t:
					fx.burst(t.body_pos(), UITheme.RED, 24, 160.0, 0.7, 2.5)
					fx.ring(t.position, 40.0, UITheme.RED, 0.5)
			elif a and t:
				fx.beam(a.body_pos(), t.body_pos(), UITheme.PURPLE, 2.0, 0.5)
		"enrage":
			_banner("CYBERPSYCHO ENRAGED", Color("ff7a2a"), "Attack speed +40%", 1.6)
			shake = maxf(shake, 5.0)
		"status":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos() + Vector2(0, -8), ev.text, ev.color, 8, 0.8, 16.0)
		"ice":
			var t := _view(ev.target)
			if t:
				fx.beam(Vector2(t.position.x + 30, -world.position.y + 30.0), t.body_pos(), Color("3d8bff"), 1.5, 0.25)
		"encounter_start":
			if ev.boss:
				_banner("WARNING: CYBERPSYCHO", UITheme.RED, "Boss ahead. Interrupt the charge.", 2.4)
				shake = maxf(shake, 3.0)
			else:
				_banner("CONTACT  %d / %d" % [ev.index + 1, sim.total_encounters()], UITheme.MAGENTA, "", 1.4)
		"encounter_cleared":
			if not ev.boss:
				_banner("AREA CLEAR", UITheme.CYAN, "Extract with the bag, or push on", 2.2)
		"outcome":
			outcome_delay = 1.6
			targeting = -1
			paused = false
			match ev.outcome:
				"success":
					_banner("TARGET DOWN", UITheme.GREEN, "", 1.6)
				"wiped":
					_banner("SQUAD FLATLINED", UITheme.RED, "", 1.6)
				"extracted":
					_banner("EXTRACTING...", UITheme.CYAN, "", 1.4)


func _banner(text: String, col: Color, sub := "", hold := 1.6) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	banner.pivot_offset = Vector2(banner.size.x / 2.0, 14)
	banner.scale = Vector2(1.25, 1.25)
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
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_top = -74
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "offset_top", -88.0, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# --- end of mission -----------------------------------------------------------------

func _show_end() -> void:
	if end_panel:
		return
	display_bag = sim.bag
	var r := sim.result()
	var c := Game.current_contract
	end_panel = Control.new()
	_full(end_panel)
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(end_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.0)
	_full(dim)
	end_panel.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.72, 0.4)

	var title: String = {"success": "MISSION COMPLETE", "extracted": "EXTRACTED", "wiped": "FLATLINED"}[r.outcome]
	var col: Color = {"success": UITheme.GREEN, "extracted": UITheme.CYAN, "wiped": UITheme.RED}[r.outcome]
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
	var sub := UITheme.label(str(c.get("title", "")), 10, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var lines := []
	match r.outcome:
		"success":
			lines.append(["Bag", "%d €$" % r.bag, UITheme.YELLOW])
			lines.append(["Contract reward", "+%d €$" % int(c.get("reward", 0)), UITheme.YELLOW])
		"extracted":
			lines.append(["Bag", "%d €$" % r.bag, UITheme.YELLOW])
			lines.append(["Contract reward", "forfeited", UITheme.TEXT_DIM])
		"wiped":
			lines.append(["Bag", "lost (%d €$)" % r.bag, UITheme.RED])
			lines.append(["Squad", "flatlined", UITheme.RED])
	lines.append(["Kills", str(r.kills), UITheme.TEXT])
	lines.append(["Encounters", "%d / %d" % [r.encounters_cleared, sim.total_encounters()], UITheme.TEXT])
	lines.append(["Time", "%d:%02d" % [int(r.duration) / 60, int(r.duration) % 60], UITheme.TEXT])
	if r.outcome != "wiped" and not r.downed.is_empty():
		lines.append(["Downed (pulled through)", str(r.downed.size()), UITheme.YELLOW])
	for i in lines.size():
		var ln: Array = lines[i]
		var h := HBoxContainer.new()
		var a := UITheme.label(ln[0], 11, UITheme.TEXT_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UITheme.label(ln[1], 11, ln[2]))
		h.modulate.a = 0.0
		v.add_child(h)
		create_tween().tween_property(h, "modulate:a", 1.0, 0.2).set_delay(0.25 + i * 0.12)
	v.add_child(HSeparator.new())
	var cont := _btn("CONTINUE", _on_continue, 140)
	cont.custom_minimum_size = Vector2(140, 30)
	cont.add_theme_font_size_override("font_size", 13)
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
	Game.finish_mission(sim.result())
	if standalone:
		get_tree().change_scene_to_file(MAIN_SCENE)
