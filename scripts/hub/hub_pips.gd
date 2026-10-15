class_name HubPips
extends Control
## Tiny pixel indicators: threat skulls or RAM cells.

enum Mode { SKULL, CELL }

var value := 0
var max_value := 5
var color := UITheme.CYAN
var mode := Mode.SKULL


func _init(v := 0, m := 5, c := UITheme.CYAN, md := Mode.SKULL) -> void:
	mode = md
	set_value(v, m, c)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: int, m: int, c: Color) -> void:
	value = v
	max_value = m
	color = c
	if mode == Mode.SKULL:
		custom_minimum_size = Vector2(maxi(1, max_value * 9 - 2), 7)
	else:
		custom_minimum_size = Vector2(maxi(1, max_value * 5 - 1), 9)
	queue_redraw()


func _draw() -> void:
	var y := floorf((size.y - custom_minimum_size.y) * 0.5)
	for i in max_value:
		var on := i < value
		if mode == Mode.SKULL:
			var x := i * 9.0
			var col := color if on else Color(1, 1, 1, 0.13)
			draw_rect(Rect2(x, y, 7, 5), col)
			draw_rect(Rect2(x + 1, y + 5, 5, 2), col)
			if on:
				draw_rect(Rect2(x + 1, y + 2, 2, 2), UITheme.BG)
				draw_rect(Rect2(x + 4, y + 2, 2, 2), UITheme.BG)
				draw_rect(Rect2(x + 3, y + 6, 1, 1), UITheme.BG)
		else:
			var x2 := i * 5.0
			draw_rect(Rect2(x2, y, 4, 9), color if on else Color(color, 0.15))
			if on:
				draw_rect(Rect2(x2, y, 4, 2), color.lightened(0.5))
