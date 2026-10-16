class_name TreeGraph
extends Control
## Nodebuster-style node graph for the fixer skill tree. Pure drawing + input:
## reads Game state every frame, emits node_tapped(id) / empty_tapped().
## Drag (mouse or touch) pans with a little inertia; taps select.

signal node_tapped(id: String)
signal empty_tapped

const R := 12.0          # regular node radius
const R_CORE := 17.0
const R_CAP := 15.0
const HIT_PAD := 9.0     # generous touch target
const DRAG_START := 6.0  # px before a press becomes a drag
const GRID := 16.0
const LOCKED_COL := Color(0.55, 0.55, 0.7)

var pan := Vector2.ZERO
var selected := ""

var _t := 0.0
var _pressing := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_pan := Vector2.ZERO
var _vel := Vector2.ZERO
var _last_motion_ms := 0
var _bursts: Array = []   # {id, t}
var _pulses: Array = []   # {from, to, t}: light travelling along a fresh edge
var _bounds := Rect2()
var _font: Font
var game: Node  # the Game autoload, looked up at runtime so --script tools can load this class


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	game = get_node("/root/Game")
	var first := true
	for id in TreeDB.all_ids():
		var p := TreeDB.pos(id)
		if first:
			_bounds = Rect2(p, Vector2.ZERO)
			first = false
		else:
			_bounds = _bounds.expand(p)
	_bounds = _bounds.grow(R_CAP + 14.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if not _pressing and _vel.length_squared() > 1.0:
		pan = _clamp_pan(pan + _vel * delta)
		_vel = _vel.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	for b in _bursts:
		b.t += delta
	_bursts = _bursts.filter(func(b): return b.t < 0.8)
	for p in _pulses:
		p.t += delta
	_pulses = _pulses.filter(func(p): return p.t < 0.9)
	queue_redraw()


func origin() -> Vector2:
	return size * 0.5 + pan


func node_screen_pos(id: String) -> Vector2:
	return origin() + TreeDB.pos(id)


func recenter() -> void:
	var t := create_tween()
	t.tween_property(self, "pan", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_vel = Vector2.ZERO


## Smoothly brings a node into view (used after selecting near an edge).
func focus(id: String) -> void:
	var p := TreeDB.pos(id)
	var want := pan
	var margin := 40.0
	var sp := size * 0.5 + pan + p
	if sp.x < margin or sp.x > size.x - margin or sp.y < margin or sp.y > size.y - margin:
		want = _clamp_pan(-p * 0.6)
		var t := create_tween()
		t.tween_property(self, "pan", want, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Purchase feedback: ring burst on the node and light running to newly opened children.
func burst(id: String) -> void:
	_bursts.append({"id": id, "t": 0.0})
	for n in TreeDB.NODES:
		if id in n.req and game.tree_rank(n.id) == 0 and game.node_unlocked(n.id):
			_pulses.append({"from": id, "to": n.id, "t": 0.0})


func _clamp_pan(p: Vector2) -> Vector2:
	# Keep the content in view: allow panning until the bounds edge reaches the panel edge.
	var half := size * 0.5
	var lim_x := maxf(0.0, maxf(-_bounds.position.x, _bounds.end.x) - half.x + 10.0)
	var lim_y := maxf(0.0, maxf(-_bounds.position.y, _bounds.end.y) - half.y + 10.0)
	return Vector2(clampf(p.x, -lim_x, lim_x), clampf(p.y, -lim_y, lim_y))


# --- input -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_pos = event.position
			_press_pan = pan
			_vel = Vector2.ZERO
		elif _pressing:
			_pressing = false
			if not _dragging:
				_tap(event.position)
			elif Time.get_ticks_msec() - _last_motion_ms > 80:
				_vel = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var d: Vector2 = event.position - _press_pos
		if not _dragging and d.length() > DRAG_START:
			_dragging = true
		if _dragging:
			var before := pan
			pan = _clamp_pan(_press_pan + d)
			var dt := maxf(0.001, (Time.get_ticks_msec() - _last_motion_ms) / 1000.0)
			if dt < 0.1:
				_vel = _vel.lerp((pan - before) / dt, 0.5)
			_last_motion_ms = Time.get_ticks_msec()
		accept_event()


func _tap(p: Vector2) -> void:
	var best := ""
	var best_d := INF
	for id in TreeDB.all_ids():
		var d := p.distance_to(node_screen_pos(id))
		if d <= _radius(id) + HIT_PAD and d < best_d:
			best_d = d
			best = id
	if best != "":
		node_tapped.emit(best)
	else:
		empty_tapped.emit()


func _radius(id: String) -> float:
	if id == "core":
		return R_CORE
	return R_CAP if id.ends_with("_cap") else R


# --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	var o := origin()
	_draw_grid(o)
	_draw_branch_labels(o)
	for n in TreeDB.NODES:
		for req in n.req:
			_draw_edge(req, n.id, o)
	for p in _pulses:
		var a := o + TreeDB.pos(p.from)
		var b := o + TreeDB.pos(p.to)
		var k: float = clampf(p.t / 0.5, 0.0, 1.0)
		var col := TreeDB.branch_color(p.to)
		draw_line(a, a.lerp(b, k), Color(col.lightened(0.4), 1.0 - p.t), 3.0)
		draw_circle(a.lerp(b, k), 3.0, Color(1, 1, 1, 1.0 - p.t))
	for n in TreeDB.NODES:
		_draw_node(n.id, o)
	for b in _bursts:
		_draw_burst(b, o)
	if game.tree_rank("core") == 0:
		var cp := o + TreeDB.pos("core")
		var a := 0.55 + 0.45 * sin(_t * 4.0)
		_text("TAP TO JACK IN", cp + Vector2(0, R_CORE + 20), 9, Color(UITheme.TEXT, a), true)


func _draw_grid(o: Vector2) -> void:
	var off := Vector2(fposmod(o.x, GRID), fposmod(o.y, GRID))
	var col := Color(0.6, 0.6, 1.0, 0.07)
	var y := off.y
	while y < size.y:
		var x := off.x
		while x < size.x:
			draw_rect(Rect2(x, y, 1, 1), col)
			x += GRID
		y += GRID
	# Faint quadrant axes through the core.
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), Color(0.6, 0.6, 1.0, 0.05), 1.0)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), Color(0.6, 0.6, 1.0, 0.05), 1.0)


func _draw_branch_labels(o: Vector2) -> void:
	for key in TreeDB.BRANCHES:
		if key == "core":
			continue
		var b: Dictionary = TreeDB.BRANCHES[key]
		var s: Vector2 = b.sign
		var p := o + Vector2(3.55 * s.x, 1.35 * s.y) * TreeDB.UNIT
		_text(String(b.name), p, 8, Color(b.color, 0.32), true)


func _draw_edge(from: String, to: String, o: Vector2) -> void:
	var a := o + TreeDB.pos(from)
	var b := o + TreeDB.pos(to)
	var dir := (b - a).normalized()
	a += dir * _radius(from)
	b -= dir * _radius(to)
	var col := TreeDB.branch_color(to)
	var from_on: bool = game.tree_rank(from) > 0
	var to_on: bool = game.tree_rank(to) > 0
	if from_on and to_on:
		draw_line(a, b, Color(col, 0.25), 5.0)
		draw_line(a, b, col.lightened(0.1), 2.0)
		# Data packets flowing outward.
		var length := a.distance_to(b)
		var k := fposmod(_t * 40.0, 24.0)
		while k < length:
			draw_rect(Rect2(a + dir * k - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 1, 1, 0.8))
			k += 24.0
	elif from_on:
		var pulse := 0.35 + 0.2 * sin(_t * 3.0)
		draw_dashed_line(a, b, Color(col, pulse), 1.5, 4.0)
	else:
		draw_line(a, b, Color(LOCKED_COL, 0.12), 1.0)


func _shape(c: Vector2, r: float, sides: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var ang := rot + TAU * i / sides
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts


func _draw_node(id: String, o: Vector2) -> void:
	var d := TreeDB.def(id)
	var c := o + TreeDB.pos(id)
	var r := _radius(id)
	var col := TreeDB.branch_color(id)
	var state: String = game.node_state(id)
	var buyable: bool = game.can_buy_node(id)
	var sides := 6 if id == "core" else (4 if id.ends_with("_cap") else 8)
	var rot := -PI / 2.0 if sides == 6 else (0.0 if sides == 4 else PI / 8.0)
	var rr := r * (1.25 if sides == 4 else 1.0)
	var fill := Color(0.05, 0.05, 0.1, 0.96)
	var border := Color(LOCKED_COL, 0.3)
	var icon_col := Color(LOCKED_COL, 0.35)
	match state:
		"open":
			border = Color(col, 0.75 if buyable else 0.45)
			icon_col = col if buyable else Color(col, 0.55)
		"owned":
			fill = col.darkened(0.68)
			border = col
			icon_col = col.lightened(0.45)
		"maxed":
			fill = col.darkened(0.15)
			border = col.lightened(0.5)
			icon_col = UITheme.BG
	# Glow / pulse.
	if state == "maxed":
		draw_circle(c, rr + 7.0, Color(col, 0.08))
		draw_circle(c, rr + 3.5, Color(col, 0.16))
	elif buyable:
		var p := 0.5 + 0.5 * sin(_t * 5.0 + c.x * 0.05)
		draw_circle(c, rr + 4.0 + 3.0 * p, Color(col, 0.10 + 0.14 * p))
		draw_arc(c, rr + 4.0 + 3.0 * p, 0, TAU, 32, Color(col, 0.35 + 0.4 * p), 1.0)
	var pts := _shape(c, rr, sides, rot)
	draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border, 2.0 if state != "locked" else 1.0)
	if state == "owned":
		# Fill level hints at progress through the ranks.
		var k := float(game.tree_rank(id)) / TreeDB.max_rank(id)
		draw_colored_polygon(_shape(c, rr * 0.55 * k + 2.0, sides, rot), Color(col, 0.35))
	_text(String(d.icon), c + Vector2(0, 0.5), 8 if String(d.icon).length() >= 3 else 9, icon_col, true, true)
	# Rank pips.
	var mr := TreeDB.max_rank(id)
	if mr > 1:
		var rank: int = game.tree_rank(id)
		var w := mr * 5.0 - 1.0
		var x0 := c.x - w * 0.5
		var y := c.y + rr + 3.0
		for i in mr:
			var on: bool = i < rank
			draw_rect(Rect2(x0 + i * 5.0, y, 4, 3), col if on else Color(col if state != "locked" else LOCKED_COL, 0.18))
	# Price tag on reachable nodes.
	if state == "open" or state == "owned":
		var cost: int = game.node_cost(id)
		var tag := c + Vector2(rr * 0.7 + 3.0, -rr * 0.7 - 3.0)
		var tc := HubShard.COLOR if game.shards >= cost else Color(UITheme.RED, 0.75)
		HubShard.draw(self, tag, 3.5, tc)
		_text(str(cost), tag + Vector2(4.5, 0), 8, tc.lightened(0.2), false)
	# Selection brackets.
	if id == selected:
		var s := rr + 6.0 + sin(_t * 6.0)
		var arm := 5.0
		var sc := Color(1, 1, 1, 0.9)
		for k in 4:
			var sx := -1.0 if k % 2 == 0 else 1.0
			var sy := -1.0 if k < 2 else 1.0
			var corner := c + Vector2(sx * s, sy * s)
			draw_line(corner, corner - Vector2(sx * arm, 0), sc, 1.5)
			draw_line(corner, corner - Vector2(0, sy * arm), sc, 1.5)


func _draw_burst(b: Dictionary, o: Vector2) -> void:
	var c := o + TreeDB.pos(b.id)
	var col := TreeDB.branch_color(b.id)
	var t: float = b.t
	var k := clampf(t / 0.6, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	draw_arc(c, _radius(b.id) + 34.0 * e, 0, TAU, 40, Color(col.lightened(0.3), 1.0 - k), 2.5)
	draw_arc(c, _radius(b.id) + 18.0 * e, 0, TAU, 40, Color(1, 1, 1, (1.0 - k) * 0.7), 1.5)
	if t < 0.12:
		draw_circle(c, _radius(b.id) + 4.0, Color(1, 1, 1, 0.6 * (1.0 - t / 0.12)))
	for i in 12:
		var ang := TAU * i / 12.0 + 0.3
		var dist := _radius(b.id) + 6.0 + 40.0 * e
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(col.lightened(0.5), 1.0 - k))


func _text(s: String, p: Vector2, fs: int, col: Color, centred: bool, outline := false) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := _font.get_ascent(fs)
	var desc := _font.get_descent(fs)
	var pos := Vector2(p.x - (w * 0.5 if centred else 0.0), p.y + (asc - desc) * 0.5)
	if outline:
		draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0, 0, 0, 0.6 * col.a))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
