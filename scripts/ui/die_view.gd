class_name DieView
extends Control
## One merc die in the fight tray: the rolled face big (keyword colour + pips), lock and
## used states, a gear / chrome marker. Also draws single faces for the crew sheet and
## loot previews (static draw_face). Emits pressed(die_view).

signal pressed(view: DieView)

var face := {}
var which := "gear"
var locked := false
var used := false
var selected := false
var valid := false        # a legal target for the pending hack
var dim := false
var _t := 0.0
var _roll := 0.0          # >0 while the roll tumble plays
var _font: Font


static func draw_face(ci: CanvasItem, font: Font, r: Rect2, f: Dictionary, alpha := 1.0) -> void:
	var k := String(f.get("k", "blank"))
	var kd := DiceDB.kw(k)
	var col: Color = kd.color
	ci.draw_rect(r, Color(col.darkened(0.78), alpha))
	ci.draw_rect(r, Color(col.darkened(0.2), alpha), false, 1.0)
	if k == "blank":
		var m := r.get_center()
		ci.draw_line(m - Vector2(r.size.x * 0.18, 0), m + Vector2(r.size.x * 0.18, 0), Color(col.lightened(0.2), alpha), 2.0)
		return
	var tag := String(kd.tag)
	var big := r.size.y >= 36.0
	var fs := 12 if big else 8
	var cy := r.position.y + (r.size.y * 0.42 if big else r.size.y * 0.5 + 3)
	ci.draw_string_outline(font, Vector2(r.position.x, cy), tag, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 3, Color(0, 0, 0, alpha * 0.8))
	ci.draw_string(font, Vector2(r.position.x, cy), tag, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(col.lightened(0.35), alpha))
	var v := int(f.get("v", 0))
	if v > 0:
		if big:
			ci.draw_string_outline(font, Vector2(r.position.x, r.end.y - 6), str(v), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, 4, Color(0, 0, 0, alpha))
			ci.draw_string(font, Vector2(r.position.x, r.end.y - 6), str(v), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, Color(1, 1, 1, alpha))
		else:
			ci.draw_string(font, Vector2(r.end.x - 9, r.end.y - 2), str(v), HORIZONTAL_ALIGNMENT_LEFT, 9, 7, Color(1, 1, 1, alpha))
	if int(f.get("burn", 0)) > 0:
		ci.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(3, 3)), Color("ff9f1c"))


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(52, 52)


func tumble() -> void:
	_roll = 0.35


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	_roll = maxf(0.0, _roll - delta)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var a := 0.35 if used or dim else 1.0
	if _roll > 0.0:
		var keys := DiceDB.KEYWORDS.keys()
		var fake := DiceDB.face(keys[int(_t * 30.0) % keys.size()], 1 + int(_t * 20.0) % 5)
		draw_face(self, _font, r.grow(-randf() * 2.0), fake, 0.8)
	else:
		draw_face(self, _font, r, face, a)
	# Gear / chrome marker in the corner.
	var mc := Color("8a8fa8") if which == "gear" else Color("ff6ad5")
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(8, 3)), Color(mc, a))
	if locked:
		var lc := UITheme.CYAN
		draw_rect(r.grow(1), lc, false, 2.0)
		draw_rect(Rect2(r.end - Vector2(11, r.size.y - 2), Vector2(9, 7)), lc)
		draw_arc(r.end - Vector2(6.5, r.size.y - 3), 3.0, PI, TAU, 8, lc, 1.5)
	if selected:
		draw_rect(r.grow(2), UITheme.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0)), false, 2.0)
	if valid:
		draw_rect(r.grow(2), UITheme.GREEN.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 9.0)), false, 2.0)
	if used:
		draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Color(1, 1, 1, 0.25), 2.0)
