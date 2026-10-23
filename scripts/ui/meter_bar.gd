class_name MeterBar
extends Control
## Small labelled bar (Trace, HP, chrome). value / max_value, colour, optional label and
## value text drawn inside. Quarter ticks when `ticks` is on.

var value := 0.0
var max_value := 100.0
var color := UITheme.CYAN
var label := ""
var text := ""
var ticks := false
var warn := false       # blink (over cap / danger)
var _t := 0.0
var _font: Font


func _init(p_label := "", p_color := UITheme.CYAN, h := 12.0) -> void:
	label = p_label
	color = p_color
	custom_minimum_size = Vector2(40, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_value(v: float, m: float, txt := "") -> void:
	value = v
	max_value = m
	text = txt
	queue_redraw()


func _process(delta: float) -> void:
	if warn:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var lw := 0.0
	if label != "":
		lw = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 4
		draw_string(_font, Vector2(0, size.y - 2), label, HORIZONTAL_ALIGNMENT_LEFT, lw, 8, color)
	var r := Rect2(lw, 0, size.x - lw, size.y)
	draw_rect(r, Color(0, 0, 0, 0.7))
	var k := clampf(value / maxf(0.001, max_value), 0.0, 1.0)
	var c := color
	if warn and fmod(_t, 0.6) < 0.3:
		c = Color.WHITE
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * k, r.size.y - 2)), c)
	if ticks:
		for q in [0.25, 0.5, 0.75]:
			var x: float = r.position.x + r.size.x * q
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.6))
	if value > max_value:
		draw_rect(r, UITheme.RED, false, 1.0)
	if text != "":
		var fs := int(clampf(size.y - 3, 7, 10))
		draw_string_outline(_font, Vector2(r.position.x, r.position.y + size.y / 2.0 + fs / 2.5), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(_font, Vector2(r.position.x, r.position.y + size.y / 2.0 + fs / 2.5), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, UITheme.TEXT)
