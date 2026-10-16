extends Control
## Segmented RAM bar (1 segment per RAM). `preview_cost` highlights what a pending cast
## would spend.

var sim: CombatSim
var preview_cost := 0.0
var _t := 0.0
var _gain := 0.0
var _last := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if sim:
		if sim.ram > _last + 0.5:
			_gain = 1.0
		_last = sim.ram
	_gain = maxf(0.0, _gain - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var label_w := 26.0
	draw_string(_font, Vector2(0, size.y - 3), "RAM", HORIZONTAL_ALIGNMENT_LEFT, label_w, 9, UITheme.CYAN)
	var bar := Rect2(label_w, 1, size.x - label_w - 34, size.y - 2)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var n := int(round(sim.max_ram))
	var seg_w := bar.size.x / maxf(1, n)
	for i in n:
		var r := Rect2(bar.position + Vector2(i * seg_w + 1, 1), Vector2(seg_w - 2, bar.size.y - 2))
		var fill := clampf(sim.ram - i, 0.0, 1.0)
		draw_rect(r, Color("13233a"))
		if fill > 0.0:
			var c := UITheme.CYAN if fill >= 1.0 else UITheme.CYAN.darkened(0.45)
			if preview_cost > 0.0 and i >= int(floor(sim.ram - preview_cost)) and i < int(ceil(sim.ram)):
				c = UITheme.MAGENTA.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_t * 10.0)))
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), c)
	if sim.ram >= sim.max_ram - 0.01:
		draw_rect(bar, Color(UITheme.CYAN, 0.4 + 0.3 * sin(_t * 5.0)), false, 1.0)
	if _gain > 0.0:
		draw_rect(bar.grow(1), Color(1, 1, 1, _gain * 0.6), false, 1.0)
	draw_string(_font, Vector2(bar.end.x + 3, size.y - 3), "%d/%d" % [int(sim.ram), n], HORIZONTAL_ALIGNMENT_LEFT, 34, 9, UITheme.TEXT)
