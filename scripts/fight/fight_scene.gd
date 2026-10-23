extends Node2D
## Turn-based dice fight (portrait 360x640). Battlefield on top: crew on the left, enemies on
## the right with their intents. Below: crew cards with incoming damage, two dice per merc,
## the fixer's hacks and daemons, and the turn buttons. Rules live in DiceCombat; this scene
## shows them and replays the sim's events one by one so every hit can be read.
## See docs/DICE_DESIGN.md.

const FightUnit := preload("res://scripts/fight/fight_unit.gd")
const FxLayer := preload("res://scripts/fight/fx_layer.gd")
const ScreenFx := preload("res://scripts/fight/screen_fx.gd")
const FallbackBackdrop := preload("res://scripts/fight/fallback_backdrop.gd")
const BACKDROP_PATH := "res://scripts/art/city_backdrop.gd"
const MAIN_SCENE := "res://scenes/main.tscn"

const TOP_H := 40.0
const FEET_Y := 224.0
const FIELD_BOTTOM := 282.0
const WORLD_Y := -72.0
const CREW_X := [146.0, 98.0, 50.0]   # front, mid, back
const ENEMY_X0 := 200.0
const ENEMY_DX := 38.0
const CARD_Y := 286.0
const DICE_Y := 336.0
const DIE_SIZE := 54.0
const STEP_FAST := 0.07
const STEP_SLOW := 0.32

var c: DiceCombat
var world: Node2D
var backdrop: Node2D
var units_layer: Node2D
var lines: Node2D
var fx: FxLayer
var views := {}            # unit id -> FightUnit
var _enemy_slots := {}     # unit id -> slot index

var ui: Control
var front_fx: ScreenFx
var cards: Array = []
var die_views: Array = []
var hack_buttons: Array = []
var info: Label
var daemon_label: Label
var trace_bar: MeterBar
var ram_label: Label
var heat_bar: MeterBar
var wave_label: Label
var bag_label: Label
var reroll_btn: Button
var done_btn: Button
var auto_btn: Button
var pause_btn: Button
var banner: Label
var banner_sub: Label
var end_panel: Control

## Audio expects these on the fight scene.
var paused := false
var targeting := -1

var sel_die := -1
var hack_slot := -1
var finished := false
var display_bag := 0
var _queue: Array = []
var _wait := 0.0
var _busy := false         # replaying the enemy phase: input blocked
var _banner_tween: Tween
var _ended := false
var instant := false       # tools: replay events without delays


func _ready() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	_ensure_run()
	var run: RunState = Game.run
	c = DiceCombat.new()
	c.setup(run.pending.fight, run.crew, run.hacks, run.daemons, Game.fight_stats())
	_build_world()
	_build_hud()
	for u in c.units:
		_add_view(u, false)
	_drain()
	var info_d: Dictionary = RunState.NODE_INFO.get(String(run.pending.fight.get("type", "fight")), RunState.NODE_INFO.fight)
	_banner(String(info_d.name), info_d.color, "%d waves  ·  roll, lock, reroll, then use your dice" % c.total_waves(), 1.6)
	if run.pending.fight.get("alert", false):
		_banner("SECURITY ALERT", UITheme.RED, "Trace %d%%+: a gunman joins every wave" % int(RunState.ALERT_TRACE), 1.6)
	Audio.attach_mission(self)


## Started on its own (F6 / tools): make a throwaway run on a first fight.
func _ensure_run() -> void:
	if Game.run != null and Game.run.phase == "fight":
		return
	Game.run = RunState.create(Game.make_contract(1), Game.fixer_stats())
	Game.run.choose_draft(0)
	Game.run.enter(Game.run.reachable()[0])


# --- construction ---------------------------------------------------------------------

func _build_world() -> void:
	world = Node2D.new()
	world.position = Vector2(0, WORLD_Y)
	add_child(world)
	if ResourceLoader.exists(BACKDROP_PATH):
		backdrop = load(BACKDROP_PATH).new()
	else:
		backdrop = FallbackBackdrop.new()
	world.add_child(backdrop)
	if backdrop.has_method("set_district"):
		backdrop.set_district(str(Game.run.contract.get("district", "Neon Row")))
	if backdrop.has_method("update_view"):
		backdrop.update_view(0.0, Vector2(360, 360))
	lines = IntentLines.new()
	lines.scene = self
	add_child(lines)
	units_layer = Node2D.new()
	add_child(units_layer)
	fx = FxLayer.new()
	add_child(fx)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UITheme.get_theme()
	layer.add_child(ui)

	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.95), true))
	bar.anchor_right = 1.0
	bar.offset_bottom = TOP_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	trace_bar = MeterBar.new("TRACE", UITheme.PURPLE, 12)
	trace_bar.ticks = true
	trace_bar.position = Vector2(6, 4)
	trace_bar.size = Vector2(212, 12)
	bar.add_child(trace_bar)
	ram_label = UITheme.label("", 10, UITheme.CYAN)
	ram_label.position = Vector2(6, 20)
	bar.add_child(ram_label)
	heat_bar = MeterBar.new("HEAT", Color("ff9f1c"), 12)
	heat_bar.position = Vector2(120, 22)
	heat_bar.size = Vector2(98, 12)
	bar.add_child(heat_bar)
	wave_label = UITheme.label("", 10, UITheme.MAGENTA)
	wave_label.position = Vector2(226, 3)
	bar.add_child(wave_label)
	bag_label = UITheme.label("", 10, UITheme.YELLOW)
	bag_label.position = Vector2(226, 20)
	bar.add_child(bag_label)
	var right := HBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -40
	right.offset_right = -4
	right.offset_top = 8
	right.offset_bottom = 32
	right.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(right)
	pause_btn = _btn("?", _show_help, 26)
	right.add_child(pause_btn)

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.025, 0.025, 0.06, 0.98), false))
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = FIELD_BOTTOM
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)

	# Crew cards with their two dice underneath, in battlefield order (front merc on the right).
	var crew := c.mercs(false)
	for i in crew.size():
		var u: DiceCombat.Unit = crew[i]
		var x := 4.0 + (2 - mini(i, 2)) * 118.0
		var card := CrewCard.new()
		card.c = c
		card.uid = u.id
		card.position = Vector2(x, CARD_Y)
		card.size = Vector2(114, 46)
		card.pressed.connect(_on_unit_tapped)
		ui.add_child(card)
		cards.append(card)
		var ds := c.dice_of(u)
		for k in ds.size():
			var dv := DieView.new()
			dv.set_meta("die", ds[k].index)
			dv.which = ds[k].which
			dv.position = Vector2(x + 2 + k * (DIE_SIZE + 2), DICE_Y)
			dv.size = Vector2(DIE_SIZE, DIE_SIZE)
			dv.custom_minimum_size = dv.size
			dv.pressed.connect(_on_die)
			ui.add_child(dv)
			die_views.append(dv)

	info = UITheme.label("", 9, UITheme.TEXT)
	info.position = Vector2(8, DICE_Y + DIE_SIZE + 2)
	info.size = Vector2(344, 26)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.max_lines_visible = 2
	ui.add_child(info)

	var hk := UITheme.label("HACKS", 8, UITheme.TEXT_DIM)
	hk.position = Vector2(8, 438)
	ui.add_child(hk)
	for i in c.hacks.size():
		var hb := HackButton.new()
		hb.scene = self
		hb.slot = i
		hb.position = Vector2(6 + i * 70.0, 450)
		hb.size = Vector2(66, 46)
		hb.pressed.connect(_on_hack)
		ui.add_child(hb)
		hack_buttons.append(hb)
	daemon_label = UITheme.label("", 8, UITheme.PURPLE)
	daemon_label.position = Vector2(8, 502)
	daemon_label.size = Vector2(344, 24)
	daemon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(daemon_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.anchor_right = 1.0
	row.offset_left = 6
	row.offset_right = -6
	row.offset_top = -62
	row.offset_bottom = -8
	ui.add_child(row)
	auto_btn = _btn("AUTO", _auto_turn, 64)
	auto_btn.tooltip_text = "Let the crew play this turn"
	row.add_child(auto_btn)
	reroll_btn = _btn("REROLL", _on_reroll, 100)
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reroll_btn)
	done_btn = _btn("DONE", _on_done, 120)
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(done_btn)
	for b in [auto_btn, reroll_btn, done_btn]:
		b.add_theme_font_size_override("font_size", 14)

	banner = UITheme.label("", 20, UITheme.CYAN)
	banner.add_theme_constant_override("outline_size", 6)
	banner.anchor_right = 1.0
	banner.offset_top = TOP_H + 8
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	ui.add_child(banner)
	banner_sub = UITheme.label("", 10, UITheme.TEXT)
	banner_sub.add_theme_constant_override("outline_size", 4)
	banner_sub.anchor_right = 1.0
	banner_sub.offset_top = TOP_H + 34
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub.modulate.a = 0.0
	ui.add_child(banner_sub)

	front_fx = ScreenFx.new()
	front_fx.mode = "front"
	front_fx.anchor_right = 1.0
	front_fx.anchor_bottom = 1.0
	ui.add_child(front_fx)


func _box(bg: Color, bottom: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = UITheme.CYAN.darkened(0.55)
	if bottom:
		s.border_width_bottom = 1
	else:
		s.border_width_top = 1
	return s


func _btn(text: String, cb: Callable, w: float) -> Button:
	var b := HubW.button(text, cb, 11)
	b.custom_minimum_size = Vector2(w, 26)
	return b


func _add_view(u: DiceCombat.Unit, full_hp: bool) -> void:
	if views.has(u.id):
		return
	var v: Node2D = FightUnit.new()
	v.setup(c, u)
	if full_hp:
		v.shown_hp = u.max_hp
	if u.team == DiceCombat.CREW:
		v.position = Vector2(CREW_X[mini(u.order, 2)], FEET_Y)
	else:
		var used := _enemy_slots.values()
		var slot := 0
		while slot in used:
			slot += 1
		_enemy_slots[u.id] = slot
		v.position = Vector2(ENEMY_X0 + slot * ENEMY_DX, FEET_Y - (34.0 if u.flying else 0.0) - (4.0 if u.backline else 0.0))
	units_layer.add_child(v)
	views[u.id] = v


# --- loop ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_wait -= delta
	while not _queue.is_empty() and _wait <= 0.0:
		var ev: Dictionary = _queue.pop_front()
		_handle(ev)
		_wait += _delay(ev)
	_busy = not _queue.is_empty()
	for id in views.keys():
		var v = views[id]
		if v.gone:
			v.queue_free()
			views.erase(id)
			_enemy_slots.erase(id)
	_update_hud()
	lines.queue_redraw()
	fx.tick(delta)
	if _queue.is_empty() and c.outcome != "" and not _ended:
		_ended = true
		get_tree().create_timer(1.0).timeout.connect(_show_end)


func _delay(ev: Dictionary) -> float:
	if instant:
		return 0.0
	match String(ev.type):
		"intent_fire":
			return STEP_SLOW
		"wave_start", "outcome":
			return 0.5
		"turn_start":
			return 0.15
		"damage", "heal", "shield", "death", "die_used", "hack":
			return STEP_FAST
	return 0.0


## Move the sim's new events into the replay queue.
func _drain() -> void:
	_queue.append_array(c.pop_events())


func _update_hud() -> void:
	trace_bar.color = UITheme.trace_color(c.trace)
	trace_bar.set_value(c.trace, 100.0, "%d%%" % int(c.trace))
	trace_bar.warn = c.trace >= 75.0
	ram_label.text = "RAM %d/%d" % [c.ram, c.ram_cap]
	heat_bar.color = Color("7ab8ff") if c.overheated else (Color("ff9f1c") if c.heat < c.heat_cap - 1 else UITheme.RED)
	heat_bar.set_value(c.heat, c.heat_cap, "LOCKED" if c.overheated else "%d/%d" % [c.heat, c.heat_cap])
	wave_label.text = "WAVE %d/%d  T%d" % [c.wave + 1, c.total_waves(), c.turn]
	bag_label.text = "€$ %d" % display_bag
	var over := c.outcome != "" or finished
	var rolling := c.phase == "roll"
	reroll_btn.text = "REROLL (%d)" % c.rerolls
	reroll_btn.disabled = over or _busy or not rolling or c.rerolls <= 0
	done_btn.text = "DONE ROLLING" if rolling else "END TURN"
	done_btn.disabled = over or _busy
	auto_btn.disabled = over or _busy
	var targets := _current_targets()
	for v in views.values():
		var u: DiceCombat.Unit = v.unit()
		v.show_intent = not _busy
		v.highlight = 0
		if not targets.is_empty() and u.alive:
			v.highlight = 1 if u.id in targets else -1
	for card in cards:
		card.highlight = 1 if card.uid in targets else 0
	for dv in die_views:
		var d: DiceCombat.Die = c.dice[dv.get_meta("die")]
		dv.face = d.face()
		dv.locked = d.locked
		dv.used = d.used
		dv.dim = not c.get_unit(d.owner).alive
		dv.selected = d.index == sel_die
		dv.valid = hack_slot >= 0 and d.index in targets and _hack_targets_dice()
	var ds := []
	var ports := c.crew_ports()
	for ref in c.daemons:
		ds.append(ChipDB.display_name(ref) + (" (dark)" if ChipDB.is_dark(ref, ports) else ""))
	daemon_label.text = "DAEMONS: " + (", ".join(ds) if not ds.is_empty() else "none")
	if sel_die < 0 and hack_slot < 0 and not _busy:
		info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		if c.phase == "roll":
			info.text = "Tap dice to lock them, REROLL the rest (%d left), then DONE ROLLING." % c.rerolls
		elif c.outcome == "":
			info.text = "Tap a die, then its target. Hacks cost RAM. Unused glitch dice fire by themselves."


func _hack_targets_dice() -> bool:
	return hack_slot >= 0 and String(ChipDB.get_def(c.hacks[hack_slot]).target) in ["die", "used_die"]


func _current_targets() -> Array:
	if hack_slot >= 0:
		return c.hack_targets(hack_slot)
	if sel_die >= 0:
		return c.valid_targets(c.dice[sel_die])
	return []


# --- input --------------------------------------------------------------------------------

func _input_blocked() -> bool:
	return _busy or finished or c.outcome != ""


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position
	if p.y < TOP_H or p.y > FIELD_BOTTOM:
		return
	var best := -1
	var best_d := 30.0
	for id in views:
		var v = views[id]
		if v.dead:
			continue
		var d: float = (p - v.body_pos()).length()
		if d < best_d:
			best_d = d
			best = id
	if best >= 0:
		_on_unit_tapped(best)
		get_viewport().set_input_as_handled()


func _on_unit_tapped(uid: int) -> void:
	if _input_blocked():
		return
	var u := c.get_unit(uid)
	if hack_slot >= 0:
		if c.hack(hack_slot, uid):
			hack_slot = -1
			targeting = -1
			_drain()
		else:
			_deny("Not a target for this hack")
		return
	if sel_die >= 0:
		var d: DiceCombat.Die = c.dice[sel_die]
		if c.use_die(d, uid):
			sel_die = -1
			_drain()
		else:
			_deny("Out of reach" if DiceDB.target_kind(d.face()) == "melee" else "Not a target for this die")
		return
	_show_info(u)


func _show_info(u: DiceCombat.Unit) -> void:
	if u == null:
		return
	if u.team == DiceCombat.ENEMY:
		var e: Dictionary = UnitDB.ENEMIES[u.kind]
		var it := UnitDB.intent_desc(u.intent) if not u.intent.is_empty() else "No intent"
		var tgt := c.get_unit(u.intent_target)
		if tgt != null and tgt.team == DiceCombat.CREW:
			it += " -> %s" % UnitDB.short_name({"name": tgt.name})
		info.text = "%s (%d/%d): %s %s" % [String(e.name).to_upper(), u.hp, u.max_hp, it, e.hint]
		info.add_theme_color_override("font_color", UITheme.TEXT)
	else:
		info.text = "%s %d/%d HP, incoming %d. Tap its dice to see the faces." % [UnitDB.short_name({"name": u.name}), u.hp, u.max_hp, c.incoming(u)]
		info.add_theme_color_override("font_color", UITheme.TEXT)


func _on_die(dv: DieView) -> void:
	if _input_blocked():
		return
	var d: DiceCombat.Die = c.dice[dv.get_meta("die")]
	if not c.get_unit(d.owner).alive:
		return
	if hack_slot >= 0 and _hack_targets_dice():
		if c.hack(hack_slot, d.index):
			hack_slot = -1
			targeting = -1
			_drain()
		else:
			_deny("Not a target for this hack")
		return
	_describe_die(d)
	if c.phase == "roll":
		c.toggle_lock(d)
		Audio.play("ui_click", -4.0, 1.4 if d.locked else 1.0)
		return
	if d.used:
		return
	if sel_die == d.index:
		var ts := c.valid_targets(d)
		if ts.size() == 1 and ts[0] == d.owner and DiceDB.target_kind(d.face()) in ["self", "none"]:
			c.use_die(d, d.owner)
			_drain()
		sel_die = -1
		return
	sel_die = d.index
	if c.valid_targets(d).is_empty():
		sel_die = -1
		_deny("Blank: nothing to do" if d.face().k == "blank" else "No target in reach")


func _describe_die(d: DiceCombat.Die) -> void:
	var f := d.face()
	var tail := ""
	match DiceDB.target_kind(f):
		"self", "none":
			tail = "  Tap again to use."
		"melee":
			tail = "  Tap a front enemy."
		"enemy":
			tail = "  Tap any enemy."
		"ally":
			tail = "  Tap a merc."
	if c.phase == "roll":
		tail = "  (locked)" if d.locked else ""
	info.text = "%s  [%s die: %s]%s" % [DiceDB.describe(f), d.which.to_upper(), DiceDB.dice_text(d.faces), tail]
	info.add_theme_color_override("font_color", DiceDB.kw(String(f.k)).color.lightened(0.3))


func _on_hack(slot: int) -> void:
	if _input_blocked():
		return
	sel_die = -1
	if hack_slot == slot:
		hack_slot = -1
		targeting = -1
		return
	var ref: String = c.hacks[slot]
	var d := ChipDB.get_def(ref)
	var why := c.hack_block(slot)
	if why != "":
		_deny({"ram": "Not enough RAM", "overheated": "Deck overheated: hacks locked this turn"}.get(why, "Can't run that now"))
		return
	info.text = "%s (%d RAM): %s" % [ChipDB.display_name(ref), c.hack_cost(slot), ChipDB.desc(ref)]
	info.add_theme_color_override("font_color", d.color)
	if d.target == "none":
		if c.hack(slot, -1):
			_drain()
		return
	if c.hack_targets(slot).is_empty():
		_deny("No valid target")
		return
	hack_slot = slot
	targeting = slot


func _on_reroll() -> void:
	if _input_blocked():
		return
	if c.reroll():
		for dv in die_views:
			if not c.dice[dv.get_meta("die")].locked:
				dv.tumble()
		_drain()


func _on_done() -> void:
	if _input_blocked():
		return
	sel_die = -1
	hack_slot = -1
	targeting = -1
	if c.phase == "roll":
		c.finish_roll()
		return
	c.end_turn()
	_drain()
	for dv in die_views:
		dv.tumble()


func _auto_turn() -> void:
	if _input_blocked():
		return
	sel_die = -1
	hack_slot = -1
	DiceBot.play_turn(c, "smart")
	_drain()


func _deny(msg: String) -> void:
	Audio.play("ui_error")
	info.text = msg
	info.add_theme_color_override("font_color", UITheme.RED)


func _show_help() -> void:
	_banner("HOW TO FIGHT", UITheme.CYAN, "Lock + reroll dice, then tap die -> target. Hacks spend RAM.", 2.4)


# --- events -> juice --------------------------------------------------------------------

func _view(id) -> Node2D:
	return views.get(id, null)


func _handle(ev: Dictionary) -> void:
	Audio.on_sim_event(ev)
	match String(ev.type):
		"wave_start":
			for u in c.units:
				if u.team == DiceCombat.ENEMY and u.alive:
					_add_view(u, true)
			if ev.boss:
				_banner("THE CYBERPSYCHO", UITheme.RED, "Berserk Charge hits the front merc for 7", 1.6)
			elif ev.index > 0:
				_banner("WAVE %d / %d" % [ev.index + 1, ev.total], UITheme.MAGENTA, "", 0.8)
		"summon":
			_add_view(c.get_unit(ev.unit), true)
			var v := _view(ev.unit)
			if v:
				fx.text(v.head_pos(), "CALLED IN", UITheme.RED, 9)
		"turn_start":
			if ev.turn > 1:
				for dv in die_views:
					dv.tumble()
		"die_used":
			var d: DiceCombat.Die = c.dice[ev.die]
			var dv: DieView = die_views.filter(func(x): return x.get_meta("die") == d.index)[0]
			var owner := _view(d.owner)
			if owner:
				owner.attack()
			var t := _view(ev.target)
			var col: Color = DiceDB.kw(String(ev.face.k)).color
			if t:
				front_fx.link(dv.get_global_rect().get_center(), t.body_pos(), col, 1.5, 0.35)
			if owner and t and t != owner and DiceDB.is_damage(ev.face):
				fx.tracer(owner.body_pos() + Vector2(10, -4), t.body_pos(), col, 2.0, 0.12)
		"damage":
			var t := _view(ev.target)
			if t == null:
				return
			var rest := int(ev.amount) - int(ev.absorbed)
			t.shown_hp -= rest
			var txt := str(rest) if ev.absorbed <= 0 else "%d (%d)" % [rest, int(ev.absorbed)]
			var col := Color("ff9a9a") if t.unit().team == DiceCombat.CREW else Color.WHITE
			if ev.kind in ["hack", "spoof"]:
				col = UITheme.CYAN
			elif ev.kind == "burn":
				col = Color("ff9f1c")
			fx.text(t.head_pos() + Vector2(0, 6), txt, col, 13 if rest >= 4 else 11)
			t.hit(Color.WHITE)
			fx.burst(t.body_pos(), col, 6, 70.0, 0.35)
		"heal":
			var t := _view(ev.target)
			if t:
				t.shown_hp += int(ev.amount)
				fx.text(t.head_pos() + Vector2(0, 6), "+%d" % int(ev.amount), UITheme.GREEN, 12)
				fx.burst(t.body_pos(), UITheme.GREEN, 6, 50.0, 0.4)
		"shield":
			var t := _view(ev.target)
			if t:
				fx.text(t.head_pos() + Vector2(0, 6), "+%d SHD" % int(ev.amount), Color("8ab4ff"), 10)
				fx.ring(t.position, 20.0, Color("3d8bff"), 0.4)
		"death":
			var t := _view(ev.unit)
			if t:
				t.die()
				var mine: bool = t.unit().team == DiceCombat.CREW
				fx.burst(t.body_pos(), UITheme.RED if mine else Color("ff6a2a"), 14, 110.0, 0.6)
				fx.text(t.head_pos(), "DOWN!" if mine else "", UITheme.RED, 14, 1.2)
				if mine:
					front_fx.flash = 0.7
					front_fx.flash_color = UITheme.RED
		"loot":
			var t := _view(ev.unit)
			display_bag += int(ev.amount)
			if t:
				fx.text(t.head_pos() - Vector2(0, 10), "+%d €$" % int(ev.amount), UITheme.YELLOW, 9)
		"dodge":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos(), "DODGE", UITheme.CYAN, 11)
		"stun":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos() - Vector2(0, 12), "STUNNED", UITheme.CYAN, 11)
				fx.burst(t.body_pos(), UITheme.CYAN, 10, 90.0, 0.4)
		"blocked":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos(), "BLOCKED", UITheme.TEXT_DIM, 10)
		"status":
			var t := _view(ev.unit)
			if t:
				fx.text(t.head_pos() - Vector2(0, 10), String(ev.text), UITheme.YELLOW, 8, 0.8)
		"intent_fire":
			var a := _view(ev.unit)
			var t := _view(ev.target)
			if a:
				a.attack()
			if a and t:
				var col := FightUnit._intent_color(String(ev.face.k))
				fx.tracer(a.body_pos() + Vector2(-10, -4), t.body_pos(), col, 2.0 if int(ev.face.v) < 5 else 4.0, 0.15)
				if String(ev.face.k) == "blast":
					fx.ring(t.position, 40.0, col, 0.4)
		"hack":
			var d := ChipDB.get_def(String(ev.ref))
			var slot := c.hacks.find(String(ev.ref))
			var t := _view(ev.target) if not String(d.target) in ["die", "used_die"] else null
			if t and slot >= 0:
				front_fx.link(hack_buttons[slot].get_global_rect().get_center(), t.body_pos(), d.color, 2.0, 0.45)
				fx.text(t.head_pos() - Vector2(0, 20), String(d.name).to_upper(), d.color, 9, 0.9)
		"daemon":
			fx.text(Vector2(180, TOP_H + 20), ChipDB.display_name(String(ev.ref)).to_upper(), UITheme.PURPLE, 9, 0.9)
		"overheat":
			_banner("DECK OVERHEATED", Color("ff9f1c"), "No hacks next turn  ·  Trace +%d" % int(ChipDB.CHASSIS.overheat_trace), 1.2)
		"trace":
			fx.text(Vector2(110, TOP_H + 8), "+%d TRACE" % int(round(ev.amount)), UITheme.PURPLE, 10, 1.0)
		"enrage":
			_banner("ENRAGED", Color("ff7a2a"), "+1 to every intent", 1.2)
		"wave_cleared":
			pass
		"outcome":
			match String(ev.outcome):
				"won": _banner("TARGET DOWN" if c.fight.get("boss", false) else "AREA SECURED", UITheme.GREEN, "", 1.2)
				"wiped": _banner("CREW FLATLINED", UITheme.RED, "", 1.2)
				"traced": _banner("CONNECTION BURNED", UITheme.RED, "Trace hit 100%", 1.2)


func _banner(text: String, col: Color, sub := "", hold := 1.4) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.12)
	_banner_tween.tween_property(banner_sub, "modulate:a", 1.0, 0.2).set_delay(0.08)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_property(banner_sub, "modulate:a", 0.0, 0.3)


# --- end of fight ---------------------------------------------------------------------------

func _show_end() -> void:
	if end_panel:
		return
	var r := c.result()
	end_panel = Control.new()
	end_panel.anchor_right = 1.0
	end_panel.anchor_bottom = 1.0
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(end_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.75)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	end_panel.add_child(dim)
	var o: String = r.outcome
	var boss: bool = c.fight.get("boss", false)
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
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var downs: int = r.crew.filter(func(x): return x.down).size()
	var lines_out := [
		["Turns", str(r.turns), UITheme.TEXT],
		["Kills", str(r.kills), UITheme.TEXT],
		["Eddies", "+%d €$" % r.bag, UITheme.YELLOW],
		["Trace", "+%d  (now %d%%)" % [int(round(r.trace_gain)), int(r.trace)], UITheme.PURPLE],
		["Intents cancelled", str(r.interrupts), UITheme.CYAN],
	]
	if downs > 0 and o == "won":
		lines_out.append(["Downed (get up with a scar)", str(downs), UITheme.RED])
	for ln in lines_out:
		var h := HBoxContainer.new()
		var a := UITheme.label(ln[0], 11, UITheme.TEXT_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UITheme.label(ln[1], 11, ln[2]))
		v.add_child(h)
	var cont := HubW.button("CONTINUE", _on_continue, 14, col, true)
	cont.custom_minimum_size = Vector2(160, 40)
	v.add_child(cont)


func _on_continue() -> void:
	if finished:
		return
	finished = true
	var standalone := get_parent() == get_tree().root
	Game.finish_fight(c.result())
	if standalone:
		get_tree().change_scene_to_file(MAIN_SCENE)


# --- inner widgets -------------------------------------------------------------------------

## Lines from each enemy's intent badge to the merc it targets.
class IntentLines:
	extends Node2D
	var scene  # the fight scene

	func _draw() -> void:
		if scene == null or scene._busy:
			return
		for e in scene.c.enemies():
			if e.intent.is_empty() or e.stunned:
				continue
			var a = scene.views.get(e.id, null)
			var t = scene.views.get(e.intent_target, null)
			if a == null:
				continue
			var k := String(e.intent.k)
			var col: Color = FightUnit._intent_color(k)
			if e.spoofed or e.hijacked:
				col = UITheme.TEXT_DIM
			var targets := []
			if k == "rampage":
				targets = scene.c.mercs().map(func(m): return scene.views.get(m.id, null))
			elif t != null and t.unit().team == DiceCombat.CREW:
				targets = [t]
			for tv in targets:
				if tv == null:
					continue
				var p0: Vector2 = a.badge_pos() + Vector2(0, 6)
				var p1: Vector2 = tv.head_pos()
				var mid := (p0 + p1) / 2.0 - Vector2(0, 26)
				var pts := PackedVector2Array()
				for i in 13:
					var f := float(i) / 12.0
					pts.append(p0.lerp(mid, f).lerp(mid.lerp(p1, f), f))
				for i in range(0, pts.size() - 1, 2):
					draw_line(pts[i], pts[i + 1], Color(col, 0.75), 1.5)
				draw_circle(p1, 2.5, col)


## Crew status card: face, name, HP, shield and the damage coming at this merc.
class CrewCard:
	extends Control
	signal pressed(uid: int)
	var c: DiceCombat
	var uid := 0
	var highlight := 0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(uid)
			accept_event()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var u := c.get_unit(uid)
		if u == null:
			return
		var font := ThemeDB.fallback_font
		var cd: Dictionary = UnitDB.CLASSES[u.kind]
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.04, 0.04, 0.09, 0.95))
		var border: Color = Color(cd.color).darkened(0.4)
		if highlight > 0:
			border = UITheme.GREEN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0))
		draw_rect(r, border, false, 2.0 if highlight > 0 else 1.0)
		var tex := PixelSprites.portrait(u.kind, u.seed)
		draw_texture_rect_region(tex, Rect2(3, 3, 22, 22), Rect2(3, 0, 10, 10), Color.WHITE if u.alive else Color(0.4, 0.4, 0.45))
		draw_string(font, Vector2(29, 12), UnitDB.short_name({"name": u.name}), HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 10, UITheme.TEXT)
		draw_string(font, Vector2(29, 23), String(cd.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 60, 8, cd.color)
		var bar := Rect2(4, 30, size.x - 8, 10)
		draw_rect(bar, Color(0, 0, 0, 0.8))
		if not u.alive:
			draw_string(font, bar.position + Vector2(0, 9), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 9, UITheme.RED)
			return
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * u.hp_pct(), bar.size.y)), UITheme.GREEN if u.hp_pct() > 0.35 else UITheme.YELLOW)
		var txt := "%d/%d" % [u.hp, u.max_hp] + ("  +%d" % u.shield if u.shield > 0 else "")
		draw_string_outline(font, bar.position + Vector2(0, 9), txt, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 9, 3, Color.BLACK)
		draw_string(font, bar.position + Vector2(0, 9), txt, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 9, Color.WHITE)
		# Incoming damage after shields: red and blinking when lethal.
		var inc := maxi(0, c.incoming(u) - u.shield)
		if u.dodge and inc > 0:
			draw_string(font, Vector2(size.x - 40, 23), "DODGE", HORIZONTAL_ALIGNMENT_RIGHT, 36, 8, UITheme.CYAN)
		elif inc > 0:
			var lethal := inc >= u.hp
			var ic := UITheme.RED if not lethal or fmod(_t, 0.5) < 0.3 else Color.WHITE
			draw_string(font, Vector2(size.x - 50, 23), ("LETHAL %d" if lethal else "IN %d") % inc, HORIZONTAL_ALIGNMENT_RIGHT, 46, 9, ic)


## A hack in the fixer row: tag, name, RAM cost; dim when it can't run.
class HackButton:
	extends Control
	signal pressed(slot: int)
	var scene  # the fight scene
	var slot := 0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(slot)
			accept_event()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c: DiceCombat = scene.c
		var ref: String = c.hacks[slot]
		var d := ChipDB.get_def(ref)
		var font := ThemeDB.fallback_font
		var ok := c.hack_block(slot) == "" and c.outcome == ""
		var col: Color = d.color
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(col.darkened(0.8), 1.0 if ok else 0.5))
		var border := col if ok else Color("3a3a58")
		if scene.hack_slot == slot:
			border = UITheme.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0))
		draw_rect(r, border, false, 2.0 if scene.hack_slot == slot else 1.0)
		draw_string(font, Vector2(0, 17), String(d.tag), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, col.lightened(0.3) if ok else UITheme.TEXT_DIM)
		draw_string(font, Vector2(0, 30), String(d.name), HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, UITheme.TEXT if ok else UITheme.TEXT_DIM)
		var cost := c.hack_cost(slot)
		draw_string(font, Vector2(0, 42), "%d RAM" % cost, HORIZONTAL_ALIGNMENT_CENTER, size.x, 8, UITheme.CYAN if c.ram >= cost else UITheme.RED)
