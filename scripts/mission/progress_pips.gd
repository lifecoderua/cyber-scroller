extends Control
## District progress: one pip per encounter, a skull for the boss.

const SKULL := [".xxxx.", "xxxxxx", "x.xx.x", "xxxxxx", ".xxxx."]

var sim: CombatSim
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var n := sim.total_encounters()
	if n == 0:
		return
	var gap := minf(22.0, (size.x - 16) / maxf(1, n - 1))
	var w := gap * (n - 1)
	var x0 := (size.x - w) / 2.0
	var cy := size.y / 2.0
	draw_line(Vector2(x0, cy), Vector2(x0 + w, cy), Color("2a2a44"), 2.0)
	var done_w := gap * clampf(float(sim.encounters_cleared), 0.0, n - 1)
	draw_line(Vector2(x0, cy), Vector2(x0 + done_w, cy), UITheme.CYAN.darkened(0.3), 2.0)
	for i in n:
		var p := Vector2(x0 + i * gap, cy)
		var cleared := i < sim.encounters_cleared
		var active := i == sim.active_encounter
		if i == n - 1:
			_skull(p, UITheme.CYAN if cleared else UITheme.RED, active)
			continue
		var col := UITheme.CYAN if cleared else (UITheme.MAGENTA if active else Color("4a4a6a"))
		var r := 4.0 + (1.0 + sin(_t * 8.0)) if active else 4.0
		draw_circle(p, r + 1.0, Color(0, 0, 0, 0.8))
		if cleared or active:
			draw_circle(p, r, col)
		else:
			draw_arc(p, r, 0, TAU, 12, col, 1.5)


func _skull(p: Vector2, col: Color, active: bool) -> void:
	var px := 1.7 * (1.0 + (0.15 * (1.0 + sin(_t * 8.0)) if active else 0.0))
	var o := p - Vector2(3 * px, 2.5 * px)
	draw_rect(Rect2(o - Vector2(1, 1), Vector2(6 * px + 2, 5 * px + 2)), Color(0, 0, 0, 0.6))
	for y in SKULL.size():
		for x in 6:
			if SKULL[y][x] == "x":
				draw_rect(Rect2(o + Vector2(x * px, y * px), Vector2(px, px)), col)
