extends Control
## District node map, bottom (start) to top (target). Pure drawing + input: reads the
## RunState every frame, emits node_tapped(id) for reachable nodes and peek(id) for others.

signal node_tapped(id: int)
signal peek(id: int)

const R := 16.0
const PAD_X := 34.0
const PAD_Y := 26.0
const HIT := 24.0

var run: RunState
var reveal := false        # Oracle Feed: show event / theme details
var selected := -1
var _t := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func node_pos(n: Dictionary) -> Vector2:
	var rows := RunState.ROWS + 1
	var h := size.y - PAD_Y * 2.0
	var y := size.y - PAD_Y - h * float(n.row) / float(rows - 1)
	var x := PAD_X + (size.x - PAD_X * 2.0) * float(n.x)
	return Vector2(x, y)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var best := -1
	var best_d := HIT
	for n in run.map:
		var d: float = node_pos(n).distance_to(event.position)
		if d < best_d:
			best_d = d
			best = n.id
	if best < 0:
		return
	accept_event()
	if best in run.reachable() and run.phase == "map":
		node_tapped.emit(best)
	else:
		peek.emit(best)


func _draw() -> void:
	if run == null:
		return
	var reach := run.reachable()
	# Row guides.
	for row in RunState.ROWS + 1:
		var y := node_pos({"row": row, "x": 0}).y
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color(1, 1, 1, 0.03), 1.0)
	# Links.
	var path := _path()
	for n in run.map:
		var a := node_pos(n)
		for l in n.links:
			var m: Dictionary = run.node(l)
			var b := node_pos(m)
			var travelled: bool = n.id in path and int(l) in path
			var live: bool = n.id == run.pos and int(l) in reach
			var col := Color("2a2a48")
			var w := 2.0
			if travelled:
				col = UITheme.CYAN.darkened(0.2)
				w = 3.0
			elif live:
				col = UITheme.CYAN.lerp(Color.WHITE, 0.3 + 0.3 * sin(_t * 4.0))
				w = 2.0
			_dashed(a, b, col, w, not (travelled or live))
	if run.pos < 0:
		var start := node_pos({"row": -0.6, "x": 0.5})
		for id in reach:
			_dashed(start, node_pos(run.node(id)), UITheme.CYAN.lerp(Color.WHITE, 0.3 + 0.3 * sin(_t * 4.0)), 2.0, false)
		_label(start + Vector2(0, 4), "JACK-IN POINT", 8, UITheme.TEXT_DIM)
	# Nodes.
	for n in run.map:
		_draw_node(n, n.id in reach, n.id in path)


func _path() -> Array:
	var out := []
	for n in run.map:
		if n.done:
			out.append(n.id)
	if run.pos >= 0:
		out.append(run.pos)
	return out


func _draw_node(n: Dictionary, reachable: bool, visited: bool) -> void:
	var info: Dictionary = RunState.NODE_INFO[n.type]
	var p := node_pos(n)
	var col: Color = info.color
	var r := R * (1.25 if n.type == "boss" else 1.0)
	var here: bool = n.id == run.pos
	var live := reachable and run.phase == "map"
	var dim: bool = not live and not visited and not here
	if live:
		var pulse := 0.5 + 0.5 * sin(_t * 5.0 + n.id)
		draw_circle(p, r + 5.0 + pulse * 3.0, Color(col, 0.12 + 0.1 * pulse))
	draw_circle(p, r + 1.5, Color(0, 0, 0, 0.85))
	var fill := col.darkened(0.72)
	if visited and not here:
		fill = Color("15152a")
	draw_circle(p, r, fill if not dim else Color("101020"))
	var ring := col if not dim else col.darkened(0.55)
	if n.id == selected:
		ring = Color.WHITE
	draw_arc(p, r, 0, TAU, 28, ring, 2.0 if live or here else 1.0)
	var icon: String = info.icon
	var ic := col.lightened(0.3) if not dim else col.darkened(0.4)
	if visited and not here:
		icon = "v"
		ic = UITheme.TEXT_DIM
	_label(p + Vector2(0, 4), icon, 12 if n.type != "boss" else 14, ic)
	if here:
		draw_arc(p, r + 5.0, _t * 3.0, _t * 3.0 + PI * 1.3, 18, UITheme.CYAN, 2.0)
	if live or n.type == "boss":
		var caption: String = info.name
		if n.type in ["fight", "elite", "cache"] and (reveal or live):
			caption += " · " + String(RunState.THEME_NAMES.get(n.theme, "")).to_upper()
		_label(p + Vector2(0, r + 12), caption, 8, col if live else col.darkened(0.3))


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dashed: bool) -> void:
	if not dashed:
		draw_line(a, b, col, w)
		return
	var dist := a.distance_to(b)
	var dir := (b - a) / maxf(1.0, dist)
	var d := R
	while d < dist - R:
		draw_line(a + dir * d, a + dir * minf(dist - R, d + 5.0), col, w)
		d += 9.0


func _label(p: Vector2, s: String, fs: int, col: Color) -> void:
	var w := 140.0
	draw_string_outline(_font, p - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(_font, p - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
