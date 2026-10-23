extends Control
## Top-bar meters: TRACE (run-wide; the fixer's HP), RAM (one segment per point) and
## HEAT (overheat freezes the deck). `preview_cost` highlights what a pending EXEC spends.

var sim: CombatSim
var preview_cost := 0.0
var _t := 0.0
var _gain := 0.0
var _last_ram := 0.0
var _trace_hit := 0.0
var _last_trace := -1.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if sim:
		if sim.deck.ram > _last_ram + 0.5:
			_gain = 1.0
		_last_ram = sim.deck.ram
		if _last_trace >= 0.0 and sim.trace > _last_trace + 0.1:
			_trace_hit = 1.0
		_last_trace = sim.trace
	_gain = maxf(0.0, _gain - delta * 3.0)
	_trace_hit = maxf(0.0, _trace_hit - delta * 1.5)
	queue_redraw()


static func trace_color(v: float) -> Color:
	if v >= 75.0:
		return UITheme.RED
	if v >= 50.0:
		return Color("ff9f1c")
	return UITheme.PURPLE


func _draw() -> void:
	if sim == null:
		return
	var lw := 36.0
	var w := size.x
	# TRACE.
	var tv := clampf(sim.trace, 0.0, 100.0)
	var tc := trace_color(tv)
	draw_string(_font, Vector2(0, 11), "TRACE", HORIZONTAL_ALIGNMENT_LEFT, lw, 9, tc)
	var tb := Rect2(lw, 2, w - lw - 34, 10)
	draw_rect(tb, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(tb.position, Vector2(tb.size.x * tv / 100.0, tb.size.y)), tc if tv < 75.0 or fmod(_t, 0.6) < 0.4 else Color.WHITE)
	for q in [25, 50, 75]:
		draw_line(Vector2(tb.position.x + tb.size.x * q / 100.0, tb.position.y), Vector2(tb.position.x + tb.size.x * q / 100.0, tb.end.y), Color(0, 0, 0, 0.6))
	if _trace_hit > 0.0:
		draw_rect(tb.grow(1), Color(1, 1, 1, _trace_hit), false, 1.0)
	draw_string(_font, Vector2(tb.end.x + 3, 11), "%d%%" % int(tv), HORIZONTAL_ALIGNMENT_LEFT, 32, 10, tc)
	# RAM segments.
	var deck := sim.deck
	var y := 18.0
	draw_string(_font, Vector2(0, y + 10), "RAM", HORIZONTAL_ALIGNMENT_LEFT, lw, 9, UITheme.CYAN)
	var heat_w := 74.0
	var rb := Rect2(lw, y, w - lw - heat_w - 40, 11)
	draw_rect(rb, Color(0, 0, 0, 0.7))
	var n := int(round(deck.max_ram))
	var seg := rb.size.x / maxf(1, n)
	for i in n:
		var r := Rect2(rb.position + Vector2(i * seg + 1, 1), Vector2(seg - 2, rb.size.y - 2))
		var fill := clampf(deck.ram - i, 0.0, 1.0)
		draw_rect(r, Color("13233a"))
		if fill > 0.0:
			var c := UITheme.CYAN if fill >= 1.0 else UITheme.CYAN.darkened(0.45)
			if preview_cost > 0.0 and i >= int(floor(deck.ram - preview_cost)) and i < int(ceil(deck.ram)):
				c = UITheme.MAGENTA.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_t * 10.0)))
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), c)
	if _gain > 0.0:
		draw_rect(rb.grow(1), Color(1, 1, 1, _gain * 0.6), false, 1.0)
	draw_string(_font, Vector2(rb.end.x + 3, y + 10), "%d/%d" % [int(deck.ram), n], HORIZONTAL_ALIGNMENT_LEFT, 36, 9, UITheme.TEXT)
	# HEAT.
	var hx := w - heat_w
	var hb := Rect2(hx + 28, y, heat_w - 28, 11)
	var frozen := deck.frozen > 0.0
	var hc := Color("ff9f1c") if deck.heat < deck.heat_cap * 0.75 else UITheme.RED
	if frozen:
		hc = Color("7ab8ff")
	draw_string(_font, Vector2(hx, y + 10), "HEAT", HORIZONTAL_ALIGNMENT_LEFT, 28, 9, hc)
	draw_rect(hb, Color(0, 0, 0, 0.7))
	if frozen:
		var k := deck.frozen / float(ChipDB.CHASSIS.freeze)
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * k, hb.size.y)), Color(hc, 0.6 if fmod(_t, 0.4) < 0.2 else 0.9))
		draw_string(_font, Vector2(hb.position.x, y + 9), "FROZEN", HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, 8, Color.WHITE)
	else:
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * clampf(deck.heat / deck.heat_cap, 0.0, 1.0), hb.size.y)), hc)
		var cells := int(deck.heat_cap)
		for i in range(1, cells):
			var xx := hb.position.x + hb.size.x * i / cells
			draw_line(Vector2(xx, hb.position.y), Vector2(xx, hb.end.y), Color(0, 0, 0, 0.5))
