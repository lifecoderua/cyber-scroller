extends Node2D
## Minimal stand-in for CityBackdrop (used only if res://scripts/art/city_backdrop.gd is
## missing). Same API: update_view(camera_left_x, view_size), set_district(name).

const STREET_Y := 292.0

var _cam := 0.0
var _size := Vector2(640, 360)


func update_view(camera_left_x: float, view_size: Vector2) -> void:
	_cam = camera_left_x
	_size = view_size
	queue_redraw()


func set_district(_name: String) -> void:
	pass


func _draw() -> void:
	var l := _cam
	var w := _size.x
	var bands := 12
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(l, STREET_Y * t, w, STREET_Y / bands + 1), Color("0b0b18").lerp(Color("2a1240"), t))
	# Parallax blocks.
	for layer in 2:
		var f := 0.3 + 0.35 * layer
		var col := Color("16162c") if layer == 0 else Color("1d1d38")
		var step := 70.0 - layer * 16.0
		var start := floorf(l * f / step) - 1
		for k in int(w / step) + 3:
			var idx := int(start) + k
			var hgt := 80.0 + float((idx * 7919 + layer * 131) % 120) - layer * 30.0
			var x := idx * step - l * f + l
			draw_rect(Rect2(x, STREET_Y - hgt, step - 6, hgt), col)
			if (idx + layer) % 3 == 0:
				draw_rect(Rect2(x + 6, STREET_Y - hgt + 12, step - 18, 4), UITheme.MAGENTA if idx % 2 else UITheme.CYAN)
	draw_rect(Rect2(l, STREET_Y, w, _size.y - STREET_Y), Color("101020"))
	draw_line(Vector2(l, STREET_Y), Vector2(l + w, STREET_Y), UITheme.CYAN.darkened(0.5), 1.0)
