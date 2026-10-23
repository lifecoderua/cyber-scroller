class_name ScreenBase
extends Control
## Shared plumbing for full-screen UI scenes (hub, run): background, fx / toast / modal
## layers, toasts, deny feedback, screen flashes, confirm dialogs.

var _fx_layer: Control
var _toasts: VBoxContainer
var _modal_layer: Control


## Call from _ready() after building the screen content.
func build_layers(toast_top := 64.0) -> void:
	_fx_layer = _layer()
	_toasts = HubW.vbox(3)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = toast_top
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_toasts)
	_modal_layer = _layer()


## Shared neon theme plus slimmer scrollbars for dense lists.
static func screen_theme() -> Theme:
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


func toast(text: String, color := UITheme.CYAN) -> void:
	while _toasts.get_child_count() >= 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var p := HubW.panel(color, HubW.DEEP_BG, 1, 7)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := HubW.lbl(text, 11, color.lightened(0.25))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.12)
	t.tween_interval(1.7)
	t.tween_property(p, "modulate:a", 0.0, 0.3)
	t.tween_callback(p.queue_free)


## Error feedback: shake the control, toast the reason.
func deny(c: Control, reason: String) -> void:
	if c:
		HubFx.shake(c)
	toast(reason, UITheme.RED)
	Audio.play("ui_error")


func screen_flash(color: Color, alpha := 0.35, time := 0.35) -> void:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(color, alpha)
	_fx_layer.add_child(r)
	var t := r.create_tween()
	t.tween_property(r, "color:a", 0.0, time)
	t.tween_callback(r.queue_free)


## Rising "+12" style number near a control.
func float_text(text: String, color: Color, near: Control) -> void:
	var l := HubW.lbl(text, 12, color)
	l.add_theme_constant_override("outline_size", 3)
	_fx_layer.add_child(l)
	var p := near.global_position - global_position
	l.position = p + Vector2(near.size.x * 0.5 - 12, near.size.y - 2)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + 16, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	t.chain().tween_callback(l.queue_free)


# --- modals ------------------------------------------------------------------------

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
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.12)
	panel.scale = Vector2(0.86, 0.86)
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	panel.create_tween().tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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


func modal_open() -> bool:
	for c in _modal_layer.get_children():
		if not c.has_meta("closing"):
			return true
	return false


## [PanelContainer, VBoxContainer] for a modal body.
func modal_panel(border: Color, min_w := 320.0) -> Array:
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


## Pick one of several options in a modal. options: Array of [label, sublabel, color].
## on_pick(index) is called; CANCEL closes without a call.
func choose(title: String, options: Array, on_pick: Callable, color := UITheme.CYAN) -> void:
	var pv := modal_panel(color)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl(title, 14, color))
	for i in options.size():
		var o: Array = options[i]
		var b := HubW.button("", func():
			close_from(v)
			on_pick.call(i), 11, o[2] if o.size() > 2 else color)
		b.custom_minimum_size.y = 40
		var box := HubW.vbox(0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 8
		box.offset_top = 4
		box.add_child(HubW.lbl(String(o[0]), 11, UITheme.TEXT))
		if o.size() > 1 and String(o[1]) != "":
			box.add_child(HubW.lbl(String(o[1]), 9, UITheme.TEXT_DIM))
		b.add_child(box)
		v.add_child(b)
	v.add_child(HubW.button("CANCEL", func(): close_from(v), 11, UITheme.TEXT_DIM))
	open_modal(pv[0])
