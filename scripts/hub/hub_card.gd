class_name HubCard
extends Button
## A tappable card: a Button that hosts arbitrary content in a VBox.
## Call seal() after filling `content` so children don't eat the input.

var content: VBoxContainer
var pad := 5


func _init(accent: Color, bg := Color(UITheme.PANEL, 0.92), border_w := 1, p := 5) -> void:
	pad = p
	focus_mode = Control.FOCUS_NONE
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = pad
	content.offset_top = pad
	content.offset_right = -pad
	content.offset_bottom = -pad
	content.minimum_size_changed.connect(update_minimum_size)
	set_accent(accent, bg, border_w)
	HubFx.juice(self)


func set_accent(accent: Color, bg: Color, border_w := 1) -> void:
	add_theme_stylebox_override("normal", UITheme.box(bg, accent.darkened(0.35), border_w, 2, 0))
	add_theme_stylebox_override("hover", UITheme.box(bg.lightened(0.07), accent, border_w, 2, 0))
	add_theme_stylebox_override("pressed", UITheme.box(accent.darkened(0.6), accent, border_w, 2, 0))
	add_theme_stylebox_override("disabled", UITheme.box(bg.darkened(0.3), accent.darkened(0.6), border_w, 2, 0))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _get_minimum_size() -> Vector2:
	if content == null:
		return Vector2.ZERO
	return content.get_combined_minimum_size() + Vector2(pad, pad) * 2.0


func seal() -> void:
	_ignore(content)


static func _ignore(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore(c)
