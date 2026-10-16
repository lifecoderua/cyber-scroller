extends Control
## Small squad status row: face, name, HP. Tappable as an ally target. Emits `tapped(id)`.

signal tapped(unit_id: int)

var sim: CombatSim
var uid := 0
var highlight := 0
var _tex: Texture2D
var _t := 0.0
var _hurt := 0.0
var _last_hp := -1.0
var _font: Font


func setup(p_sim: CombatSim, u: CombatSim.Unit) -> void:
	sim = p_sim
	uid = u.id
	_tex = PixelSprites.portrait(u.kind, u.seed)
	custom_minimum_size = Vector2(118, 22)
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(uid)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	var u := sim.get_unit(uid) if sim else null
	if u:
		if _last_hp >= 0.0 and u.hp < _last_hp - 0.5:
			_hurt = 1.0
		_last_hp = u.hp
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var u := sim.get_unit(uid) if sim else null
	if u == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	var border := UITheme.CYAN.darkened(0.55)
	if highlight > 0:
		border = UITheme.GREEN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0))
	draw_rect(r, Color(0.04, 0.04, 0.09, 0.82))
	if _hurt > 0.0:
		draw_rect(r, Color(1, 0.1, 0.2, _hurt * 0.35))
	draw_rect(r, border, false, 2.0 if highlight > 0 else 1.0)
	# Face crop of the portrait (head rows), zoomed.
	var mod := Color.WHITE if u.alive else Color(0.4, 0.4, 0.45)
	draw_texture_rect_region(_tex, Rect2(2, 2, 18, 18), Rect2(3, 0, 10, 10), mod)
	var nm: String = u.name
	var q := nm.find("\"")
	if q >= 0:
		nm = nm.substr(q).replace("\"", "")
	draw_string(_font, Vector2(23, 10), nm, HORIZONTAL_ALIGNMENT_LEFT, 64, 9, UITheme.TEXT if u.alive else UITheme.TEXT_DIM)
	var cdef: Dictionary = UnitDB.CLASSES.get(u.kind, {})
	draw_string(_font, Vector2(size.x - 34, 10), cdef.get("name", ""), HORIZONTAL_ALIGNMENT_RIGHT, 30, 7, cdef.get("color", UITheme.TEXT_DIM))
	var bar := Rect2(23, 13, size.x - 27, 5)
	draw_rect(bar, Color(0, 0, 0, 0.8))
	if u.alive:
		var c := UITheme.GREEN if u.hp_pct() > 0.35 else (UITheme.RED if fmod(_t, 0.5) < 0.25 else UITheme.YELLOW)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * u.hp_pct(), bar.size.y)), c)
		if u.shield > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(1.0, u.shield / u.max_hp), 2)), Color(0.4, 0.7, 1.0))
	else:
		draw_string(_font, bar.position + Vector2(0, 6), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 8, UITheme.RED)
