class_name UITheme
extends RefCounted
## Shared neon UI theme and palette. Use UITheme.get_theme() on root Controls.

const BG := Color("0b0b18")
const PANEL := Color("141428")
const PANEL_HI := Color("1e1e3a")
const CYAN := Color("2de2e6")
const MAGENTA := Color("ff3d81")
const YELLOW := Color("f9c80e")
const GREEN := Color("4cff8f")
const RED := Color("ff2a2a")
const PURPLE := Color("b388ff")
const TEXT := Color("e6e6f0")
const TEXT_DIM := Color("8a8aa8")

const FONT_SIZE := 12

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	t.set_stylebox("normal", "Button", box(PANEL, CYAN.darkened(0.4)))
	t.set_stylebox("hover", "Button", box(PANEL_HI, CYAN))
	t.set_stylebox("pressed", "Button", box(CYAN.darkened(0.6), CYAN))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.3), TEXT_DIM.darkened(0.5)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", CYAN)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))

	t.set_stylebox("panel", "PanelContainer", box(PANEL, CYAN.darkened(0.55)))
	t.set_stylebox("panel", "Panel", box(PANEL, CYAN.darkened(0.55)))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 2)

	t.set_stylebox("background", "ProgressBar", box(Color("0a0a14"), Color("2a2a44"), 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(CYAN, CYAN, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("scroll", "VScrollBar", box(Color("0a0a14"), Color("0a0a14"), 0, 2))
	t.set_stylebox("grabber", "VScrollBar", box(CYAN.darkened(0.5), CYAN.darkened(0.5), 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(CYAN, CYAN, 0, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(CYAN, CYAN, 0, 2))
	_theme = t
	return t


static func box(bg: Color, border: Color, border_w := 1, radius := 2, pad := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func label(text: String, size := FONT_SIZE, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, size := FONT_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_press)
	return b


static func format_eddies(n: int) -> String:
	return "%d €$" % n
