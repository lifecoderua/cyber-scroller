extends Node2D
## Renders one CombatSim unit: sprite (walk/attack frames, hit flash), shadow, HP bar,
## telegraph bar + aim line / impact marker, status marks and targeting brackets.
## Positioned in world coords.

const STREET_Y := 292.0
const FLY_HEIGHT := 56.0
const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, flash_color.rgb, flash), c.a);
}
"""

const CAST_LABELS := {"aim": "AIMING", "grenade": "GRENADE", "upload": "UPLOAD", "berserk_charge": "BERSERK CHARGE"}

static var _shader: Shader

var sim: CombatSim
var uid := 0
var scale_px := 2.0
var frames: Array = []
var sprite: Sprite2D
var mat: ShaderMaterial
var flash := 0.0
var flash_color := Color.WHITE
var attack_t := 0.0
var walk_t := 0.0
var walk_frame := 0
var highlight := 0  # 1 valid target, -1 dimmed, 0 normal
var hover := false
var shown_hp := 1.0
var dead_t := 0.0
var spawn_t := 0.0
var kick := 0.0  # recoil / lunge offset
var gone := false
var _t := 0.0
var _font: Font


func setup(p_sim: CombatSim, u: CombatSim.Unit) -> void:
	sim = p_sim
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
	sprite.flip_h = u.team == CombatSim.ENEMY
	sprite.position = Vector2(0, -12.0 * scale_px)
	add_child(sprite)
	shown_hp = u.hp_pct()
	spawn_t = 0.0 if u.team == CombatSim.MERC else 0.01
	_t = randf() * 10.0
	z_index = 1 if u.team == CombatSim.MERC else 0
	if u.boss:
		z_index = 2


func unit() -> CombatSim.Unit:
	return sim.get_unit(uid)


## Centre of the body in world coordinates (used for tracers, popups, hit tests).
func body_pos() -> Vector2:
	return position + sprite.position


func head_pos() -> Vector2:
	return position + Vector2(0, -24.0 * scale_px - 2.0) + (Vector2(0, 12) if unit() and not unit().alive else Vector2.ZERO)


func hit(col := Color.WHITE, strength := 1.0) -> void:
	flash = maxf(flash, strength)
	flash_color = col


func on_attack() -> void:
	attack_t = 0.14
	kick = 3.0


func tick(sim_dt: float, real_dt: float) -> void:
	var u := unit()
	if u == null:
		return
	_t += real_dt
	flash = maxf(0.0, flash - real_dt * 6.0)
	attack_t = maxf(0.0, attack_t - sim_dt)
	kick = move_toward(kick, 0.0, real_dt * 30.0)
	if spawn_t > 0.0 and spawn_t < 1.0:
		spawn_t = minf(1.0, spawn_t + real_dt * 3.0)
	shown_hp = move_toward(shown_hp, u.hp_pct(), real_dt * 0.6) if shown_hp > u.hp_pct() else u.hp_pct()
	var y := STREET_Y + u.lane
	if u.flying and u.alive:
		y -= FLY_HEIGHT + sin(_t * 3.0 + uid) * 3.0
	sprite.flip_h = u.side() == CombatSim.ENEMY
	var face := -1.0 if u.side() == CombatSim.ENEMY else 1.0
	position = Vector2(round(u.x + kick * face * (1.0 if attack_t > 0.0 else -0.5)), round(y))
	# Frames.
	if not u.alive:
		dead_t += real_dt
		sprite.texture = frames[0]
		sprite.rotation = lerp_angle(sprite.rotation, (-PI / 2.0) * face, minf(1.0, dead_t * 8.0))
		sprite.position = Vector2(0, -5.0 * scale_px)
		if u.flying:
			position.y = round(STREET_Y + u.lane - maxf(0.0, FLY_HEIGHT * (1.0 - dead_t * 3.0)))
		if u.team == CombatSim.MERC and u.merc_id != "":
			sprite.modulate = Color(0.45, 0.45, 0.55, 1.0)
		else:
			sprite.modulate = Color(1, 1, 1, clampf(1.6 - dead_t, 0.0, 1.0))
			if dead_t > 1.6:
				gone = true
	else:
		if attack_t > 0.0:
			sprite.texture = frames[2]
		elif u.moving:
			walk_t += sim_dt
			if walk_t > 0.18:
				walk_t = 0.0
				walk_frame = 1 - walk_frame
			sprite.texture = frames[walk_frame]
		else:
			sprite.texture = frames[0]
		sprite.rotation = 0.0
		var bob := 0.0
		if not u.moving and attack_t <= 0.0 and u.stun <= 0.0:
			bob = round(sin(_t * 2.2 + uid) * 0.6)
		sprite.position = Vector2(0, -12.0 * scale_px + bob)
		var m := Color.WHITE
		if u.is_casting():
			var p := 0.5 + 0.5 * sin(_t * 18.0)
			m = Color(1.0, 0.6 + 0.3 * p, 0.6 + 0.3 * p)
		if u.psycho_t > 0.0:
			m = Color(1.0, 0.45, 0.45) if fmod(_t, 0.25) < 0.15 else Color(1.0, 0.8, 0.8)
		if u.hijack_t > 0.0:
			m = Color(1.0, 0.55, 0.9)
		if u.stun > 0.0:
			m = m * Color(0.75, 0.9, 1.0)
		if highlight < 0:
			m = m * Color(0.45, 0.45, 0.55, 0.7)
		m.a *= spawn_t if spawn_t > 0.0 else 1.0
		sprite.modulate = m
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("flash_color", flash_color)
	queue_redraw()


func _draw() -> void:
	var u := unit()
	if u == null or gone:
		return
	var s := scale_px
	var ground := STREET_Y + u.lane - position.y
	# Shadow.
	var sh_w := 9.0 * s * (0.6 if u.flying and u.alive else 1.0)
	draw_set_transform(Vector2(0, ground), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, sh_w, Color(0, 0, 0, 0.45 if u.alive else 0.25))
	draw_set_transform(Vector2.ZERO)
	if not u.alive:
		return
	var top := -24.0 * s - 6.0
	# Shield bubble.
	if u.shield > 0.0:
		var a := 0.25 + 0.1 * sin(_t * 6.0)
		draw_arc(Vector2(0, -12.0 * s), 13.0 * s * 0.75, 0, TAU, 24, Color(0.24, 0.55, 1.0, a + 0.3), 1.5)
		draw_circle(Vector2(0, -12.0 * s), 13.0 * s * 0.75, Color(0.24, 0.55, 1.0, a * 0.4))
	# HP bar.
	var bw := 46.0 if u.boss else 22.0
	var bh := 4.0 if u.boss else 3.0
	var bx := -bw / 2.0
	draw_rect(Rect2(bx - 1, top - 1, bw + 2, bh + 2), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(bx, top, bw * shown_hp, bh), Color(1, 1, 1, 0.85))
	var hp_col := UITheme.GREEN if u.side() == CombatSim.MERC else (UITheme.RED if not u.enraged else Color("ff7a2a"))
	if u.hijack_t > 0.0:
		hp_col = Color("ff6ad5")
	if u.team == CombatSim.MERC and u.hp_pct() < 0.35:
		hp_col = UITheme.YELLOW if fmod(_t, 0.5) < 0.25 else UITheme.RED
	draw_rect(Rect2(bx, top, bw * u.hp_pct(), bh), hp_col)
	if u.shield > 0.0:
		draw_rect(Rect2(bx, top - 2, bw * minf(1.0, u.shield / u.max_hp * 2.0), 1.5), Color(0.4, 0.7, 1.0))
	# Telegraph: bar + label, and where it will land.
	if u.is_casting():
		var cw := 52.0 if u.boss else 38.0
		var cy := top - 11.0
		var p := 1.0 - u.cast_t / maxf(0.01, u.cast_total)
		var blink := fmod(_t, 0.2) < 0.1
		draw_rect(Rect2(-cw / 2 - 1, cy - 1, cw + 2, 6), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-cw / 2, cy, cw * p, 4), UITheme.YELLOW if blink else Color("ff7a2a"))
		_text(Vector2(0, cy - 3), "%s %.1f" % [CAST_LABELS.get(u.cast_name, "!!"), u.cast_t], 8, UITheme.YELLOW if blink else Color.WHITE)
		var tgt := sim.get_unit(u.cast_target)
		if tgt != null and tgt.alive:
			var to := Vector2(tgt.x - u.x, STREET_Y + tgt.lane - position.y - 12.0 * 2.0)
			if u.cast_name == "aim":
				var from := Vector2(-8.0 * s, -12.5 * s)
				var a := 0.35 + 0.5 * p
				var seg := 6.0
				var dist := from.distance_to(to)
				var dir := (to - from) / maxf(1.0, dist)
				var d := fmod(_t * 40.0, seg * 2.0)
				while d < dist:
					draw_line(from + dir * d, from + dir * minf(dist, d + seg), Color(1, 0.15, 0.2, a), 1.0)
					d += seg * 2.0
				draw_circle(to, 3.0 + 2.0 * p, Color(1, 0.15, 0.2, a))
			elif u.cast_name == "grenade":
				var impact := Vector2(tgt.x - u.x, STREET_Y + tgt.lane - position.y)
				draw_set_transform(impact, 0.0, Vector2(1.0, 0.35))
				var rr := float(u.cast_def.get("radius", 40.0))
				draw_arc(Vector2.ZERO, rr, 0, TAU, 28, Color(1, 0.6, 0.1, 0.4 + 0.5 * p), 2.0)
				draw_circle(Vector2.ZERO, rr * p, Color(1, 0.5, 0.1, 0.18))
				draw_set_transform(Vector2.ZERO)
			elif u.cast_name == "upload":
				draw_line(Vector2(0, -12.0 * s), to, Color(UITheme.PURPLE, 0.25 + 0.4 * p), 1.0)
	# Status marks.
	var mx := bw / 2.0 + 3.0
	if u.stun > 0.0:
		for i in 3:
			var ang := _t * 6.0 + i * TAU / 3.0
			draw_rect(Rect2(Vector2(cos(ang) * 7.0, top - 4 + sin(ang) * 2.0), Vector2(2, 2)), UITheme.YELLOW)
	if u.taunt_t > 0.0 and u.team == CombatSim.ENEMY:
		_text(Vector2(mx + 2, top + 4), "!", 9, UITheme.MAGENTA)
	var icons := []
	if u.dots.size() > 0:
		icons.append(u.dots[0].color)
	if u.haste_t > 0.0:
		icons.append(UITheme.YELLOW)
	if u.breach_t > 0.0:
		icons.append(Color("ffe066"))
	if u.infect_t > 0.0:
		icons.append(Color("9bff3d"))
	for i in icons.size():
		draw_rect(Rect2(bx - 5 - i * 4, top, 3, 3), icons[i])
	if u.mark_t > 0.0:
		var c := Vector2(0, -12.0 * s)
		var rr := 9.0 + sin(_t * 8.0)
		draw_arc(c, rr, 0, TAU, 16, Color(UITheme.YELLOW, 0.7), 1.0)
		draw_line(c + Vector2(-rr - 3, 0), c + Vector2(-rr + 3, 0), UITheme.YELLOW, 1.0)
		draw_line(c + Vector2(rr - 3, 0), c + Vector2(rr + 3, 0), UITheme.YELLOW, 1.0)
	if u.front_shield > 0.0 and u.breach_t <= 0.0:
		var sx := -9.0 * s if u.side() == CombatSim.ENEMY else 9.0 * s
		draw_rect(Rect2(sx - 1, -20.0 * s, 2, 16.0 * s), Color(0.55, 0.75, 1.0, 0.55 + 0.2 * sin(_t * 5.0)))
	if u.affix != "":
		_text(Vector2(0, top - (20.0 if u.is_casting() else 4.0)), String(UnitDB.AFFIXES[u.affix].name).to_upper(), 7, Color("ff9f1c"))
	if u.life_t > 0.0:
		draw_rect(Rect2(bx, top + bh + 1, bw * clampf(u.life_t / float(UnitDB.TURRET.life), 0.0, 1.0), 1), UITheme.CYAN)
	# Targeting brackets.
	if highlight > 0:
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		var half := Vector2(10.0 * s * 0.75 + pulse * 3.0, 13.0 * s * 0.75 + pulse * 3.0)
		var c := Vector2(0, -12.0 * s)
		var col := (UITheme.GREEN if u.side() == CombatSim.MERC else UITheme.CYAN)
		if hover:
			col = Color.WHITE
		col.a = 0.7 + 0.3 * pulse
		var L := 6.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := c + Vector2(half.x * sx, half.y * sy)
				draw_line(corner, corner + Vector2(-L * sx, 0), col, 2.0)
				draw_line(corner, corner + Vector2(0, -L * sy), col, 2.0)


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var w := 120.0
	draw_string_outline(_font, pos - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 3, Color(0, 0, 0, 0.9))
	draw_string(_font, pos - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)
