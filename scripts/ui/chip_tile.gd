class_name ChipTile
extends Control
## A deck chip drawn as a colour-coded tile: kind colour (trigger yellow, selector green,
## modifier blue, payload red), 2-4 letter tag, RAM cost, tier pips. Used by the combat
## HUD (static draw_tile) and by the deck editor / loot cards as a tappable Control.

signal pressed(tile: ChipTile)

var ref := ""
var selected := false
var dim := false
var hint := ""           # small caption under the tile ("slot 1", "TRIGGER only")
var _t := 0.0
var _font: Font


static func draw_tile(ci: CanvasItem, font: Font, r: Rect2, ref: String, lit := 0.0, dimmed := false, sel := false, t := 0.0) -> void:
	if ref == "":
		var c := Color("2a2a48")
		ci.draw_rect(r, Color(0, 0, 0, 0.35))
		var step := 4.0
		var x := r.position.x
		while x < r.end.x:
			ci.draw_line(Vector2(x, r.position.y), Vector2(minf(x + 2, r.end.x), r.position.y), c)
			ci.draw_line(Vector2(x, r.end.y), Vector2(minf(x + 2, r.end.x), r.end.y), c)
			x += step
		var y := r.position.y
		while y < r.end.y:
			ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x, minf(y + 2, r.end.y)), c)
			ci.draw_line(Vector2(r.end.x, y), Vector2(r.end.x, minf(y + 2, r.end.y)), c)
			y += step
		if sel:
			ci.draw_rect(r, UITheme.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 9.0)), false, 2.0)
		return
	var d := ChipDB.get_def(ref)
	var kc := ChipDB.kind_color(String(d.get("kind", "")))
	var pc: Color = d.get("color", kc)
	var a := 0.45 if dimmed else 1.0
	ci.draw_rect(r, Color(kc.darkened(0.78), a))
	if lit > 0.0:
		ci.draw_rect(r.grow(2), Color(pc, 0.35 * lit))
		ci.draw_rect(r, Color(pc.darkened(0.3), 0.6 * lit))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(kc, a))
	var border := Color(kc.darkened(0.25), a)
	if lit > 0.0:
		border = border.lerp(Color.WHITE, lit)
	if sel:
		border = UITheme.CYAN.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 9.0))
	ci.draw_rect(r, border, false, 2.0 if sel or lit > 0.5 else 1.0)
	var fs := 11 if r.size.x >= 40 else 9
	var tag := String(d.get("tag", "?"))
	var tc := Color(UITheme.TEXT, a) if lit <= 0.0 else Color.WHITE
	ci.draw_string_outline(font, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + 4), tag, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 3, Color(0, 0, 0, 0.8))
	ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + 4), tag, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, tc)
	var ram := int(d.get("ram", 0))
	if ram > 0 and r.size.y >= 30:
		ci.draw_string(font, r.position + Vector2(3, r.size.y - 3), str(ram), HORIZONTAL_ALIGNMENT_LEFT, 12, 7, Color(UITheme.CYAN, a))
	if int(d.get("tier", 1)) >= 2:
		for i in 2:
			ci.draw_rect(Rect2(r.end.x - 5 - i * 4, r.end.y - 5, 2, 2), Color(UITheme.YELLOW, a))


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(48, 40)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if selected:
		queue_redraw()


func _draw() -> void:
	var h := size.y - (10.0 if hint != "" else 0.0)
	draw_tile(self, _font, Rect2(1, 1, size.x - 2, h - 2), ref, 0.0, dim, selected, _t)
	if hint != "":
		draw_string(_font, Vector2(0, size.y - 1), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 7, UITheme.TEXT_DIM)
