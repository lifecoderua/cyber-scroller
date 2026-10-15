extends Control
## Safehouse hub: header, tabs (contracts / crew / deck / market), toasts and modals.
## All game state lives in the Game autoload; views rebuild on Game.state_changed.

const TAB_NAMES := ["CONTRACTS", "CREW", "DECK", "MARKET"]
const TAB_SCRIPTS := [
	preload("res://scripts/hub/tab_contracts.gd"),
	preload("res://scripts/hub/tab_crew.gd"),
	preload("res://scripts/hub/tab_deck.gd"),
	preload("res://scripts/hub/tab_market.gd"),
]
const BG_SCRIPT := preload("res://scripts/hub/hub_bg.gd")
const RESULTS_SCRIPT := preload("res://scripts/hub/results_modal.gd")

static var _last_tab := 0
static var _hint_dismissed := false

## Id of an item that just changed (new runner, slotted soft): views flash it once.
var flash_id := ""

var _views: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _dirty: Array[bool] = [true, true, true, true]
var _current := -1
var _refresh_queued := false
var _launching := false

var _content: Control
var _toasts: VBoxContainer
var _fx_layer: Control
var _modal_layer: Control
var _title: HubTitle
var _eddies_chip: PanelContainer
var _eddies_label: Label
var _rep_label: Label
var _threat_pips: HubPips
var _shown_eddies := 0.0
var _eddies_target := 0
var _eddies_tween: Tween


func _ready() -> void:
	theme = _hub_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(BG_SCRIPT.new())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var root := HubW.vbox(4)
	margin.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_tabs())

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

	_fx_layer = _layer()
	_toasts = HubW.vbox(3)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 78
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_toasts)
	_modal_layer = _layer()

	_shown_eddies = Game.eddies
	_eddies_target = Game.eddies
	_update_header()
	Game.state_changed.connect(_on_state_changed)
	select_tab(_last_tab)

	if not Game.last_result.is_empty():
		show_results.call_deferred()
	else:
		_maybe_hint.call_deferred()


## Shared neon theme plus slimmer scrollbars for the dense hub lists.
func _hub_theme() -> Theme:
	var th: Theme = UITheme.get_theme().duplicate()
	th.set_stylebox("scroll", "VScrollBar", UITheme.box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 2, 2))
	th.set_stylebox("grabber", "VScrollBar", UITheme.box(UITheme.CYAN.darkened(0.45), UITheme.CYAN.darkened(0.45), 0, 2, 2))
	th.set_stylebox("grabber_highlight", "VScrollBar", UITheme.box(UITheme.CYAN, UITheme.CYAN, 0, 2, 2))
	th.set_stylebox("grabber_pressed", "VScrollBar", UITheme.box(UITheme.CYAN, UITheme.CYAN, 0, 2, 2))
	th.set_stylebox("tooltip_panel", "TooltipPanel", UITheme.box(Color(0.03, 0.03, 0.08, 0.96), UITheme.CYAN, 1, 2, 5))
	th.set_color("font_color", "TooltipLabel", UITheme.TEXT)
	th.set_font_size("font_size", "TooltipLabel", 10)
	return th


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# --- header / tabs -------------------------------------------------------

func _build_header() -> Control:
	var h := HubW.hbox(8)
	h.custom_minimum_size.y = 32
	_title = HubTitle.new("SAFEHOUSE", 18)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title)
	var sub := HubW.lbl("// fixer node 0x2077", 9, UITheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sub)
	h.add_child(HubW.spacer())

	var rep_box := HubW.hbox(4)
	rep_box.add_child(_vcenter(HubW.lbl("REP", 9, UITheme.TEXT_DIM)))
	_rep_label = _vcenter(HubW.lbl("0", 13, UITheme.PURPLE))
	rep_box.add_child(_rep_label)
	h.add_child(rep_box)

	var threat_box := HubW.hbox(4)
	threat_box.add_child(_vcenter(HubW.lbl("THREAT", 9, UITheme.TEXT_DIM)))
	_threat_pips = HubPips.new(1, 5, UITheme.GREEN)
	threat_box.add_child(_threat_pips)
	threat_box.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(threat_box)

	_eddies_chip = HubW.panel(UITheme.YELLOW.darkened(0.35), HubW.DEEP_BG, 1, 6)
	_eddies_chip.custom_minimum_size.x = 96
	_eddies_label = HubW.lbl("0 €$", 15, UITheme.YELLOW)
	_eddies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_eddies_chip.add_child(_eddies_label)
	h.add_child(_eddies_chip)

	var menu := HubW.button("SYS", _open_menu, 11)
	menu.custom_minimum_size = Vector2(44, 32)
	h.add_child(menu)
	return h


func _vcenter(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _build_tabs() -> Control:
	var h := HubW.hbox(4)
	for i in TAB_NAMES.size():
		var b := HubW.button(TAB_NAMES[i], select_tab.bind(i), 13)
		b.custom_minimum_size.y = 34
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
	var alert := i == 1 and Game.squad_runners().is_empty()
	if alert:
		accent = UITheme.RED
	b.text = TAB_NAMES[i] + (" (!)" if alert else "")
	if active:
		var s := UITheme.box(accent.darkened(0.7), accent, 1, 2)
		s.border_width_bottom = 3
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_color_override("font_color", accent.lightened(0.4))
		b.add_theme_color_override("font_hover_color", accent.lightened(0.4))
	else:
		HubW.restyle(b, accent)
		b.add_theme_color_override("font_color", UITheme.TEXT_DIM if not alert else UITheme.RED)


# --- state ---------------------------------------------------------------

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
	flash_id = ""


func _update_header() -> void:
	_rep_label.text = str(Game.rep)
	var mt := Game.max_threat()
	_threat_pips.set_value(mt, 5, HubW.threat_color(mt))
	var tb: Control = _threat_pips.get_parent()
	tb.tooltip_text = "Max contract threat %d. Next tier at %d rep." % [mt, mt * 4] if mt < 5 else "Max contract threat unlocked."
	_set_eddies(Game.eddies)


func _set_eddies(target: int) -> void:
	if target == _eddies_target:
		_eddies_label.text = UITheme.format_eddies(int(round(_shown_eddies)))
		return
	var delta := target - _eddies_target
	_eddies_target = target
	if _eddies_tween and _eddies_tween.is_valid():
		_eddies_tween.kill()
	_eddies_tween = create_tween()
	_eddies_tween.tween_method(_show_eddies, _shown_eddies, float(target), clampf(absf(delta) / 500.0, 0.3, 0.9)) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var col := UITheme.GREEN if delta > 0 else UITheme.MAGENTA
	HubFx.flash(_eddies_chip, col, 0.5)
	_float_text(("+%d" if delta > 0 else "%d") % delta, col, _eddies_chip)


func _show_eddies(v: float) -> void:
	_shown_eddies = v
	_eddies_label.text = UITheme.format_eddies(int(round(v)))


## Rising "+120" style number near a control.
func _float_text(text: String, color: Color, near: Control) -> void:
	var l := HubW.lbl(text, 12, color)
	l.add_theme_constant_override("outline_size", 3)
	_fx_layer.add_child(l)
	var p := near.global_position - global_position
	l.position = p + Vector2(near.size.x * 0.5 - 12, near.size.y - 2)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + 16, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	t.chain().tween_callback(l.queue_free)


# --- feedback ------------------------------------------------------------

func toast(text: String, color := UITheme.CYAN) -> void:
	while _toasts.get_child_count() >= 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var p := HubW.panel(color, HubW.DEEP_BG, 1, 7)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := HubW.lbl(text, 11, color.lightened(0.25))
	p.add_child(l)
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.12)
	t.tween_interval(1.7)
	t.tween_property(p, "modulate:a", 0.0, 0.3)
	t.tween_callback(p.queue_free)


## Error feedback: shake the control, flash red, toast the reason.
func deny(c: Control, reason: String) -> void:
	HubFx.shake(c)
	toast(reason, UITheme.RED)


func deny_money(c: Control) -> void:
	deny(c, "Not enough eddies")
	HubFx.shake(_eddies_chip, 3.0)


func screen_flash(color: Color, alpha := 0.35, time := 0.35) -> void:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(color, alpha)
	_fx_layer.add_child(r)
	var t := r.create_tween()
	t.tween_property(r, "color:a", 0.0, time)
	t.tween_callback(r.queue_free)


# --- modals --------------------------------------------------------------

func open_modal(panel: Control, dim := 0.72) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.01, 0.04, dim)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.add_child(panel)
	_modal_layer.add_child(overlay)
	overlay.modulate.a = 0.0
	var t := overlay.create_tween()
	t.tween_property(overlay, "modulate:a", 1.0, 0.12)
	panel.scale = Vector2(0.86, 0.86)
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	var t2 := panel.create_tween()
	t2.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return overlay


func close_modal(overlay: Control) -> void:
	if not is_instance_valid(overlay) or overlay.has_meta("closing"):
		return
	overlay.set_meta("closing", true)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := overlay.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, 0.12)
	t.tween_callback(overlay.queue_free)


## Closes the modal that contains `node`.
func close_from(node: Node) -> void:
	var n := node
	while n and n.get_parent() != _modal_layer:
		n = n.get_parent()
	if n is Control:
		close_modal(n)


func modal_panel(border: Color, min_w := 280.0) -> Array:
	var p := HubW.panel(border, Color(0.03, 0.03, 0.08, 0.97), 2, 12)
	p.custom_minimum_size.x = min_w
	var v := HubW.vbox(6)
	p.add_child(v)
	return [p, v]


func confirm(title: String, body: String, yes_text: String, on_yes: Callable, color := UITheme.RED) -> void:
	var pv := modal_panel(color)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl(title, 15, color))
	v.add_child(HubW.wrap(HubW.lbl(body, 11, UITheme.TEXT)))
	v.add_child(HubW.line(Color(color, 0.3)))
	var row := HubW.hbox(8)
	var cancel := HubW.button("CANCEL", func(): close_from(v), 12, UITheme.TEXT_DIM)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var yes := HubW.button(yes_text, func():
		close_from(v)
		on_yes.call(), 12, color, true)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	row.add_child(yes)
	v.add_child(row)
	open_modal(pv[0])


func _open_menu() -> void:
	var pv := modal_panel(UITheme.CYAN, 240)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl("SYSTEM", 15, UITheme.CYAN))
	v.add_child(HubW.lbl("Jobs run: %d   Crew: %d   Soft: %d" % [Game.missions_run, Game.roster.size(), Game.owned_soft.size()], 10, UITheme.TEXT_DIM))
	var how := HubW.button("HOW TO PLAY", func():
		close_from(v)
		show_hint(), 12)
	v.add_child(how)
	var reset := HubW.button("RESET SAVE", func():
		close_from(v)
		confirm("WIPE SAVE?", "Your crew, soft, eddies and rep will be erased. A fresh safehouse starts from zero.", "WIPE", _reset_save), 12, UITheme.RED)
	v.add_child(reset)
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
	if Game.missions_run == 0 and not _hint_dismissed:
		show_hint()


func show_hint() -> void:
	var pv := modal_panel(UITheme.CYAN, 330)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl("WELCOME, FIXER", 16, UITheme.CYAN))
	var lines := [
		["You never hit the street. Your runners fight on their own; you back them up from the net.", UITheme.TEXT],
		["Pick a contract, check your CREW and DECK, then LAUNCH.", UITheme.TEXT],
		["Tap a soft card to pause time, then tap a target to cast.", UITheme.YELLOW],
		["Between fights you may EXTRACT to keep the bag. A wipe means your runners flatline.", UITheme.MAGENTA],
	]
	for ln in lines:
		var row := HubW.hbox(6)
		var arrow := HubW.lbl(">", 11, UITheme.CYAN)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(arrow)
		row.add_child(HubW.wrap(HubW.lbl(ln[0], 11, ln[1])))
		v.add_child(row)
	var ok := HubW.button("GOT IT", func():
		_hint_dismissed = true
		close_from(v), 13, UITheme.CYAN, true)
	v.add_child(ok)
	open_modal(pv[0])


func show_results() -> void:
	var res: Dictionary = Game.last_result
	if res.is_empty():
		return
	var m: PanelContainer = RESULTS_SCRIPT.new()
	m.setup(self, res)
	var overlay := open_modal(m, 0.8)
	m.overlay = overlay
	m.play()


## Called by the results modal when closed.
func results_closed() -> void:
	Game.last_result = {}
	_maybe_hint()


# --- mission -------------------------------------------------------------

func launch(index: int, from: Control) -> void:
	if _launching:
		return
	if not Game.can_start_mission():
		deny(from, "No runners in the squad. Go to CREW.")
		return
	_launching = true
	_title.burst(0.5)
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color(UITheme.CYAN, 0.0)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(cover)
	var l := HubW.lbl("JACKING IN", 22, UITheme.CYAN)
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
	for i in 3:
		t.tween_callback(func(): l.text = "JACKING IN" + ".".repeat(i + 1))
		t.tween_interval(0.12)
	t.tween_callback(func():
		_launching = false
		Game.start_mission(index))
