extends Control
## One deck thread in the combat HUD: chip tiles that light up as they execute, the
## dry-run readout, a cooldown sweep, and an EXEC button for MANUAL threads.
## Emits exec_pressed(thread) and tile_pressed(thread, slot).

signal exec_pressed(thread: int)
signal tile_pressed(thread: int, slot: int)

const EXEC_W := 82.0
const STATUS_W := 58.0
const LABEL_W := 16.0
const TILE_H := 40.0

var sim: CombatSim
var thread := 0
var selected := false
var readout := ""
var _t := 0.0
var _flash := 0.0
var _deny := 0.0
var _was_ready := false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 68)


func deny() -> void:
	_deny = 0.4


func flash() -> void:
	_flash = 1.0


func _deck() -> DeckEngine:
	return sim.deck if sim else null


func _th() -> Dictionary:
	return sim.deck.threads[thread]


func _right_w() -> float:
	return EXEC_W if _deck().is_manual(thread) else STATUS_W


func _tile_rect(slot: int) -> Rect2:
	var n: int = _th().chips.size()
	var avail := size.x - LABEL_W - _right_w() - 6.0
	var gap := 5.0
	var w := minf(50.0, (avail - gap * (n - 1)) / n)
	return Rect2(LABEL_W + slot * (w + gap), 2, w, TILE_H)


func exec_rect() -> Rect2:
	return Rect2(size.x - EXEC_W, 2, EXEC_W, size.y - 6)


## Screen position of a chip tile (for HUD -> target link lines).
func tile_center_global(slot: int) -> Vector2:
	return get_global_transform() * _tile_rect(slot).get_center()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position
	if _deck().is_manual(thread) and exec_rect().grow(4).has_point(p):
		exec_pressed.emit(thread)
		accept_event()
		return
	for s in _th().chips.size():
		if _tile_rect(s).grow(2).has_point(p):
			tile_pressed.emit(thread, s)
			accept_event()
			return


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.5)
	_deny = maxf(0.0, _deny - delta)
	if sim and _deck().is_manual(thread):
		var ready := _deck().block_reason(thread) == ""
		if ready and not _was_ready and sim.outcome == "":
			_flash = 1.0
		_was_ready = ready
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var deck := _deck()
	var th := _th()
	var dark := deck.is_dark(thread)
	var reason := deck.block_reason(thread)
	var manual := deck.is_manual(thread)
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.035, 0.035, 0.08, 0.9))
	var border := Color("2a2a48")
	if selected:
		border = UITheme.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 10.0))
	elif _flash > 0.0:
		border = border.lerp(UITheme.YELLOW, _flash)
	if _deny > 0.0:
		border = UITheme.RED
	draw_rect(r, border, false, 2.0 if selected else 1.0)
	# Thread label.
	draw_string(_font, Vector2(2, 14), "T%d" % (thread + 1), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 9, UITheme.TEXT_DIM if dark else UITheme.TEXT)
	if th.waiting and not dark:
		draw_string(_font, Vector2(2, 28), "..", HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 9, UITheme.GREEN)
	# Chip tiles with chevrons between them.
	var n: int = th.chips.size()
	for s in n:
		var tr := _tile_rect(s)
		var ref: String = th.chips[s]
		if s > 0:
			var cx := tr.position.x - 3.0
			draw_line(Vector2(cx - 1, tr.get_center().y - 3), Vector2(cx + 1, tr.get_center().y), Color("4a4a6a"), 1.0)
			draw_line(Vector2(cx + 1, tr.get_center().y), Vector2(cx - 1, tr.get_center().y + 3), Color("4a4a6a"), 1.0)
		ChipTile.draw_tile(self, _font, tr, ref, deck.lit(thread, s) if ref != "" else 0.0, dark)
	# Readout.
	var tiles_w := _tile_rect(n - 1).end.x - LABEL_W
	var col := UITheme.TEXT_DIM if not dark else Color(UITheme.TEXT_DIM, 0.5)
	var txt := readout
	if dark:
		txt = th.warn if th.warn != "" else "DARK: nothing to run"
	draw_string(_font, Vector2(LABEL_W, TILE_H + 12), _clip(txt, 8, tiles_w), HORIZONTAL_ALIGNMENT_LEFT, tiles_w, 8, col if not dark else UITheme.RED.darkened(0.2))
	# Cooldown sweep under the tiles.
	var bar := Rect2(LABEL_W, size.y - 7, tiles_w, 3)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var cycle := maxf(0.01, float(th.stats.cycle))
	var k := 1.0 - clampf(float(th.cd) / cycle, 0.0, 1.0)
	var bar_col := UITheme.CYAN if k >= 1.0 else UITheme.CYAN.darkened(0.45)
	if deck.frozen > 0.0:
		bar_col = Color("7ab8ff")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), bar_col if not dark else Color("2a2a44"))
	# Right side: EXEC button or status.
	if manual:
		_draw_exec(reason, th)
	else:
		_draw_status(reason, th, dark)


func _draw_exec(reason: String, th: Dictionary) -> void:
	var er := exec_rect()
	var ok := reason == ""
	var accent := UITheme.MAGENTA if ok else Color("3a3a58")
	if selected:
		accent = UITheme.CYAN
	var bg := accent.darkened(0.7) if ok or selected else Color(0.05, 0.05, 0.1)
	draw_rect(er, bg)
	if reason == "cd":
		var cycle := maxf(0.01, float(th.stats.cycle))
		var f := clampf(float(th.cd) / cycle, 0.0, 1.0)
		draw_rect(Rect2(er.position, Vector2(er.size.x, er.size.y * f)), Color(0, 0, 0, 0.5))
	var bw := 2.0 if ok else 1.0
	var bc := accent.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_t * 6.0))) if ok else accent
	if _flash > 0.0:
		bc = bc.lerp(Color.WHITE, _flash)
	draw_rect(er, bc, false, bw)
	var label := "CANCEL" if selected else "EXEC"
	draw_string(_font, er.position + Vector2(0, er.size.y / 2.0 + 1), label, HORIZONTAL_ALIGNMENT_CENTER, er.size.x, 15, UITheme.TEXT if ok or selected else UITheme.TEXT_DIM)
	var sub := "%d RAM" % int(th.stats.ram)
	match reason:
		"cd": sub = "%.1fs" % float(th.cd)
		"ram": sub = "NO RAM (%d)" % int(th.stats.ram)
		"frozen": sub = "FROZEN"
		"dark": sub = "DARK"
	draw_string(_font, er.position + Vector2(0, er.size.y / 2.0 + 15), sub, HORIZONTAL_ALIGNMENT_CENTER, er.size.x, 9,
		UITheme.CYAN if ok else (UITheme.RED if reason == "ram" else UITheme.TEXT_DIM))


func _draw_status(reason: String, th: Dictionary, dark: bool) -> void:
	var x := size.x - STATUS_W
	var cost_col := UITheme.CYAN if sim.deck.ram + 0.001 >= float(th.stats.ram) else UITheme.RED
	var chip := Rect2(x + 4, 6, 24, 14)
	draw_rect(chip, Color(0, 0, 0, 0.6))
	draw_rect(chip, cost_col.darkened(0.2), false, 1.0)
	draw_string(_font, chip.position + Vector2(0, 11), str(int(th.stats.ram)), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 10, cost_col)
	draw_string(_font, Vector2(x + 30, 17), "RAM", HORIZONTAL_ALIGNMENT_LEFT, 30, 7, UITheme.TEXT_DIM)
	var st := "AUTO"
	var sc := UITheme.GREEN.darkened(0.2)
	if dark:
		st = "DARK"
		sc = UITheme.RED.darkened(0.2)
	elif reason == "frozen":
		st = "FROZEN"
		sc = Color("7ab8ff")
	elif th.waiting:
		st = "WAITING"
		sc = UITheme.TEXT_DIM
	elif reason == "cd":
		st = "%.1fs" % float(th.cd)
		sc = UITheme.TEXT_DIM
	elif reason == "ram":
		st = "NO RAM"
		sc = UITheme.RED
	elif _flash > 0.2:
		st = "RUN"
		sc = UITheme.YELLOW
	draw_string(_font, Vector2(x, 40), st, HORIZONTAL_ALIGNMENT_CENTER, STATUS_W - 2, 10, sc)
	draw_string(_font, Vector2(x, 52), "x%d" % int(th.fired), HORIZONTAL_ALIGNMENT_CENTER, STATUS_W - 2, 8, UITheme.TEXT_DIM)


func _clip(s: String, fs: int, w: float) -> String:
	if _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return s
	while s.length() > 3 and _font.get_string_size(s + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		s = s.substr(0, s.length() - 1)
	return s + "..."
