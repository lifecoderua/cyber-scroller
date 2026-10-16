extends Node2D
## World-space juice: tracers, slashes, hack beams, AoE rings, sparks, floating text.
## Everything is immediate-mode in _draw() on plain arrays (cheap on web/mobile).

const MAX_TEXTS := 48
const MAX_SPARKS := 220

var tracers: Array = []  # {a, b, t, life, col, w}
var slashes: Array = []  # {p, t, life, col, dir}
var beams: Array = []    # {from, to, t, life, col, w}
var rings: Array = []    # {p, r, t, life, col}
var arcs: Array = []     # {a, b, t, life, col}
var sparks: Array = []   # {p, v, t, life, col, s}
var texts: Array = []    # {p, v, s, t, life, col, size}
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 5


func tracer(a: Vector2, b: Vector2, col: Color, w := 1.5, life := 0.09) -> void:
	tracers.append({"a": a, "b": b, "t": 0.0, "life": life, "col": col, "w": w})


func slash(p: Vector2, col: Color, dir := 1.0) -> void:
	slashes.append({"p": p, "t": 0.0, "life": 0.16, "col": col, "dir": dir})


func beam(from: Vector2, to: Vector2, col: Color, w := 3.0, life := 0.4) -> void:
	beams.append({"from": from, "to": to, "t": 0.0, "life": life, "col": col, "w": w})


func ring(p: Vector2, r: float, col: Color, life := 0.45) -> void:
	rings.append({"p": p, "r": r, "t": 0.0, "life": life, "col": col})


func arc(a: Vector2, b: Vector2, col: Color, life := 0.35) -> void:
	arcs.append({"a": a, "b": b, "t": 0.0, "life": life, "col": col})


func burst(p: Vector2, col: Color, n := 8, speed := 90.0, life := 0.45, size := 2.0) -> void:
	for i in n:
		if sparks.size() >= MAX_SPARKS:
			sparks.pop_front()
		var ang := randf() * TAU
		var v := Vector2(cos(ang), sin(ang) - 0.6) * speed * randf_range(0.4, 1.0)
		sparks.append({"p": p, "v": v, "t": 0.0, "life": life * randf_range(0.6, 1.2), "col": col, "s": size})


func text(p: Vector2, s: String, col: Color, size := 10, life := 0.9, rise := 34.0) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()
	# Nudge stacked popups apart.
	var off := 0.0
	for o in texts:
		if o.t < 0.25 and o.p.distance_to(p + Vector2(0, off)) < 9.0:
			off -= 9.0
	texts.append({"p": p + Vector2(randf_range(-4, 4), off), "v": Vector2(randf_range(-8, 8), -rise),
		"s": s, "t": 0.0, "life": life, "col": col, "size": size})


func tick(dt: float) -> void:
	for arr in [tracers, slashes, beams, rings, arcs, sparks, texts]:
		for o in arr:
			o.t += dt
	for s in sparks:
		s.p += s.v * dt
		s.v.y += 260.0 * dt
		s.v *= 0.97
	for o in texts:
		o.p += o.v * dt
		o.v *= pow(0.04, dt)
	tracers = tracers.filter(_alive)
	slashes = slashes.filter(_alive)
	beams = beams.filter(_alive)
	rings = rings.filter(_alive)
	arcs = arcs.filter(_alive)
	sparks = sparks.filter(_alive)
	texts = texts.filter(_alive)
	queue_redraw()


func _alive(o) -> bool:
	return o.t < o.life


func _draw() -> void:
	for o in tracers:
		var k: float = 1.0 - o.t / o.life
		var c: Color = o.col
		c.a = k
		draw_line(o.a, o.b, c, o.w)
		draw_line(o.a.lerp(o.b, 0.55), o.b, Color(1, 1, 1, k), maxf(1.0, o.w - 0.5))
	for o in slashes:
		var k: float = o.t / o.life
		var c: Color = o.col
		c.a = 1.0 - k
		var r := 7.0 + k * 9.0
		var start: float = -1.1 if o.dir > 0 else PI - 1.1
		draw_arc(o.p, r, start, start + 2.2, 8, c, 2.0)
		draw_arc(o.p, r - 3.0, start + 0.3, start + 1.9, 6, Color(1, 1, 1, 1.0 - k), 1.0)
	for o in beams:
		var k: float = 1.0 - o.t / o.life
		var c: Color = o.col
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var f := float(i) / n
			var p: Vector2 = o.from.lerp(o.to, f)
			if i > 0 and i < n:
				p.x += randf_range(-6, 6) * k
			pts.append(p)
		c.a = 0.35 * k
		draw_polyline(pts, c, o.w * 3.0)
		c.a = k
		draw_polyline(pts, c, o.w)
		draw_polyline(pts, Color(1, 1, 1, k), maxf(1.0, o.w * 0.35))
		# Glitch blocks along the beam.
		for i in 3:
			var p: Vector2 = o.from.lerp(o.to, randf())
			draw_rect(Rect2(p + Vector2(randf_range(-10, 6), 0), Vector2(randf_range(3, 9), 2)), Color(c.r, c.g, c.b, k * 0.8))
		draw_circle(o.to, 6.0 * k + 2.0, Color(c.r, c.g, c.b, 0.5 * k))
	for o in rings:
		var k: float = o.t / o.life
		var c: Color = o.col
		c.a = 1.0 - k
		var rr: float = o.r * (0.3 + 0.7 * sqrt(k))
		draw_set_transform(o.p, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, rr, 0, TAU, 32, c, 3.0)
		c.a *= 0.25
		draw_circle(Vector2.ZERO, rr, c)
		draw_set_transform(Vector2.ZERO)
	for o in arcs:
		var k: float = minf(1.0, o.t / (o.life * 0.6))
		var pts := PackedVector2Array()
		for i in 9:
			var f := float(i) / 8.0 * k
			var p: Vector2 = o.a.lerp(o.b, f)
			p.y -= sin(f * PI) * 40.0
			pts.append(p)
		if pts.size() > 1:
			draw_polyline(pts, Color(o.col.r, o.col.g, o.col.b, 1.0 - o.t / o.life), 1.5)
		draw_rect(Rect2(pts[pts.size() - 1] - Vector2(2, 2), Vector2(4, 4)), o.col)
	for s in sparks:
		var c: Color = s.col
		c.a = 1.0 - s.t / s.life
		draw_rect(Rect2(s.p, Vector2(s.s, s.s)), c)
	for o in texts:
		var k: float = o.t / o.life
		var c: Color = o.col
		c.a = 1.0 if k < 0.65 else 1.0 - (k - 0.65) / 0.35
		var pop := 1.0 + maxf(0.0, 0.35 - o.t) * 1.5
		var size := int(round(o.size * pop))
		var w := 160.0
		var pos: Vector2 = o.p - Vector2(w / 2.0, 0)
		draw_string_outline(_font, pos, o.s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 4, Color(0, 0, 0, c.a * 0.9))
		draw_string(_font, pos, o.s, HORIZONTAL_ALIGNMENT_CENTER, w, size, c)
