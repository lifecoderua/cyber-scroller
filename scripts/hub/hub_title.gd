class_name HubTitle
extends Control
## Header title with chromatic ghosts, a faint flicker and the occasional glitch burst.

const GLYPHS := "#$%&*+=?@01<>/\\|_"

var text := "SAFEHOUSE"
var font_size := 17
var _main: Label
var _ghost_a: Label
var _ghost_b: Label
var _next_glitch := 1.2
var _glitch_left := 0.0


func _init(t := "SAFEHOUSE", fs := 17) -> void:
	text = t
	font_size = fs
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_a = _mk(UITheme.MAGENTA, 0.75)
	_ghost_b = _mk(UITheme.CYAN, 0.65)
	_main = _mk(UITheme.TEXT, 1.0)
	_main.add_theme_constant_override("outline_size", 0)


func _ready() -> void:
	custom_minimum_size = _main.get_combined_minimum_size() + Vector2(3, 0)
	_rest()


func _mk(c: Color, a: float) -> Label:
	var l := UITheme.label(text, font_size, c)
	l.add_theme_constant_override("outline_size", 0)
	l.modulate.a = a
	add_child(l)
	return l


func _rest() -> void:
	_main.text = text
	_main.position = Vector2(1, 0)
	_ghost_a.position = Vector2(0, 0)
	_ghost_b.position = Vector2(2, 0)
	_ghost_a.text = text
	_ghost_b.text = text


func _process(delta: float) -> void:
	if _glitch_left > 0.0:
		_glitch_left -= delta
		var chars := []
		for i in text.length():
			chars.append(GLYPHS[randi() % GLYPHS.length()] if randf() < 0.22 else text[i])
		_main.text = "".join(chars)
		_ghost_a.position = Vector2(randf_range(-4, -1), randf_range(-1, 1))
		_ghost_b.position = Vector2(randf_range(3, 6), randf_range(-1, 1))
		_main.position.x = randf_range(0, 2)
		if randf() < 0.5:
			_ghost_a.text = _main.text
		if _glitch_left <= 0.0:
			_rest()
		return
	_next_glitch -= delta
	# Subtle neon flicker.
	_main.modulate.a = 0.72 if randf() < 0.015 else 1.0
	if _next_glitch <= 0.0:
		_glitch_left = randf_range(0.08, 0.22)
		_next_glitch = randf_range(1.8, 5.0)


## Forces a glitch burst (used on big events).
func burst(time := 0.3) -> void:
	_glitch_left = time
