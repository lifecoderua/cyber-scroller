extends Control
## A soft (program) card in the bottom row: name, RAM cost, cooldown sweep, charges,
## disabled state, selected (targeting) state. Emits `tapped(slot)`.

signal tapped(slot: int)

var sim: CombatSim
var slot := 0
var selected := false
var _t := 0.0
var _ready_flash := 0.0
var _deny := 0.0
var _was_blocked := false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(84, 50)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func deny() -> void:
	_deny = 0.35


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(slot)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	_ready_flash = maxf(0.0, _ready_flash - delta * 2.5)
	_deny = maxf(0.0, _deny - delta)
	if sim:
		var blocked := sim.block_reason(slot) in ["cd", "ram", "charges"]
		if _was_blocked and not blocked and sim.outcome == "":
			_ready_flash = 1.0
		_was_blocked = blocked
	queue_redraw()


func _draw() -> void:
	if sim == null or slot >= sim.slots.size():
		return
	var s: Dictionary = sim.slots[slot]
	var d: Dictionary = s.def
	var col: Color = d.color
	var reason := sim.block_reason(slot)
	var lift := -4.0 if selected else 0.0
	var shake := sin(_t * 70.0) * 3.0 * (_deny / 0.35)
	var r := Rect2(Vector2(shake, lift), size)
	var usable := reason == "" or reason == "target"
	var bg := UITheme.PANEL_HI if usable else UITheme.PANEL.darkened(0.25)
	draw_rect(r, Color(0, 0, 0, 0.5) if not selected else Color(col.r, col.g, col.b, 0.25))
	draw_rect(r.grow(-1), bg)
	# Colour stripe + icon glyph.
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(4, r.size.y - 2)), col if usable else col.darkened(0.55))
	# Border.
	var border := col.darkened(0.35) if usable else Color("2a2a44")
	if selected:
		var p := 0.5 + 0.5 * sin(_t * 10.0)
		border = col.lerp(Color.WHITE, p * 0.6)
	if _ready_flash > 0.0:
		border = border.lerp(Color.WHITE, _ready_flash)
	if _deny > 0.0:
		border = UITheme.RED
	draw_rect(r, border, false, 2.0 if selected or _ready_flash > 0.0 else 1.0)
	# Name (two lines max).
	var name_col := UITheme.TEXT if usable else UITheme.TEXT_DIM
	var words: String = d.name
	var lines := _wrap(words, 9, size.x - 14)
	for i in lines.size():
		draw_string(_font, r.position + Vector2(9, 13 + i * 10), lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 14, 9, name_col)
	# Hotkey.
	draw_string(_font, r.position + Vector2(size.x - 11, 10), str(slot + 1), HORIZONTAL_ALIGNMENT_LEFT, 10, 8, UITheme.TEXT_DIM)
	# RAM cost chip.
	var ram_ok := sim.ram + 0.0001 >= float(d.ram)
	var chip := Rect2(r.position + Vector2(8, size.y - 15), Vector2(26, 11))
	draw_rect(chip, Color(0, 0, 0, 0.6))
	draw_rect(chip, UITheme.CYAN if ram_ok else UITheme.RED, false, 1.0)
	draw_string(_font, chip.position + Vector2(0, 9), "%d" % int(d.ram), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 9, UITheme.CYAN if ram_ok else UITheme.RED)
	# Target type hint.
	var hint: String = {"enemy": "ENEMY", "ally": "ALLY", "none": "ALL"}.get(d.target, "")
	draw_string(_font, r.position + Vector2(38, size.y - 6), hint, HORIZONTAL_ALIGNMENT_LEFT, 40, 7, col.darkened(0.2) if usable else UITheme.TEXT_DIM.darkened(0.3))
	# Charges.
	if int(d.get("charges", 0)) > 0:
		draw_string(_font, r.position + Vector2(size.x - 24, size.y - 6), "x%d" % s.charges, HORIZONTAL_ALIGNMENT_RIGHT, 20, 9, UITheme.YELLOW if s.charges > 0 else UITheme.TEXT_DIM)
	# Cooldown sweep: dark shade that shrinks downward + seconds.
	if s.cd_t > 0.0 and float(d.cd) > 0.0:
		var f: float = s.cd_t / float(d.cd)
		var h := (size.y - 2) * f
		draw_rect(Rect2(r.position + Vector2(1, size.y - 1 - h), Vector2(size.x - 2, h)), Color(0, 0, 0, 0.62))
		draw_line(r.position + Vector2(1, size.y - 1 - h), r.position + Vector2(size.x - 1, size.y - 1 - h), Color(col.r, col.g, col.b, 0.8), 1.0)
		draw_string_outline(_font, r.position + Vector2(0, size.y / 2 + 6), "%.1f" % s.cd_t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, 4, Color.BLACK)
		draw_string(_font, r.position + Vector2(0, size.y / 2 + 6), "%.1f" % s.cd_t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color.WHITE)
	elif reason == "charges":
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.55))
		draw_string(_font, r.position + Vector2(0, size.y / 2 + 4), "SPENT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, UITheme.TEXT_DIM)
	elif reason == "ram":
		# RAM fill progress towards affordability.
		var f := clampf(sim.ram / float(d.ram), 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(1, size.y - 3), Vector2((size.x - 2) * f, 2)), UITheme.CYAN.darkened(0.3))


func _wrap(s: String, fsize: int, width: float) -> Array:
	if _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= width:
		return [s]
	var words := s.split(" ")
	var out := []
	var line := ""
	for w in words:
		var cand := w if line == "" else line + " " + w
		if _font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and line != "":
			out.append(line)
			line = w
		else:
			line = cand
	if line != "":
		out.append(line)
	return out.slice(0, 2)
