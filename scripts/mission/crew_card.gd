extends Control
## Crew status card in the combat HUD: face, name, HP, stress (over-chromed mercs),
## status marks. Tappable as an ally target. Emits `tapped(unit_id)`.

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
	custom_minimum_size = Vector2(110, 44)
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
	var cdef: Dictionary = UnitDB.CLASSES.get(u.kind, {})
	var ccol: Color = cdef.get("color", UITheme.TEXT_DIM)
	var border := ccol.darkened(0.5)
	if highlight > 0:
		border = UITheme.GREEN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0))
	if u.psycho_t > 0.0:
		border = UITheme.RED if fmod(_t, 0.3) < 0.15 else Color.WHITE
	draw_rect(r, Color(0.04, 0.04, 0.09, 0.9))
	if _hurt > 0.0:
		draw_rect(r, Color(1, 0.1, 0.2, _hurt * 0.35))
	draw_rect(r, border, false, 2.0 if highlight > 0 else 1.0)
	var mod := Color.WHITE if u.alive else Color(0.4, 0.4, 0.45)
	draw_rect(Rect2(3, 3, 24, 24), Color(0, 0, 0, 0.5))
	draw_texture_rect_region(_tex, Rect2(3, 3, 24, 24), Rect2(3, 0, 10, 10), mod)
	draw_string(_font, Vector2(31, 12), UnitDB.short_name({"name": u.name}), HORIZONTAL_ALIGNMENT_LEFT, size.x - 34, 10, UITheme.TEXT if u.alive else UITheme.TEXT_DIM)
	draw_string(_font, Vector2(31, 22), String(cdef.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 50, 8, ccol)
	# Status marks on the right of the class line.
	var marks := []
	if u.firewall:
		marks.append(["FW", Color("3d8bff")])
	if u.haste_t > 0.0:
		marks.append(["OD", UITheme.YELLOW])
	if u.dr_t > 0.0:
		marks.append(["BW", Color("ff9f1c")])
	if not u.dots.is_empty():
		marks.append(["HOT", UITheme.PURPLE])
	var mx := size.x - 4.0
	for m in marks:
		var w := _font.get_string_size(m[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 2
		mx -= w
		draw_string(_font, Vector2(mx, 22), m[0], HORIZONTAL_ALIGNMENT_LEFT, w, 7, m[1])
		mx -= 2
	var bar := Rect2(4, 29, size.x - 8, 7)
	draw_rect(bar, Color(0, 0, 0, 0.8))
	if u.alive:
		var c := UITheme.GREEN if u.hp_pct() > 0.35 else (UITheme.RED if fmod(_t, 0.5) < 0.25 else UITheme.YELLOW)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * u.hp_pct(), bar.size.y)), c)
		if u.shield > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(1.0, u.shield / u.max_hp), 2)), Color(0.4, 0.7, 1.0))
		draw_string_outline(_font, Vector2(bar.position.x, bar.position.y + 7), "%d" % int(ceil(u.hp)), HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x - 2, 8, 3, Color(0, 0, 0, 0.9))
		draw_string(_font, Vector2(bar.position.x, bar.position.y + 7), "%d" % int(ceil(u.hp)), HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x - 2, 8, Color.WHITE)
	else:
		draw_string(_font, bar.position + Vector2(0, 7), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 8, UITheme.RED)
	# Stress: only for over-chromed mercs.
	if float(u.stats.get("chrome_over", 0.0)) > 0.0 and u.alive:
		var sb := Rect2(4, 38, size.x - 8, 3)
		draw_rect(sb, Color(0, 0, 0, 0.8))
		var k := u.stress / UnitDB.STRESS_MAX if u.psycho_t <= 0.0 else u.psycho_t / CombatSim.PSYCHO_TIME
		draw_rect(Rect2(sb.position, Vector2(sb.size.x * clampf(k, 0.0, 1.0), sb.size.y)), UITheme.RED if u.psycho_t > 0.0 else Color("ff6ad5"))
	if u.psycho_t > 0.0:
		draw_string_outline(_font, Vector2(0, 22), "PSYCHO", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, 3, Color.BLACK)
		draw_string(_font, Vector2(0, 22), "PSYCHO", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, UITheme.RED)
