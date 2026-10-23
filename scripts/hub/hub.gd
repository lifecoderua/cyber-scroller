extends ScreenBase
## Safehouse hub (portrait): header, the current tab, a thumb-zone tab bar (JOBS / NET /
## STASH), toasts and modals. Meta state lives in the Game autoload; views rebuild on
## Game.state_changed.

const TAB_NAMES := ["JOBS", "NET", "STASH"]
const TAB_NODES := 1
const TAB_SCRIPTS := [
	preload("res://scripts/hub/tab_contracts.gd"),
	preload("res://scripts/hub/tab_nodes.gd"),
	preload("res://scripts/hub/tab_stash.gd"),
]
const BG_SCRIPT := preload("res://scripts/hub/hub_bg.gd")
const RESULTS_SCRIPT := preload("res://scripts/hub/results_modal.gd")

static var _last_tab := 0
static var _hint_dismissed := false

var _views: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _dirty: Array[bool] = [true, true, true]
var _current := -1
var _refresh_queued := false
var _launching := false

var _content: Control
var _title: HubTitle
var _rep_label: Label
var _threat_pips: HubPips
var _shards_chip: PanelContainer
var _shards_label: Label
var _shown_shards := -1


func _ready() -> void:
	theme = screen_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(BG_SCRIPT.new())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var root := HubW.vbox(6)
	margin.add_child(root)
	root.add_child(_build_header())
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	root.add_child(_content)
	for i in TAB_SCRIPTS.size():
		var v: Control = TAB_SCRIPTS[i].new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.visible = false
		_content.add_child(v)
		v.setup(self)
		_views.append(v)
	root.add_child(_build_tabs())
	build_layers(84)

	_update_header()
	Game.state_changed.connect(_on_state_changed)
	select_tab(_last_tab)

	if Game.run != null:
		_resume_banner.call_deferred()
	elif not Game.last_result.is_empty():
		show_results.call_deferred()
	else:
		_maybe_hint.call_deferred()


# --- header / tabs -------------------------------------------------------------------

func _build_header() -> Control:
	var v := HubW.vbox(4)
	var h := HubW.hbox(8)
	_title = HubTitle.new("SAFEHOUSE", 18)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title)
	h.add_child(HubW.spacer())
	var menu := HubW.button("SYS", _open_menu, 11)
	menu.custom_minimum_size = Vector2(46, 32)
	h.add_child(menu)
	v.add_child(h)
	var row := HubW.hbox(8)
	var rep_box := HubW.hbox(4)
	rep_box.add_child(_vcenter(HubW.lbl("REP", 9, UITheme.TEXT_DIM)))
	_rep_label = _vcenter(HubW.lbl("0", 13, UITheme.PURPLE))
	rep_box.add_child(_rep_label)
	row.add_child(rep_box)
	var threat_box := HubW.hbox(4)
	threat_box.add_child(_vcenter(HubW.lbl("THREAT", 9, UITheme.TEXT_DIM)))
	_threat_pips = HubPips.new(1, 5, UITheme.GREEN)
	threat_box.add_child(_threat_pips)
	threat_box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(threat_box)
	row.add_child(HubW.spacer())
	_shards_chip = HubW.panel(HubShard.COLOR.darkened(0.35), HubW.DEEP_BG, 1, 6)
	_shards_chip.custom_minimum_size.x = 64
	_shards_chip.tooltip_text = "Data Shards: spend them in NET"
	var sh := HubW.hbox(4)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(HubShard.new(11))
	_shards_label = HubW.lbl("0", 15, HubShard.COLOR.lightened(0.3))
	_shards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shards_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(_shards_label)
	_shards_chip.add_child(sh)
	row.add_child(_shards_chip)
	v.add_child(row)
	return v


func _vcenter(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _build_tabs() -> Control:
	var h := HubW.hbox(4)
	for i in TAB_NAMES.size():
		var b := HubW.button(TAB_NAMES[i], select_tab.bind(i), 13)
		b.custom_minimum_size.y = 44
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		_tab_buttons.append(b)
	return h


func select_tab(i: int) -> void:
	i = clampi(i, 0, _views.size() - 1)
	if i == _current:
		return
	_current = i
	_last_tab = i
	for k in _views.size():
		_views[k].visible = k == i
		_style_tab(k, k == i)
	if _dirty[i]:
		_dirty[i] = false
		_views[i].refresh()
	var v := _views[i]
	v.modulate.a = 0.0
	v.offset_left = 12
	v.offset_right = 12
	var t := v.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(v, "modulate:a", 1.0, 0.16)
	t.tween_property(v, "offset_left", 0.0, 0.2)
	t.tween_property(v, "offset_right", 0.0, 0.2)
	if v.has_method("on_show"):
		v.on_show()


func _style_tab(i: int, active: bool) -> void:
	var b := _tab_buttons[i]
	var accent := UITheme.CYAN
	var ready := i == TAB_NODES and Game.nodes_affordable() > 0
	if i == TAB_NODES:
		accent = HubShard.COLOR
	b.text = TAB_NAMES[i] + (" +" if ready else "")
	if active:
		var s := UITheme.box(accent.darkened(0.7), accent, 1, 2)
		s.border_width_top = 3
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_color_override("font_color", accent.lightened(0.4))
		b.add_theme_color_override("font_hover_color", accent.lightened(0.4))
	else:
		HubW.restyle(b, accent)
		b.add_theme_color_override("font_color", HubShard.COLOR.lightened(0.3) if ready else UITheme.TEXT_DIM)


# --- state ---------------------------------------------------------------------------

func _on_state_changed() -> void:
	for i in _dirty.size():
		_dirty[i] = true
	if not _refresh_queued:
		_refresh_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_refresh_queued = false
	_update_header()
	for k in _views.size():
		_style_tab(k, k == _current)
	if _current >= 0:
		_dirty[_current] = false
		_views[_current].refresh()


func _update_header() -> void:
	_rep_label.text = str(Game.rep)
	var mt := Game.max_threat()
	_threat_pips.set_value(mt, 5, HubW.threat_color(mt))
	var tb: Control = _threat_pips.get_parent()
	tb.tooltip_text = "Max contract threat %d. Next tier at %d rep." % [mt, Game.next_threat_rep()] if mt < 5 else "Max contract threat unlocked."
	_set_shards(Game.shards)


func _set_shards(v: int) -> void:
	if _shown_shards >= 0 and v != _shown_shards:
		var delta := v - _shown_shards
		var col := HubShard.COLOR.lightened(0.3) if delta > 0 else UITheme.MAGENTA
		HubFx.flash(_shards_chip, col, 0.5)
		float_text(("+%d" if delta > 0 else "%d") % delta, col, _shards_chip)
	_shown_shards = v
	_shards_label.text = str(v)


func deny_shards(c: Control) -> void:
	deny(c, "Not enough Data Shards. Run more jobs.")
	HubFx.shake(_shards_chip, 3.0)


# --- modals --------------------------------------------------------------------------

func _open_menu() -> void:
	var pv := modal_panel(UITheme.CYAN, 260)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl("SYSTEM", 15, UITheme.CYAN))
	v.add_child(HubW.lbl("Runs: %d   Won: %d   Stash: %d" % [Game.runs_played, Game.runs_won, Game.stash.size()], 10, UITheme.TEXT_DIM))
	v.add_child(HubW.button("HOW TO PLAY", func():
		close_from(v)
		show_hint(), 12))
	v.add_child(Audio.mute_row())
	v.add_child(HubW.button("RESET SAVE", func():
		close_from(v)
		confirm("WIPE SAVE?", "Shards, rep, the skill tree and the stash will be erased.", "WIPE", _reset_save), 12, UITheme.RED))
	v.add_child(HubW.button("CLOSE", func(): close_from(v), 12, UITheme.TEXT_DIM))
	open_modal(pv[0])


func _reset_save() -> void:
	_hint_dismissed = false
	Game.new_game()
	screen_flash(UITheme.CYAN, 0.4, 0.5)
	_title.burst(0.4)
	toast("Save wiped. Welcome back, fixer.", UITheme.CYAN)
	_maybe_hint.call_deferred()


func _maybe_hint() -> void:
	if Game.runs_played == 0 and not _hint_dismissed:
		show_hint()


func show_hint() -> void:
	var pv := modal_panel(UITheme.CYAN, 320)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl("WELCOME, FIXER", 16, UITheme.CYAN))
	var lines := [
		["You never hit the street. Pick a job, then a crew of hired guns. They fight on their own.", UITheme.TEXT],
		["Fights are turns of dice. Each merc rolls a gear die and a chrome die; lock, reroll, then use them.", UITheme.YELLOW],
		["Enemies show their intents first. Kill, stun, shield or taunt before they act. Hacks spend RAM.", UITheme.CYAN],
		["After each fight pick ONE piece of loot: gear changes a merc's dice, chips are hacks and daemons.", UITheme.GREEN],
		["Trace is your HP. At 100% the run is burned. Subnets and stealth keep it low.", UITheme.MAGENTA],
	]
	for ln in lines:
		var row := HubW.hbox(6)
		var arrow := HubW.lbl(">", 11, UITheme.CYAN)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(arrow)
		row.add_child(HubW.wrap(HubW.lbl(ln[0], 11, ln[1])))
		v.add_child(row)
	v.add_child(HubW.button("GOT IT", func():
		_hint_dismissed = true
		close_from(v), 13, UITheme.CYAN, true))
	open_modal(pv[0])


func show_results() -> void:
	if Game.last_result.is_empty():
		return
	var m: PanelContainer = RESULTS_SCRIPT.new()
	m.setup(self, Game.last_result)
	var overlay := open_modal(m, 0.8)
	m.overlay = overlay
	m.play()


## Called by the results modal when closed.
func results_closed() -> void:
	Game.last_result = {}
	_maybe_hint()


func _resume_banner() -> void:
	confirm("RUN IN PROGRESS", "Your crew is still out there: %s." % String(Game.run.contract.get("title", "")), "RESUME",
		func(): Game.goto(Game.start_screen()), UITheme.CYAN)


# --- runs ----------------------------------------------------------------------------

func launch(index: int, _from: Control) -> void:
	if _launching:
		return
	_launching = true
	_title.burst(0.5)
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color(UITheme.CYAN, 0.0)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(cover)
	var l := HubW.lbl("CALLING THE CREWS", 18, UITheme.CYAN)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	cover.add_child(l)
	var t := cover.create_tween()
	t.tween_property(cover, "color", Color(UITheme.CYAN, 0.55), 0.06)
	t.tween_property(cover, "color", Color(UITheme.BG, 0.97), 0.25)
	t.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	t.tween_interval(0.3)
	t.tween_callback(func():
		_launching = false
		Game.start_run(index))
