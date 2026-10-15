extends Control
## Cheap animated hub backdrop: gradient sky, static skyline silhouette,
## a scrolling synthwave grid floor and scanlines. Redraws the animated parts at ~30 fps.

const HORIZON := 0.6
const SKY_TOP := Color("05050c")
const SKY_HORIZON := Color("1d0d33")
const FLOOR_BOTTOM := Color("07070f")
const GRID := Color(1.0, 0.24, 0.5, 0.22)

var _t := 0.0
var _acc := 0.0
var _sky: Control
var _scan: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky = Skyline.new()
	add_child(_sky)
	_scan = Scanlines.new()
	add_child(_scan)
	resized.connect(func(): _sky.queue_redraw())


func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc >= 1.0 / 30.0:
		_acc = 0.0
		queue_redraw()
		_scan.t = _t
		_scan.queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var hy := floorf(h * HORIZON)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, hy), Vector2(0, hy)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_HORIZON, SKY_HORIZON]))
	draw_polygon(PackedVector2Array([Vector2(0, hy), Vector2(w, hy), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color("140a24"), Color("140a24"), FLOOR_BOTTOM, FLOOR_BOTTOM]))
	# Sun-ish glow behind the skyline.
	var cx := w * 0.5
	for i in 5:
		var r := 70.0 - i * 12.0
		draw_circle(Vector2(cx, hy), r, Color(1.0, 0.24, 0.5, 0.035 + i * 0.012))
	# Grid floor: horizontal lines approach the viewer.
	var depth := h - hy
	var n := 12
	var phase := fmod(_t * 0.35, 1.0)
	for i in n:
		var z := (i + phase) / n
		var y := hy + depth * z * z
		draw_line(Vector2(0, y), Vector2(w, y), Color(GRID, GRID.a * z), 1.0)
	# Vertical lines fan out from the vanishing point.
	var spread := 26
	for i in range(-spread, spread + 1):
		var bx := cx + i * 46.0
		draw_line(Vector2(cx + i * 4.0, hy), Vector2(bx, h), Color(GRID, 0.14), 1.0)
	draw_line(Vector2(0, hy), Vector2(w, hy), Color(1.0, 0.35, 0.6, 0.6), 1.0)


class Skyline extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := size.x
		var hy := floorf(size.y * 0.6)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2077
		_layer(rng, w, hy, 20.0, 70.0, Color("120c26"), 0.10)
		_layer(rng, w, hy, 30.0, 120.0, Color("0a0816"), 0.22)

	func _layer(rng: RandomNumberGenerator, w: float, hy: float, min_h: float, max_h: float, col: Color, lit: float) -> void:
		var x := -rng.randf_range(0, 20)
		while x < w:
			var bw := rng.randf_range(16, 46)
			var bh := rng.randf_range(min_h, max_h)
			var top := hy - bh
			draw_rect(Rect2(x, top, bw, bh), col)
			if rng.randf() < 0.3:
				draw_rect(Rect2(x + bw * 0.5 - 1, top - 10, 1, 10), col)  # antenna
				draw_rect(Rect2(x + bw * 0.5 - 1, top - 11, 1, 1), Color(1, 0.2, 0.2, 0.8))
			# Windows.
			var wy := top + 4
			while wy < hy - 3:
				var wx := x + 3
				while wx < x + bw - 3:
					if rng.randf() < lit:
						var wc := UITheme.YELLOW if rng.randf() < 0.6 else UITheme.CYAN
						draw_rect(Rect2(wx, wy, 2, 1), Color(wc, rng.randf_range(0.25, 0.6)))
					wx += 4
				wy += 4
			# Occasional vertical neon sign.
			if rng.randf() < 0.18 and bh > 50:
				var nc := UITheme.MAGENTA if rng.randf() < 0.5 else UITheme.CYAN
				var sh := rng.randf_range(14, 30)
				draw_rect(Rect2(x + 2, top + 8, 3, sh), Color(nc, 0.75))
				draw_rect(Rect2(x + 1, top + 7, 5, sh + 2), Color(nc, 0.15))
			x += bw + rng.randf_range(-4, 6)


class Scanlines extends Control:
	var t := 0.0
	var _tex: ImageTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var img := Image.create_empty(1, 3, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.set_pixel(0, 2, Color(0, 0, 0, 0.28))
		_tex = ImageTexture.create_from_image(img)

	func _draw() -> void:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), true)
		# Slow scan beam.
		var y := fmod(t * 40.0, size.y + 80.0) - 40.0
		draw_rect(Rect2(0, y, size.x, 24), Color(0.18, 0.89, 0.9, 0.025))
		draw_rect(Rect2(0, y + 10, size.x, 2), Color(0.18, 0.89, 0.9, 0.04))
