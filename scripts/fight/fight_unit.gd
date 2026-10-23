extends Node2D
## A unit on the flat battlefield: sprite (idle bob, attack frame, hit flash, death fade),
## HP bar with shield, status marks, and for enemies the intent badge above the head.
## HP shown is `shown_hp`, driven by replayed events so numbers land with the animation.

const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, flash_color.rgb, flash), c.a);
}
"""
const BADGE_W := 36.0

static var _shader: Shader

var c: DiceCombat
var uid := 0
var scale_px := 2.0
var frames: Array = []
var sprite: Sprite2D
var mat: ShaderMaterial
var shown_hp := 0
var dead := false
var gone := false
var show_intent := true
var highlight := 0        # 1 valid target, -1 dimmed
var _flash := 0.0
var _flash_col := Color.WHITE
var _attack := 0.0
var _dead_t := 0.0
var _t := 0.0
var _font: Font


func setup(p_c: DiceCombat, u: DiceCombat.Unit) -> void:
	c = p_c
	uid = u.id
	_font = ThemeDB.fallback_font
	scale_px = 3.0 if u.boss else 2.0
	frames = PixelSprites.frames(u.kind, u.seed)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = FLASH_SHADER
	mat = ShaderMaterial.new()
	mat.shader = _shader
	sprite = Sprite2D.new()
	sprite.texture = frames[0]
	sprite.material = mat
	sprite.scale = Vector2(scale_px, scale_px)
	sprite.flip_h = u.team == DiceCombat.ENEMY
	sprite.position = Vector2(0, -12.0 * scale_px)
	add_child(sprite)
	shown_hp = u.hp
	_t = randf() * 10.0


func unit() -> DiceCombat.Unit:
	return c.get_unit(uid)


func body_pos() -> Vector2:
	return position + sprite.position


func head_pos() -> Vector2:
	return position + Vector2(0, -24.0 * scale_px - 4.0)


## Where intent lines start (enemies) / end (mercs).
func badge_pos() -> Vector2:
	return head_pos() + Vector2(0, -16)


func hit(col := Color.WHITE) -> void:
	_flash = 1.0
	_flash_col = col


func attack() -> void:
	_attack = 0.2


func die() -> void:
	dead = true


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 5.0)
	_attack = maxf(0.0, _attack - delta)
	var u := unit()
	if u == null:
		return
	var face := -1.0 if u.team == DiceCombat.ENEMY else 1.0
	if dead:
		_dead_t += delta
		sprite.rotation = lerp_angle(sprite.rotation, (-PI / 2.0) * face, minf(1.0, _dead_t * 8.0))
		sprite.position = Vector2(0, -5.0 * scale_px)
		if u.team == DiceCombat.ENEMY:
			modulate.a = clampf(1.4 - _dead_t, 0.0, 1.0)
			gone = _dead_t > 1.4
		else:
			sprite.modulate = Color(0.45, 0.45, 0.55)
	else:
		sprite.texture = frames[2] if _attack > 0.0 else frames[0]
		sprite.position = Vector2(face * (4.0 if _attack > 0.0 else 0.0), -12.0 * scale_px + round(sin(_t * 2.2 + uid) * 0.6))
		var m := Color.WHITE
		if highlight < 0:
			m = Color(0.45, 0.45, 0.55, 0.7)
		if u.stunned:
			m = m * Color(0.7, 0.85, 1.0)
		sprite.modulate = m
	mat.set_shader_parameter("flash", _flash)
	mat.set_shader_parameter("flash_color", _flash_col)
	queue_redraw()


func _draw() -> void:
	var u := unit()
	if u == null or gone:
		return
	var s := scale_px
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 9.0 * s, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
	if dead:
		return
	# HP bar + numbers under the feet.
	var bw := 40.0 if u.boss else 30.0
	var y := 6.0
	draw_rect(Rect2(-bw / 2 - 1, y - 1, bw + 2, 6), Color(0, 0, 0, 0.8))
	var k := clampf(float(shown_hp) / float(u.max_hp), 0.0, 1.0)
	var col := UITheme.GREEN if u.team == DiceCombat.CREW else UITheme.RED
	draw_rect(Rect2(-bw / 2, y, bw * k, 4), col)
	var txt := "%d/%d" % [maxi(0, shown_hp), u.max_hp]
	if u.shield > 0:
		txt += " +%d" % u.shield
	_text(Vector2(0, y + 14), txt, 9, Color("8ab4ff") if u.shield > 0 else UITheme.TEXT)
	# Status marks.
	var marks := []
	if u.vuln > 0:
		marks.append(["+%d" % u.vuln, Color("ffe066")])
	if u.breached:
		marks.append(["BRC", Color("ffe066")])
	if u.armor > 0 and not u.breached:
		marks.append(["ARM%d" % u.armor, UITheme.TEXT_DIM])
	if u.front_shield and not u.breached:
		marks.append(["SHLD", Color("8ab4ff")])
	if not u.burns.is_empty():
		marks.append(["BURN", Color("ff9f1c")])
	if u.dodge:
		marks.append(["DDG", UITheme.CYAN])
	if u.taunt:
		marks.append(["TNT", Color("ff9f1c")])
	if u.firewall:
		marks.append(["FW", Color("3d8bff")])
	if u.turret_turns > 0:
		marks.append(["TUR", UITheme.CYAN])
	if u.affix != "":
		marks.append([String(UnitDB.AFFIXES[u.affix].name).substr(0, 4).to_upper(), Color("ff9f1c")])
	for i in marks.size():
		_text(Vector2(0, y + 24 + i * 9), marks[i][0], 8, marks[i][1])
	# Targeting highlight.
	if highlight > 0:
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		var half := Vector2(10.0 * s * 0.8 + pulse * 2.0, 13.0 * s * 0.8 + pulse * 2.0)
		var cc := Vector2(0, -12.0 * s)
		var hc := UITheme.GREEN if u.team == DiceCombat.CREW else UITheme.CYAN
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := cc + Vector2(half.x * sx, half.y * sy)
				draw_line(corner, corner + Vector2(-6 * sx, 0), hc, 2.0)
				draw_line(corner, corner + Vector2(0, -6 * sy), hc, 2.0)
	# Intent badge (enemies).
	if u.team == DiceCombat.ENEMY and show_intent and not u.intent.is_empty():
		var bp := badge_pos() - position
		var f := u.intent
		var r := Rect2(bp - Vector2(BADGE_W / 2.0, 8), Vector2(BADGE_W, 14))
		var ic := _intent_color(String(f.k))
		var cancelled := u.stunned or u.spoofed or u.hijacked
		draw_rect(r, Color(0, 0, 0, 0.85))
		draw_rect(r, ic if not cancelled else UITheme.TEXT_DIM, false, 1.0)
		var tag := UnitDB.intent_tag(f)
		_text(r.position + Vector2(BADGE_W / 2.0, 11), tag, 9, ic if not cancelled else UITheme.TEXT_DIM)
		if cancelled:
			draw_line(r.position + Vector2(2, 7), r.end - Vector2(2, 7), UITheme.CYAN, 1.5)


static func _intent_color(k: String) -> Color:
	match k:
		"guard": return Color("8ab4ff")
		"aim", "snipe": return UITheme.RED
		"upload": return UITheme.PURPLE
		"charge", "rampage": return Color("ff2a2a")
		"blank", "summon": return UITheme.TEXT_DIM
	return Color("ff6a2a")


func _text(p: Vector2, txt: String, fs: int, col: Color) -> void:
	var w := 80.0
	draw_string_outline(_font, p - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(_font, p - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)
