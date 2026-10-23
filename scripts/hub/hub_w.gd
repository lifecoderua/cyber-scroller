class_name HubW
extends RefCounted
## Widget builders shared by the hub tabs.

const PANEL_BG := Color(0.078, 0.078, 0.157, 0.9)
const DEEP_BG := Color(0.035, 0.035, 0.08, 0.94)
const THREAT_NAMES := ["LOW", "MODERATE", "HIGH", "SEVERE", "LETHAL"]
const THREAT_COLORS := [Color("4cff8f"), Color("2de2e6"), Color("f9c80e"), Color("ff9f1c"), Color("ff2a2a")]
const RARITY_COLORS := {"common": Color("a8a8c8"), "uncommon": Color("2de2e6"), "rare": Color("f9c80e")}


static func panel(border: Color, bg := PANEL_BG, bw := 1, pad := 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(bg, border, bw, 2, pad))
	return p


static func lbl(text: String, size := 12, color := UITheme.TEXT) -> Label:
	var l := UITheme.label(text, size, color)
	if size <= 10:
		l.add_theme_constant_override("outline_size", 0)
	return l


## Single line that trims with an ellipsis instead of pushing the layout.
static func clip(l: Label) -> Label:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 10
	return l


static func wrap(l: Label, lines := 0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 10
	if lines > 0:
		l.max_lines_visible = lines
	return l


static func vbox(sep := 4) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep := 4) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func spacer(vertical := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func line(color: Color, h := 1) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## Full-body portrait (16x24 at `scale`).
static func portrait(cls: String, vseed: int, scale := 2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PixelSprites.portrait(cls, vseed)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(16, 24) * scale
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Head-and-shoulders crop of the portrait.
static func headshot(cls: String, vseed: int, scale := 2) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = PixelSprites.portrait(cls, vseed)
	at.region = Rect2(0, 0, 16, 13)
	var t := TextureRect.new()
	t.texture = at
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(16, 13) * scale
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func button(text: String, cb: Callable, size := 12, accent := UITheme.CYAN, filled := false) -> Button:
	var b := UITheme.button(text, cb, size)
	b.custom_minimum_size = Vector2(0, 32)
	b.focus_mode = Control.FOCUS_NONE
	restyle(b, accent, filled)
	HubFx.juice(b)
	return b


static func restyle(b: Button, accent: Color, filled := false) -> void:
	var bg := accent.darkened(0.62) if filled else PANEL_BG
	b.add_theme_stylebox_override("normal", UITheme.box(bg, accent.darkened(0.15 if filled else 0.35)))
	b.add_theme_stylebox_override("hover", UITheme.box(bg.lightened(0.08), accent))
	b.add_theme_stylebox_override("pressed", UITheme.box(accent.darkened(0.45), accent))
	b.add_theme_color_override("font_color", accent.lightened(0.55) if filled else UITheme.TEXT)
	b.add_theme_color_override("font_hover_color", accent.lightened(0.3))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


static func threat_color(t: int) -> Color:
	return THREAT_COLORS[clampi(t, 1, 5) - 1]


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, UITheme.TEXT_DIM)


static func class_color(cls: String) -> Color:
	return UnitDB.CLASSES[cls].color


static func _num(f: float) -> String:
	if is_equal_approx(f, roundf(f)):
		return str(int(roundf(f)))
	return "%.1f" % f


static func short_name(m: Dictionary) -> String:
	return UnitDB.short_name(m)
