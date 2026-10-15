class_name CityBackdrop
extends Node2D
## Procedural, infinite, parallax night-city backdrop: sky, three skyline layers,
## street props, wet street with reflections, and rain.
##
## Usage: add as the FIRST child of the world Node2D (world coordinates, camera scrolls
## along x only) and call update_view(camera_left_x, view_size) whenever the camera moves.
## Optional: set_district("Kabuki" | "Watson Docks" | "Glen Spire" | "Neon Row").
##
## Art is generated per chunk (128 art px = 256 screen px) into half-resolution
## ImageTextures that are drawn at 2x, so every art pixel is a chunky 2x2 block.
## Chunks are deterministic (seeded by district + layer + chunk index), cached while
## visible and freed when they scroll away. Animated touches (blinking beacons, neon
## flicker, reflections, flying cars, search beams, rain) are cheap primitives in _draw().

const U := 2  # screen px per art px
const CHUNK := 128  # art px per chunk
const STREET := 146  # art px; street surface top = 292 screen px
const ART_H := 180
const GF_TOP := 124  # art px; ground-floor line of the street-level buildings

const L_FAR := 0
const L_MID := 1
const L_BACK := 2
const L_NEAR := 3
const FACTORS := [0.12, 0.3, 0.6, 1.0]

const RAIN_FAR := 70
const RAIN_NEAR := 46

const SHOP_WORDS := ["NOODLE", "RAMEN", "OPEN 24", "BAR", "HOTEL", "SUSHI", "CLINIC", "CHROME",
	"KARAOKE", "DRINK", "24H", "LIQUOR", "DOLLS", "BIONIC", "SOBA", "REPAIR", "VOID", "GYM",
	"PAWN", "DELI", "JACK IN", "DOC", "TEA", "LOVE", "ARCADE", "CYBER", "MOTEL", "IMPLANT"]
const CORP_NAMES := ["KAGEMORI", "NOVAGEN", "SYNCORA", "ORBITA", "HYOGA", "VOLKOV", "MAXOS",
	"TESSERA", "KUROKAMI", "AXION", "OBSIDIAN", "SEIRYU", "NEXUM", "RAIJIN", "OMNIVA",
	"ZENKO", "IKARI", "MERIDIAN", "HALCYON", "TSURUGI"]
const SLOGANS := ["BUY", "OBEY", "2077", "NEW", "LIVE", "DREAM", "UPGRADE", "SAFE"]

const FONT := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111",
	"0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
	"4": "101101111001001", "5": "111100110001110", "6": "011100111101111", "7": "111001010010010",
	"8": "111101111101111", "9": "111101111001110", "-": "000000111000000", "+": "000010111010000",
}

const DISTRICTS := {
	"Neon Row": {
		"sky": ["05040e", "0c0922", "1d0f3c", "3a1650"], "haze": "3a1752",
		"far": "1a1234", "far_win": ["54467e", "7a4a6e", "3f6a85"],
		"mid": "110c26", "mid_rim": "251b48", "win": ["d29a48", "48b4c4", "9a6ad6", "c45a8a"],
		"back": "0d0a1c", "trim": "1e1836", "near": "0c0a16", "near_hi": "2a2342",
		"side": "17122a", "curb": "241c3a", "asphalt": "0a0814",
		"neon": ["2de2e6", "ff3d81", "f9c80e", "b388ff", "4cff8f"], "lamp": "ffc870", "hmult": 1.0,
	},
	"Kabuki": {
		"sky": ["0a0410", "180724", "36103c", "62184e"], "haze": "561650",
		"far": "220c30", "far_win": ["7a3a6e", "a04a7a", "5a4a8a"],
		"mid": "170a22", "mid_rim": "361444", "win": ["e07ab0", "c45aff", "f0a060", "ff5a7a"],
		"back": "110717", "trim": "2a1430", "near": "0e0812", "near_hi": "3a1e3e",
		"side": "1c1024", "curb": "2c1a34", "asphalt": "0c0610",
		"neon": ["ff3d81", "ff6ad5", "d65cff", "ff2a6a", "2de2e6"], "lamp": "ff9ad0", "hmult": 0.95,
	},
	"Watson Docks": {
		"sky": ["05070c", "0b121c", "1c1e2a", "46291e"], "haze": "4a2a1e",
		"far": "151a24", "far_win": ["6a5a40", "3a6a6a", "5a4a3a"],
		"mid": "10141c", "mid_rim": "2a2a30", "win": ["e0a050", "40c0b0", "c06030", "d0d0a0"],
		"back": "0b0d12", "trim": "1e2028", "near": "0a0b10", "near_hi": "2a2c34",
		"side": "15171e", "curb": "22242c", "asphalt": "08090d",
		"neon": ["ff8a2a", "1fd1b5", "f9c80e", "ff4a3a", "2de2e6"], "lamp": "ffa040", "hmult": 0.75,
	},
	"Glen Spire": {
		"sky": ["03060f", "071026", "0f1e46", "1d3866"], "haze": "1a3466",
		"far": "101a34", "far_win": ["3a5a9a", "5a7ab0", "3a8aa0"],
		"mid": "0b1228", "mid_rim": "1c2c58", "win": ["8ac0ff", "50e0f0", "e0e8ff", "9a8aff"],
		"back": "080c1a", "trim": "18223a", "near": "080a14", "near_hi": "222c46",
		"side": "121628", "curb": "1e2438", "asphalt": "070912",
		"neon": ["4aa8ff", "2de2e6", "cfe8ff", "b388ff", "7a8cff"], "lamp": "d0e8ff", "hmult": 1.35,
	},
}


## Off-screen RGBA canvas for one chunk; x is in layer art px (ox = chunk origin).
class Painter:
	var img: Image
	var ox: int
	var oy: int
	var w: int
	var h: int
	var blinks: Array = []  # [Vector2i pos, phase, period]
	var flicks: Array = []  # [Rect2i, seed]
	var refls: Array = []  # [x, w, Color]

	func _init(width: int, height: int, origin_x: int, origin_y: int) -> void:
		img = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		ox = origin_x
		oy = origin_y
		w = width
		h = height

	func owns(x: int) -> bool:
		return x >= ox and x < ox + w

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		if rw <= 0 or rh <= 0:
			return
		if c.a >= 0.999:
			img.fill_rect(Rect2i(x - ox, y - oy, rw, rh), c)
		else:
			blend(x, y, rw, rh, c)

	func blend(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		var x0 := maxi(x - ox, 0)
		var x1 := mini(x - ox + rw, w)
		var y0 := maxi(y - oy, 0)
		var y1 := mini(y - oy + rh, h)
		var ia := 1.0 - c.a
		for yy in range(y0, y1):
			for xx in range(x0, x1):
				var d := img.get_pixel(xx, yy)
				var a := c.a + d.a * ia
				if a <= 0.0:
					continue
				var k := d.a * ia
				img.set_pixel(xx, yy, Color((c.r * c.a + d.r * k) / a, (c.g * c.a + d.g * k) / a,
						(c.b * c.a + d.b * k) / a, a))

	func glow(x: int, y: int, rw: int, rh: int, c: Color, strength := 1.0) -> void:
		blend(x - 3, y - 3, rw + 6, rh + 6, Color(c, 0.05 * strength))
		blend(x - 2, y - 2, rw + 4, rh + 4, Color(c, 0.07 * strength))
		blend(x - 1, y - 1, rw + 2, rh + 2, Color(c, 0.12 * strength))


var _cam := 0.0
var _vw := 640.0
var _vh := 360.0
var _t := 0.0
var _district := "Neon Row"
var _dseed := 0
var _p := {}  # resolved palette (Colors)
var _chunks := {}  # Vector2i(layer, idx) -> Dictionary
var _layouts := {}  # Vector2i(layer, idx) -> Array
var _prefetch: Array[Vector2i] = []

var _sky_tex: ImageTexture
var _ramp_tex: ImageTexture
var _moon_tex: ImageTexture
var _stars: Array = []  # Vector3(x, y, phase)

var _rain_pos := PackedVector2Array()
var _rain_end := PackedFloat32Array()
var _splashes: Array = []  # Vector3(x, y, age)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = 7741
	if _p.is_empty():
		_apply_palette()
	_build_static()
	_init_rain()
	_ensure_chunks(true)


## Called by the mission/hub when the camera moves. Visible world rect is
## x in [camera_left_x, camera_left_x + view_size.x], y in [0, view_size.y].
func update_view(camera_left_x: float, view_size: Vector2) -> void:
	_cam = camera_left_x
	if view_size.x > _vw + 1.0:
		_vw = view_size.x
		_init_rain()
	_vw = view_size.x
	_vh = view_size.y
	if _sky_tex:
		_ensure_chunks(true)
	queue_redraw()


## Optional palette per district. Unknown names fall back to "Neon Row".
func set_district(district_name: String) -> void:
	if not DISTRICTS.has(district_name):
		district_name = "Neon Row"
	if district_name == _district and not _p.is_empty():
		return
	_district = district_name
	_apply_palette()
	_chunks.clear()
	_layouts.clear()
	_prefetch.clear()
	if _sky_tex:
		_build_static()
		_ensure_chunks(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_step_rain(delta)
	if not _prefetch.is_empty():
		var k: Vector2i = _prefetch.pop_front()
		if not _chunks.has(k):
			_chunks[k] = _gen_chunk(k.x, k.y)
	queue_redraw()


# ---------------------------------------------------------------- palette / statics

func _apply_palette() -> void:
	var d: Dictionary = DISTRICTS[_district]
	_dseed = hash(_district) & 0xffff
	_p = {}
	for key in d:
		var v = d[key]
		if v is String:
			_p[key] = Color(v)
		elif v is Array:
			var arr: Array[Color] = []
			for s in v:
				arr.append(Color(s))
			_p[key] = arr
		else:
			_p[key] = v


func _build_static() -> void:
	# Sky gradient (1 x ART_H), stretched horizontally.
	var sky: Array = _p.sky
	var stops := [0.0, 64.0, 112.0, 146.0]
	var img := Image.create_empty(1, ART_H, false, Image.FORMAT_RGBA8)
	for y in ART_H:
		var c: Color = sky[3]
		for i in 3:
			if y <= stops[i + 1]:
				c = (sky[i] as Color).lerp(sky[i + 1], (y - stops[i]) / (stops[i + 1] - stops[i]))
				break
		img.set_pixel(0, y, c)
	_sky_tex = ImageTexture.create_from_image(img)

	# Alpha ramp for haze / fades (transparent at top, opaque at bottom, smoothstep).
	var ramp := Image.create_empty(1, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var f := smoothstep(0.0, 1.0, y / 31.0)
		ramp.set_pixel(0, y, Color(1, 1, 1, f))
	_ramp_tex = ImageTexture.create_from_image(ramp)

	# Moon with halo (48x48 art px).
	var m := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	var halo: Color = (_p.haze as Color).lightened(0.45)
	var lit := Color("e8e2ff").lerp(_p.haze, 0.12)
	for y in 48:
		for x in 48:
			var dx := x - 23.5
			var dy := y - 23.5
			var r := sqrt(dx * dx + dy * dy)
			if r <= 8.0:
				var c := lit
				if dx - dy > 6.0:  # terminator shade
					c = lit.darkened(0.28)
				if (x == 21 and y == 21) or (x == 25 and y == 26) or (x == 20 and y == 26) or (x == 24 and y == 19):
					c = c.darkened(0.15)
				m.set_pixel(x, y, c)
			elif r < 24.0:
				var a := 0.0
				if r < 10.0:
					a = 0.22
				elif r < 14.0:
					a = 0.10
				else:
					a = 0.045 * (24.0 - r) / 10.0
				m.set_pixel(x, y, Color(halo, a))
	_moon_tex = ImageTexture.create_from_image(m)

	# Stars in a 1200 px wide repeating band.
	_stars.clear()
	var srng := RandomNumberGenerator.new()
	srng.seed = 99 + _dseed
	for i in 70:
		_stars.append(Vector3(srng.randi_range(0, 599) * 2, srng.randi_range(0, 80) * 2, srng.randf() * TAU))


func _init_rain() -> void:
	var n := RAIN_FAR + RAIN_NEAR
	_rain_pos.resize(n)
	_rain_end.resize(n)
	for i in n:
		_rain_pos[i] = Vector2(_rng.randf_range(0, _vw + 120), _rng.randf_range(-40, 360))
		_rain_end[i] = _drop_end(i)


func _drop_end(i: int) -> float:
	if i < RAIN_FAR:
		return _rng.randf_range(180, 300)
	return _rng.randf_range(294, 352)


func _step_rain(delta: float) -> void:
	for i in _rain_pos.size():
		var v := Vector2(-50, 380) if i < RAIN_FAR else Vector2(-95, 640)
		var p := _rain_pos[i] + v * delta
		if p.y > _rain_end[i]:
			if i >= RAIN_FAR and _splashes.size() < 24:
				_splashes.append(Vector3(roundf(p.x / 2) * 2, roundf(p.y / 2) * 2, 0.0))
			p = Vector2(_rng.randf_range(0, _vw + 120), _rng.randf_range(-30, -4))
			_rain_end[i] = _drop_end(i)
		_rain_pos[i] = p
	var j := 0
	while j < _splashes.size():
		var s: Vector3 = _splashes[j]
		s.z += delta
		if s.z > 0.16:
			_splashes.remove_at(j)
		else:
			_splashes[j] = s
			j += 1


# ---------------------------------------------------------------- chunk management

func _ensure_chunks(prefetch: bool) -> void:
	var keep := {}
	for layer in 4:
		var f: float = FACTORS[layer]
		var a := (_cam * f) / U
		var b := (_cam * f + _vw) / U
		var i0 := floori(a / CHUNK)
		var i1 := floori(b / CHUNK)
		for i in range(i0, i1 + 1):
			var k := Vector2i(layer, i)
			keep[k] = true
			if not _chunks.has(k):
				_chunks[k] = _gen_chunk(layer, i)
		for k in [Vector2i(layer, i0 - 1), Vector2i(layer, i1 + 1)]:
			keep[k] = true
			if prefetch and not _chunks.has(k) and not _prefetch.has(k):
				_prefetch.append(k)
	for k in _chunks.keys():
		if not keep.has(k):
			_chunks.erase(k)
	if _layouts.size() > 96:
		_layouts.clear()


func _layout(layer: int, idx: int) -> Array:
	var key := Vector2i(layer, idx)
	if _layouts.has(key):
		return _layouts[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(_dseed, layer, idx))
	var hm: float = _p.hmult
	var arr := []
	var start := idx * CHUNK
	var end := start + CHUNK
	match layer:
		L_FAR:
			var x := start + rng.randi_range(0, 4)
			while x < end:
				var w := rng.randi_range(6, 18)
				var hgt := rng.randf_range(26, 84) * hm
				if rng.randf() < 0.07:
					w = rng.randi_range(12, 20)
					hgt = rng.randf_range(100, 124) * hm
				arr.append({"x": x, "w": w, "top": maxi(STREET - int(hgt), 8), "seed": rng.randi() & 0x3fffffff})
				x += maxi(int(w * rng.randf_range(0.55, 1.05)), 4)
		L_MID:
			var x := start + rng.randi_range(0, 10)
			while x < end:
				var w := rng.randi_range(14, 34)
				var hgt := rng.randf_range(48, 122) * hm
				arr.append({"x": x, "w": w, "top": maxi(STREET - int(hgt), 10), "seed": rng.randi() & 0x3fffffff})
				x += w + rng.randi_range(3, 16)
		L_BACK:
			var x := start
			while x < end:
				var w := rng.randi_range(30, 62)
				var gap := rng.randi_range(6, 12) if rng.randf() < 0.25 else 0  # side street
				if end - (x + w + gap) < 30:
					w = end - x
					gap = 0
				var hgt := rng.randf_range(30, 96) * minf(hm, 1.15)
				arr.append({"x": x, "w": w, "top": STREET - int(hgt), "seed": rng.randi() & 0x3fffffff})
				x += w + gap
		L_NEAR:
			var x := start + rng.randi_range(4, 30)
			while x < end:
				var r := rng.randf()
				var kind := "lamp"
				var w := 9
				if r < 0.24:
					kind = "lamp"; w = 9
				elif r < 0.38:
					kind = "vending"; w = 9
				elif r < 0.50:
					kind = "bin"; w = 5
				elif r < 0.60:
					kind = "bollards"; w = 13
				elif r < 0.70:
					kind = "crates"; w = 11
				elif r < 0.78:
					kind = "barrier"; w = 12
				elif r < 0.90:
					kind = "signpole"; w = 7
				else:
					kind = "hydrant"; w = 4
				arr.append({"x": x, "w": w, "kind": kind, "seed": rng.randi() & 0x3fffffff})
				x += w + rng.randi_range(22, 60)
	_layouts[key] = arr
	return arr


func _gen_chunk(layer: int, idx: int) -> Dictionary:
	var p := Painter.new(CHUNK, STREET, idx * CHUNK, 0)
	for j in [idx - 1, idx, idx + 1]:
		for b in _layout(layer, j):
			if b.x + b.w + 16 < p.ox or b.x - 16 >= p.ox + CHUNK:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = b.seed
			match layer:
				L_FAR:
					_far_bld(p, b, rng)
				L_MID:
					_mid_bld(p, b, rng)
				L_BACK:
					_back_bld(p, b, rng)
				L_NEAR:
					_prop(p, b, rng)
	var d := {"tex": ImageTexture.create_from_image(p.img), "blinks": p.blinks, "flicks": p.flicks, "refls": p.refls}
	if layer == L_NEAR:
		d["ground"] = _gen_ground(idx)
	return d


# ---------------------------------------------------------------- helpers

static func _hf(s: int, a: int, b: int) -> float:
	return float(hash(Vector3i(s, a, b)) & 0xffff) / 65536.0


func _neon(rng: RandomNumberGenerator) -> Color:
	var n: Array = _p.neon
	return n[rng.randi() % n.size()]


static func _tw(s: String, sc := 1) -> int:
	var n := 0
	for ch in s:
		n += 3 if ch == " " else 4
	return (n - 1) * sc


func _text(p: Painter, x: int, y: int, s: String, col: Color, sc := 1) -> void:
	var cx := x
	for ch in s:
		if ch == " ":
			cx += 3 * sc
			continue
		var g: String = FONT.get(ch, "")
		for r in 5:
			for c in 3:
				if g != "" and g[r * 3 + c] == "1":
					p.rect(cx + c * sc, y + r * sc, sc, sc, col)
		cx += 4 * sc


## Kanji-like 5x5 glyph built from a few random strokes.
func _glyph(p: Painter, x: int, y: int, rng: RandomNumberGenerator, col: Color) -> void:
	var bits := PackedByteArray()
	bits.resize(25)
	for s in rng.randi_range(3, 4):
		var t := rng.randi() % 7
		match t:
			0, 1:  # horizontal stroke
				var r: int = [0, 2, 4][rng.randi() % 3]
				var a := rng.randi_range(0, 1)
				var b := rng.randi_range(3, 4)
				for c in range(a, b + 1):
					bits[r * 5 + c] = 1
			2, 3:  # vertical stroke
				var c: int = [0, 2, 4][rng.randi() % 3]
				var a := rng.randi_range(0, 2)
				for r in range(a, 5):
					bits[r * 5 + c] = 1
			4:  # box
				for i in 5:
					bits[i] = 1
					bits[20 + i] = 1
					bits[i * 5] = 1
					bits[i * 5 + 4] = 1
			5:  # short hook
				var r := rng.randi_range(1, 3)
				bits[r * 5 + 1] = 1
				bits[r * 5 + 2] = 1
				bits[(r + 1) * 5 + 3] = 1
			6:
				bits[rng.randi_range(0, 24)] = 1
	for i in 25:
		if bits[i]:
			p.rect(x + i % 5, y + i / 5, 1, 1, col)


## Horizontal neon text sign: dark box, colored border, bright tube text, soft glow.
func _text_sign(p: Painter, x: int, y: int, s: String, col: Color, rng: RandomNumberGenerator, refl := true) -> void:
	var w := _tw(s) + 4
	var h := 9
	p.glow(x, y, w, h, col, 1.2)
	p.rect(x, y, w, h, Color(0.03, 0.02, 0.07))
	p.rect(x, y, w, 1, col.darkened(0.25))
	p.rect(x, y + h - 1, w, 1, col.darkened(0.25))
	p.rect(x, y, 1, h, col.darkened(0.25))
	p.rect(x + w - 1, y, 1, h, col.darkened(0.25))
	_text(p, x + 2, y + 2, s, col.lightened(0.3))
	if p.owns(x):
		if rng.randf() < 0.3:
			p.flicks.append([Rect2i(x, y, w, h), rng.randi() & 0xffff])
		if refl:
			p.refls.append([x + 1, w - 2, col])


## Vertical hanging banner with stacked glyphs.
func _banner(p: Painter, x: int, y: int, n: int, col: Color, rng: RandomNumberGenerator) -> void:
	var h := n * 6 + 1
	p.glow(x, y, 7, h, col, 1.0)
	var inverted := rng.randf() < 0.4
	var bg := col.darkened(0.15) if inverted else Color(0.03, 0.02, 0.07)
	var fg := Color(0.05, 0.02, 0.08) if inverted else col.lightened(0.25)
	p.rect(x, y, 7, h, bg)
	if not inverted:
		p.rect(x, y, 1, h, col.darkened(0.3))
		p.rect(x + 6, y, 1, h, col.darkened(0.3))
	for i in n:
		_glyph(p, x + 1, y + 1 + i * 6, rng, fg)
	if p.owns(x):
		if rng.randf() < 0.3:
			p.flicks.append([Rect2i(x, y, 7, h), rng.randi() & 0xffff])
		p.refls.append([x, 7, col])


# ---------------------------------------------------------------- layer painters

func _far_bld(p: Painter, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var x: int = b.x
	var w: int = b.w
	var top: int = b.top
	var c: Color = _p.far
	p.rect(x, top, w, STREET - top, c)
	var cx := x
	var cw := w
	var ctop := top
	var r := rng.randf()
	if r < 0.32 and w > 7:  # setback crown
		cw = maxi(int(w * rng.randf_range(0.4, 0.7)), 3)
		var ch := rng.randi_range(3, 10)
		cx = x + (w - cw) / 2
		p.rect(cx, top - ch, cw, ch, c)
		ctop = top - ch
		if rng.randf() < 0.5 and cw > 5:
			var c2 := maxi(cw - 4, 2)
			var h2 := rng.randi_range(2, 6)
			p.rect(cx + (cw - c2) / 2, ctop - h2, c2, h2, c)
			ctop -= h2
	elif r < 0.45:  # stepped pyramid top
		var steps := mini(w / 2, rng.randi_range(2, 5))
		for i in steps:
			p.rect(x + i + 1, top - i - 1, w - 2 * (i + 1), 1, c)
		ctop = top - steps
	if rng.randf() < 0.4:  # spire with beacon
		var sh := rng.randi_range(4, 16)
		var sx := cx + cw / 2
		p.rect(sx, ctop - sh, 1, sh, c)
		if p.owns(sx):
			p.blinks.append([Vector2i(sx, ctop - sh - 1), rng.randf() * 3.0, rng.randf_range(1.6, 3.2)])
	if rng.randf() < 0.14:  # thin neon edge strip
		var col := Color(_neon(rng), 0.45)
		p.rect(x if rng.randf() < 0.5 else x + w - 1, top, 1, STREET - top, col)
	# sparse windows (hash-based so clipping is deterministic)
	var wins: Array = _p.far_win
	var dens := rng.randf_range(0.04, 0.16)
	for wy in range(top + 2, STREET - 6, 3):
		var rowd := dens * (0.2 + 1.6 * _hf(b.seed, -1, wy))
		for wx in range(x + 1, x + w - 1, 2):
			if wx < p.ox or wx >= p.ox + p.w:
				continue
			var hv := _hf(b.seed, wx, wy)
			if hv < rowd:
				p.rect(wx, wy, 1, 1, wins[int(hv * 997) % wins.size()])


func _mid_bld(p: Painter, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var x: int = b.x
	var w: int = b.w
	var top: int = b.top
	var c: Color = _p.mid
	var rim: Color = _p.mid_rim
	var r := rng.randf()
	var bx := x
	var bw := w
	var btop := top
	# optional upper setback tier
	if r < 0.3 and w > 18:
		var tw := int(w * rng.randf_range(0.5, 0.75))
		var th := rng.randi_range(8, 22)
		bx = x + rng.randi_range(1, w - tw - 1)
		bw = tw
		p.rect(bx, top - th, bw, th, c)
		p.rect(bx, top - th, 1, th, rim)
		p.rect(bx, top - th, bw, 1, rim)
		btop = top - th
	p.rect(x, top, w, STREET - top, c)
	p.rect(x, top, 1, STREET - top, rim)  # rim light from the city glow
	p.rect(x, top, w, 1, rim)
	p.rect(x + w - 1, top, 1, STREET - top, c.darkened(0.3))
	# rooftop clutter
	var rr := rng.randf()
	if rr < 0.45:
		var n := rng.randi_range(1, 2)
		for i in n:
			var ax := bx + rng.randi_range(1, maxi(bw - 2, 1))
			var ah := rng.randi_range(5, 14)
			p.rect(ax, btop - ah, 1, ah, rim)
			if i == 0 or rng.randf() < 0.5:
				if p.owns(ax):
					p.blinks.append([Vector2i(ax, btop - ah - 1), rng.randf() * 3.0, rng.randf_range(1.2, 2.6)])
	elif rr < 0.7 and bw > 8:  # water tank
		var tx := bx + rng.randi_range(1, bw - 6)
		p.rect(tx, btop - 6, 5, 4, c.lightened(0.04))
		p.rect(tx, btop - 6, 5, 1, rim)
		p.rect(tx, btop - 2, 1, 2, c)
		p.rect(tx + 4, btop - 2, 1, 2, c)
	elif bw > 6:  # AC boxes
		var tx := bx + 1
		while tx < bx + bw - 4:
			p.rect(tx, btop - 2, 3, 2, rim.darkened(0.2))
			tx += rng.randi_range(4, 8)
	# window grid
	var style := rng.randi() % 4
	var ww: int = [1, 2, 1, 2][style]
	var wh: int = [1, 1, 2, 2][style]
	var sx: int = ww + [1, 1, 1, 2][style]
	var sy: int = wh + rng.randi_range(1, 2)
	var wins: Array = _p.win
	var wc: Color = wins[rng.randi() % wins.size()]
	var wc2: Color = wins[rng.randi() % wins.size()]
	var dens := rng.randf_range(0.08, 0.3)
	var off := c.lightened(0.045)
	var gx0 := x + 2
	var gx1 := x + w - 2 - ww
	for wy in range(top + 3, STREET - 2, sy):
		var rowd := dens * (0.15 + 1.7 * _hf(b.seed, -7, wy))
		for wx in range(gx0, gx1 + 1, sx):
			if wx + ww <= p.ox or wx >= p.ox + p.w:
				continue
			var hv := _hf(b.seed, wx, wy)
			if hv < rowd:
				var lc := (wc if hv < rowd * 0.8 else wc2).darkened(0.3 + 0.35 * _hf(b.seed, wy, wx))
				p.rect(wx, wy, ww, wh, lc)
			else:
				p.rect(wx, wy, ww, wh, off)
	# vertical neon strip
	if rng.randf() < 0.22:
		var col := _neon(rng)
		var sxp := x + 1 if rng.randf() < 0.5 else x + w - 2
		var y0 := top + rng.randi_range(0, 10)
		p.blend(sxp - 1, y0, 3, STREET - y0, Color(col, 0.12))
		p.rect(sxp, y0, 1, STREET - y0, Color(col, 0.7))
	# holographic billboard
	if w >= 16 and rng.randf() < 0.5:
		var col := _neon(rng)
		var big := w >= 24 and rng.randf() < 0.3
		var hw := (w + 8) if big else (w - 4)
		var hx := (x - 4) if big else (x + 2)
		var hh := rng.randi_range(10, 16) if big else rng.randi_range(8, 12)
		var hy := top + rng.randi_range(4, maxi(5, mini(30, STREET - top - hh - 30)))
		p.glow(hx, hy, hw, hh, col, 1.4)
		p.blend(hx, hy, hw, hh, Color(col.darkened(0.55), 0.85))
		for sl in range(hy, hy + hh, 2):  # scanlines
			p.blend(hx, sl, hw, 1, Color(col, 0.10))
		p.rect(hx, hy, hw, 1, Color(col, 0.9))
		p.rect(hx, hy + hh - 1, hw, 1, Color(col, 0.9))
		p.rect(hx, hy, 1, 3, col.lightened(0.3))
		p.rect(hx + hw - 1, hy + hh - 3, 1, 3, col.lightened(0.3))
		var fits := []
		for nm in CORP_NAMES + SLOGANS:
			if _tw(nm) + 4 <= hw:
				fits.append(nm)
		var sc := 2 if (hh >= 14 and rng.randf() < 0.6) else 1
		var label := ""
		if sc == 2:
			var fits2 := []
			for nm in SLOGANS + CORP_NAMES:
				if _tw(nm, 2) + 4 <= hw:
					fits2.append(nm)
			if fits2.is_empty():
				sc = 1
			else:
				label = fits2[int(_hf(_dseed, hx, 55) * fits2.size())]
		if sc == 1 and not fits.is_empty() and rng.randf() < 0.8:
			label = fits[int(_hf(_dseed, hx, 57) * fits.size())]
		var fg := col.lightened(0.35)
		if label != "":
			var tw := _tw(label, sc)
			_text(p, hx + (hw - tw) / 2, hy + (hh - 5 * sc) / 2, label, fg, sc)
		else:
			var n := maxi((hw - 2) / 6, 1)
			var gx := hx + (hw - (n * 6 - 1)) / 2
			for i in n:
				_glyph(p, gx + i * 6, hy + (hh - 5) / 2, rng, fg)
		if p.owns(hx) and rng.randf() < 0.45:
			p.flicks.append([Rect2i(hx, hy, hw, hh), rng.randi() & 0xffff])


func _back_bld(p: Painter, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var x: int = b.x
	var w: int = b.w
	var top: int = b.top
	var c: Color = _p.back
	var trim: Color = _p.trim
	p.rect(x, top, w, STREET - top, c)
	p.rect(x, top, 1, STREET - top, c.darkened(0.4))
	p.rect(x + 1, top, w - 1, 1, trim)
	p.rect(x + 2, top + 2, w - 3, 1, trim.darkened(0.35))
	# roof clutter
	var rx := x + rng.randi_range(2, 8)
	while rx < x + w - 6:
		var k := rng.randi() % 5
		if k == 0:
			p.rect(rx, top - 3, 5, 3, trim)
			p.rect(rx + 1, top - 2, 3, 1, c)
		elif k == 1:
			p.rect(rx, top - 7, 1, 7, trim)
			p.rect(rx - 1, top - 5, 3, 1, trim)
		elif k == 2:
			p.rect(rx, top - 2, 6, 2, trim.darkened(0.2))
			for i in range(0, 6, 2):
				p.rect(rx + i, top - 4, 1, 2, trim.darkened(0.2))
		rx += rng.randi_range(6, 14)
	# windows
	var style := rng.randi() % 3
	var ww: int = [2, 3, 2][style]
	var wh: int = [2, 2, 3][style]
	var sx: int = ww + rng.randi_range(2, 3)
	var sy: int = wh + rng.randi_range(2, 3)
	var wins: Array = _p.win
	var wc: Color = wins[rng.randi() % wins.size()]
	var dens := rng.randf_range(0.1, 0.3)
	var off := c.lightened(0.06)
	var sill := c.darkened(0.45)
	for wy in range(top + 5, GF_TOP - wh - 13, sy):
		var rowd := dens * (0.25 + 1.5 * _hf(b.seed, -3, wy))
		for wx in range(x + 3, x + w - 2 - ww, sx):
			if wx + ww <= p.ox or wx >= p.ox + p.w:
				continue
			var hv := _hf(b.seed, wx, wy)
			if hv < rowd:
				var lc := wc.darkened(0.35 + 0.3 * _hf(b.seed, wy, wx))
				p.rect(wx, wy, ww, wh, lc)
				if hv < rowd * 0.35:
					p.rect(wx, wy + 1, ww, 1, lc.darkened(0.5))  # blinds
			else:
				p.rect(wx, wy, ww, wh, off)
			p.rect(wx, wy + wh, ww, 1, sill)
	# fire escape
	if rng.randf() < 0.4 and w > 20:
		var fx := x + rng.randi_range(3, w - 17)
		var fy := top + 8
		var flip := false
		while fy < GF_TOP - 16:
			p.rect(fx, fy, 14, 1, trim)
			for i in range(0, 14, 3):
				p.rect(fx + i, fy - 2, 1, 2, trim.darkened(0.25))
			for k in 5:
				var stx := fx + 2 + k * 2 if not flip else fx + 11 - k * 2
				p.rect(stx, fy + 1 + k, 2, 1, trim.darkened(0.15))
			flip = not flip
			fy += 6
	# pipe
	if rng.randf() < 0.55:
		var px := x + rng.randi_range(1, w - 2)
		p.rect(px, top + 3, 1, GF_TOP - top - 3, trim.darkened(0.1))
		for yy in range(top + 6, GF_TOP, 9):
			p.rect(px - 1, yy, 3, 1, trim)
	# AC units hanging on the facade
	for i in rng.randi_range(0, 3):
		var ax := x + rng.randi_range(2, w - 6)
		var ay := rng.randi_range(top + 6, GF_TOP - 18)
		p.rect(ax, ay, 4, 3, trim)
		p.rect(ax + 1, ay + 1, 2, 1, c.darkened(0.3))
	# ground floor storefronts
	p.rect(x, GF_TOP - 1, w, 1, trim)
	p.rect(x, GF_TOP, w, STREET - GF_TOP, c.darkened(0.15))
	var n := 1 if w < 44 else 2
	var sw := (w - 2) / n
	for k in n:
		var s0 := x + 1 + k * sw
		var col := _neon(rng)
		if rng.randf() < 0.28:  # rolling shutter (closed shop)
			var shc: Color = trim.lerp(Color("3a3448"), 0.25)
			p.rect(s0 + 2, GF_TOP + 3, sw - 4, STREET - GF_TOP - 3, shc)
			for yy in range(GF_TOP + 4, STREET, 2):
				p.rect(s0 + 2, yy, sw - 4, 1, shc.darkened(0.3))
			p.rect(s0 + 2, GF_TOP + 3, sw - 4, 1, trim.lightened(0.1))
			for g in rng.randi_range(4, 10):  # graffiti specks
				var gc := Color(_neon(rng).darkened(0.45), 0.8)
				p.rect(s0 + 4 + rng.randi_range(0, sw - 10), GF_TOP + 9 + rng.randi_range(0, 6), rng.randi_range(1, 3), 1, gc)
		else:
			var winw := sw - 11
			var interior := col.darkened(0.78)
			p.rect(s0 + 2, GF_TOP + 4, winw, 14, interior)
			p.rect(s0 + 2, GF_TOP + 4, winw, 1, col.darkened(0.35))
			p.blend(s0 + 2, GF_TOP + 5, winw, 3, Color(col, 0.12))
			for sh in [GF_TOP + 10, GF_TOP + 14]:
				p.rect(s0 + 3, sh, winw - 2, 1, interior.darkened(0.5))
			p.rect(s0 + 2 + winw / 2, GF_TOP + 4, 1, 14, trim)
			p.rect(s0 + 1, GF_TOP + 18, winw + 2, 1, trim)
			# door
			var dx := s0 + sw - 8
			p.rect(dx, GF_TOP + 4, 6, STREET - GF_TOP - 4, c.darkened(0.55))
			p.rect(dx + 1, GF_TOP + 5, 4, 6, interior.lightened(0.05))
			if p.owns(s0 + 2):
				p.refls.append([s0 + 3, winw - 2, col.darkened(0.4)])
			if rng.randf() < 0.55:  # striped awning
				var ac := col.darkened(0.58)
				for ax in range(s0 + 1, s0 + sw - 1):
					var on := ((ax - s0) / 2) % 2 == 0
					p.rect(ax, GF_TOP, 1, 3, ac if on else ac.darkened(0.5))
				for ax in range(s0 + 1, s0 + sw - 1, 2):
					p.rect(ax, GF_TOP + 3, 1, 1, ac.darkened(0.3))
		# sign over the shop
		var fits := []
		for wd in SHOP_WORDS:
			if _tw(wd) + 4 <= sw - 2:
				fits.append(wd)
		var sr := rng.randf()
		if not fits.is_empty() and sr < 0.6:
			var wd: String = fits[int(_hf(_dseed, s0, 51) * fits.size())]
			var tw := _tw(wd) + 4
			var sxp := s0 + rng.randi_range(0, maxi(sw - 2 - tw, 0)) + 1
			var sgy := GF_TOP - 12
			if rng.randf() < 0.45:
				sgy -= rng.randi_range(4, 16)
			_text_sign(p, sxp, sgy, wd, col, rng)
		elif sr < 0.85:  # projecting blade sign
			var gl := rng.randi_range(2, 3)
			var bxp := s0 + (0 if rng.randf() < 0.5 else sw - 7)
			var by := GF_TOP - 3 - (gl * 6 + 1) - rng.randi_range(0, 8)
			p.rect(bxp + 2, by - 1, 3, 1, trim)
			_banner(p, bxp, by, gl, col, rng)
	# rooftop sign on scaffolding
	if w >= 30 and top > 40 and rng.randf() < 0.3:
		var pool := []
		for wd in CORP_NAMES + ["HOTEL", "MOTEL", "KARAOKE", "ARCADE", "CLINIC"]:
			if _tw(wd) + 4 <= w - 6:
				pool.append(wd)
		if not pool.is_empty():
			var wd: String = pool[int(_hf(_dseed, x, 53) * pool.size())]
			var sw2 := _tw(wd) + 4
			var rxp := x + rng.randi_range(3, w - 3 - sw2)
			var ry := top - 14
			for lx in range(rxp + 2, rxp + sw2 - 1, 6):
				p.rect(lx, ry + 9, 1, 5, trim)
			p.rect(rxp + 1, ry + 11, sw2 - 2, 1, trim)
			_text_sign(p, rxp, ry, wd, _neon(rng), rng, false)
	# hanging vertical banner near an edge
	if rng.randf() < 0.5:
		var col := _neon(rng)
		var gl := rng.randi_range(3, 6)
		var bh := gl * 6 + 1
		var maxy := GF_TOP - 16 - bh
		if maxy > top + 6:
			var by := rng.randi_range(top + 6, maxy)
			var bxp := (x + w - 5) if rng.randf() < 0.5 else (x - 2)
			p.rect(bxp + 3, by - 2, 3, 1, trim)
			_banner(p, bxp, by, gl, col, rng)


func _prop(p: Painter, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var x: int = b.x
	var c: Color = _p.near
	var hi: Color = _p.near_hi
	match b.kind:
		"lamp":
			var lc: Color = _p.lamp
			var px := x + 4
			var ly := rng.randi_range(70, 80)
			# light cone (soft, baked)
			for yy in range(ly + 2, STREET):
				var f := float(yy - ly) / float(STREET - ly)
				var half := int(2 + f * 11)
				p.blend(px - half, yy, half * 2 + 1, 1, Color(lc, 0.05 * (1.0 - f * 0.6)))
			p.rect(px, ly, 2, STREET - ly, c)
			p.rect(px, ly, 1, STREET - ly, hi)
			p.rect(px - 1, STREET - 3, 4, 3, c)
			p.rect(px - 1, ly + 18, 4, 1, hi)
			p.rect(px - 5, ly - 1, 7, 1, c)
			p.rect(px - 6, ly, 5, 2, c)
			p.glow(px - 6, ly + 1, 5, 1, lc, 1.8)
			p.rect(px - 5, ly + 2, 3, 1, lc)
			if p.owns(px):
				p.refls.append([px - 6, 5, lc])
		"vending":
			var col := _neon(rng)
			var y0 := STREET - 17
			p.glow(x, y0, 9, 17, col, 0.8)
			p.rect(x, y0, 9, 17, c)
			p.rect(x, y0, 9, 1, hi)
			p.rect(x + 1, y0 + 1, 7, 2, col)
			p.rect(x + 1, y0 + 4, 7, 7, col.darkened(0.6))
			for ry in range(y0 + 5, y0 + 11, 2):
				for rxx in range(x + 2, x + 8, 2):
					p.rect(rxx, ry, 1, 1, _neon(rng).darkened(0.1))
			p.rect(x + 2, y0 + 12, 5, 2, Color(0.02, 0.02, 0.04))
			p.rect(x + 6, y0 + 12, 1, 1, Color("ff3d3d"))
			if p.owns(x):
				p.refls.append([x + 1, 7, col])
		"bin":
			p.rect(x, STREET - 7, 5, 7, c)
			p.rect(x - 1, STREET - 8, 7, 1, hi)
			p.rect(x + 1, STREET - 5, 1, 4, hi.darkened(0.3))
		"bollards":
			for i in 3:
				var bx := x + i * 5
				p.rect(bx, STREET - 6, 2, 6, c)
				p.rect(bx, STREET - 6, 2, 1, hi)
				p.rect(bx, STREET - 4, 2, 1, Color("6a5a20"))
		"crates":
			p.rect(x, STREET - 6, 7, 6, c.lightened(0.05))
			p.rect(x, STREET - 6, 7, 1, hi)
			p.rect(x + 1, STREET - 4, 5, 1, c)
			p.rect(x + 3, STREET - 11, 6, 5, c.lightened(0.03))
			p.rect(x + 3, STREET - 11, 6, 1, hi)
			p.rect(x + 5, STREET - 10, 1, 4, c)
		"barrier":
			p.rect(x + 1, STREET - 5, 1, 5, c)
			p.rect(x + 10, STREET - 5, 1, 5, c)
			for i in 12:
				var on := (i / 2) % 2 == 0
				p.rect(x + i, STREET - 7, 1, 3, Color("5a4a1c") if on else Color("15121e"))
		"signpole":
			var sc := Color("1d5a3a") if rng.randf() < 0.5 else Color("1d3a6a")
			p.rect(x + 3, STREET - 32, 1, 32, hi)
			p.rect(x, STREET - 34, 7, 5, sc)
			p.rect(x, STREET - 34, 7, 1, sc.lightened(0.3))
			p.rect(x + 1, STREET - 32, 5, 1, sc.lightened(0.4))
		"hydrant":
			p.rect(x, STREET - 5, 4, 5, Color("4a1420"))
			p.rect(x + 1, STREET - 6, 2, 1, Color("5a1a28"))
			p.rect(x - 1, STREET - 4, 6, 1, Color("3a1018"))


func _gen_ground(idx: int) -> ImageTexture:
	var gh := ART_H - STREET
	var p := Painter.new(CHUNK, gh, idx * CHUNK, STREET)
	var ox := idx * CHUNK
	var side: Color = _p.side
	var curb: Color = _p.curb
	var asph: Color = _p.asphalt
	p.rect(ox, STREET, CHUNK, 6, side)
	p.rect(ox, STREET, CHUNK, 1, side.lightened(0.16))
	p.rect(ox, STREET + 6, CHUNK, 1, curb)
	p.rect(ox, STREET + 7, CHUNK, 1, curb.darkened(0.35))
	p.rect(ox, STREET + 8, CHUNK, ART_H - STREET - 8, asph)
	p.rect(ox, STREET + 8, CHUNK, 1, asph.darkened(0.5))
	for x in range(ox, ox + CHUNK):
		if x % 16 == 0:
			p.rect(x, STREET + 1, 1, 5, side.darkened(0.3))
		for y in range(STREET + 9, ART_H):
			var hv := _hf(_dseed, x, y)
			if hv < 0.05:
				p.rect(x, y, 1, 1, asph.lightened(0.06))
			elif hv > 0.985:
				p.rect(x, y, 1, 1, asph.darkened(0.4))
		if posmod(x, 48) < 16:
			p.rect(x, STREET + 20, 1, 1, Color("221e1a"))
	# light pools from lamps on the sidewalk
	for j in [idx - 1, idx, idx + 1]:
		for b in _layout(L_NEAR, j):
			if b.kind != "lamp":
				continue
			var cx: int = b.x + 4
			for row in 6:
				var half := 14 - absi(row - 2) * 2
				p.blend(cx - half, STREET + row, half * 2 + 1, 1, Color(_p.lamp, 0.09))
	return ImageTexture.create_from_image(p.img)


# ---------------------------------------------------------------- drawing

func _sx(layer: int, art_x: int) -> float:
	return roundf(art_x * U - _cam * FACTORS[layer]) + _cam


func _visible(layer: int) -> Array:
	var f: float = FACTORS[layer]
	var i0 := floori((_cam * f) / U / CHUNK)
	var i1 := floori((_cam * f + _vw) / U / CHUNK)
	var out := []
	for i in range(i0, i1 + 1):
		var k := Vector2i(layer, i)
		if not _chunks.has(k):
			_chunks[k] = _gen_chunk(layer, i)
		out.append([i, _chunks[k]])
	return out


func _fog(y0: float, y1: float, col: Color, a: float) -> void:
	draw_texture_rect(_ramp_tex, Rect2(_cam, y0, _vw, y1 - y0), false, Color(col, a))


func _flicker_off(seed: int) -> bool:
	var tt := _t * 0.6 + seed * 0.0137
	var win := floori(tt)
	if _hf(seed, win, 7) > 0.4:
		return false
	var local := tt - win
	var start := _hf(seed, win, 3) * 0.75
	if local < start or local > start + 0.15:
		return false
	return int(_t * 17.0 + seed) % 3 != 0


func _draw() -> void:
	if not _sky_tex:
		return
	var cam := _cam
	var vw := _vw
	var haze: Color = _p.haze
	draw_texture_rect(_sky_tex, Rect2(cam, 0, vw, 300), false)

	# stars
	for s in _stars:
		var sxp: float = fposmod(s.x - cam * 0.02, 1200.0)
		if sxp < vw:
			var a: float = 0.25 + 0.2 * sin(_t * 1.7 + s.z)
			draw_rect(Rect2(cam + floorf(sxp / 2) * 2, s.y, 2, 2), Color(0.8, 0.8, 1.0, a))

	# moon (fixed in screen space)
	draw_texture_rect(_moon_tex, Rect2(cam + roundf(vw * 0.76 / 2) * 2, 18, 96, 96), false)

	# thin haze strata
	draw_rect(Rect2(cam, 118, vw, 4), Color(haze, 0.18))
	draw_rect(Rect2(cam, 150, vw, 6), Color(haze, 0.14))

	# search beams from behind the far skyline
	var beam := Color(haze.lightened(0.55), 0.055)
	for k in 2:
		var ox := fposmod(300.0 + k * 820.0 - cam * 0.12, vw + 700.0) - 300.0
		var ang := -PI / 2 + sin(_t * 0.23 + k * 2.1) * 0.5
		var o := Vector2(cam + ox, 280)
		var d1 := Vector2.from_angle(ang - 0.045) * 420.0
		var d2 := Vector2.from_angle(ang + 0.045) * 420.0
		draw_colored_polygon(PackedVector2Array([o, o + d1, o + d2]), beam)

	_draw_layer(L_FAR)
	_draw_cars()
	_fog(140, 292, haze, 0.6)
	_draw_layer(L_MID)
	_fog(190, 292, haze, 0.38)
	_draw_layer(L_BACK)
	# slight dusk over the ground floors so units standing in front read clearly
	_fog(214, 292, Color(0.02, 0.01, 0.05), 0.3)
	_draw_street()
	_draw_layer(L_NEAR)
	_draw_rain()


func _draw_layer(layer: int) -> void:
	var size := Vector2(CHUNK * U, STREET * U)
	var f: float = FACTORS[layer]
	var shift := roundf(-_cam * f) + _cam
	for e in _visible(layer):
		var ch: Dictionary = e[1]
		draw_texture_rect(ch.tex, Rect2(Vector2(_sx(layer, e[0] * CHUNK), 0), size), false)
		for bl in ch.blinks:
			var ph: float = fposmod(_t + bl[1], bl[2]) / bl[2]
			if ph < 0.45:
				var pp: Vector2i = bl[0]
				var bp := Vector2(pp.x * U + shift, pp.y * U)
				var a: float = 1.0 - ph / 0.45
				draw_rect(Rect2(bp - Vector2(4, 4), Vector2(10, 10)), Color(1, 0.15, 0.2, 0.12 * a))
				draw_rect(Rect2(bp - Vector2(2, 2), Vector2(6, 6)), Color(1, 0.2, 0.25, 0.25 * a))
				draw_rect(Rect2(bp, Vector2(2, 2)), Color(1, 0.35, 0.35, 0.5 + 0.5 * a))
		for fl in ch.flicks:
			if _flicker_off(fl[1]):
				var r: Rect2i = fl[0]
				draw_rect(Rect2(r.position.x * U + shift, r.position.y * U, r.size.x * U, r.size.y * U), Color(0.02, 0.01, 0.05, 0.8))


func _draw_cars() -> void:
	for k in 3:
		var speed := 34.0 + k * 13.0
		var span := _vw + 80.0
		var dur := span / speed
		var cycle := maxf(9.0 + k * 7.0, dur + 3.0)
		var local := fposmod(_t + k * 5.3 + 2.0, cycle)
		if local > dur:
			continue
		var dir := 1.0 if k % 2 == 0 else -1.0
		var x := (-40.0 + local * speed) if dir > 0 else (_vw + 40.0 - local * speed)
		x = _cam + roundf(x / 2) * 2
		var y := roundf((76.0 + k * 30.0 + sin(_t * 1.1 + k) * 3.0) / 2) * 2
		var body := Color("1c1730")
		var glow: Color = (_p.neon as Array)[k % (_p.neon as Array).size()]
		var front := x + (12.0 if dir > 0 else 0.0)
		var back := x + (0.0 if dir > 0 else 12.0)
		draw_rect(Rect2(front - (0.0 if dir > 0 else 26.0), y, 26, 2), Color(1, 0.95, 0.8, 0.07))
		draw_rect(Rect2(x, y, 14, 4), body)
		draw_rect(Rect2(x + 4, y - 2, 6, 2), body)
		draw_rect(Rect2(x + 2, y + 4, 10, 2), Color(glow, 0.45))
		draw_rect(Rect2(front, y, 2, 2), Color(1, 0.95, 0.8))
		draw_rect(Rect2(back, y + 2, 2, 2), Color(1, 0.2, 0.25))


func _draw_street() -> void:
	var size := Vector2(CHUNK * U, (ART_H - STREET) * U)
	var near := _visible(L_NEAR)
	for e in near:
		draw_texture_rect(e[1].ground, Rect2(Vector2(_sx(L_NEAR, e[0] * CHUNK), STREET * U), size), false)
	# mirrored reflections of the street-level layer and props (axis at y = 298)
	var mod := Color(0.6, 0.65, 1.0, 0.34)
	draw_set_transform(Vector2(0, 596), 0.0, Vector2(1, -1))
	for layer in [L_BACK, L_NEAR]:
		var src := Rect2(0, 118, CHUNK, STREET - 118)
		for e in _visible(layer):
			var dst := Rect2(_sx(layer, e[0] * CHUNK), 236, CHUNK * U, (STREET - 118) * U)
			draw_texture_rect_region(e[1].tex, dst, src, mod if layer == L_BACK else Color(mod, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# neon streaks (elongated, shimmering reflections)
	for layer in [L_BACK, L_NEAR]:
		var f: float = FACTORS[layer]
		var shift := roundf(-_cam * f) + _cam
		for e in _visible(layer):
			for rf in e[1].refls:
				var col: Color = rf[2]
				var bx: float = rf[0] * U + shift
				var bw: float = rf[1] * U
				for k in 6:
					var y := 306.0 + k * 4.0
					var jit := roundf(sin(_t * 2.3 + k * 1.7 + rf[0] * 0.3) * 1.5) * 2.0
					var shrink := k * 2.0
					var a := 0.24 * (1.0 - k / 6.5)
					draw_rect(Rect2(bx + shrink + jit, y, maxf(bw - shrink * 2.0, 2.0), 2), Color(col, a))
	# wet streaks: darker broken lines break the mirror into a rippled surface
	var asph: Color = _p.asphalt
	for k in 9:
		var y := 308.0 + k * 4.0
		var off := fposmod(k * 53.0 - _cam + _t * (6.0 + k), 96.0)
		var x := _cam - off
		while x < _cam + _vw:
			draw_rect(Rect2(x, y, 60, 2), Color(asph, 0.35))
			x += 96.0
	# calm the bottom band (UI cards sit there)
	draw_texture_rect(_ramp_tex, Rect2(_cam, 318, _vw, 42), false, Color(asph, 0.8))


func _draw_rain() -> void:
	var far := PackedVector2Array()
	var near := PackedVector2Array()
	far.resize(RAIN_FAR * 2)
	near.resize(RAIN_NEAR * 2)
	var off := Vector2(_cam, 0)
	var df := Vector2(-50, 380).normalized() * 7.0
	var dn := Vector2(-95, 640).normalized() * 12.0
	for i in _rain_pos.size():
		var p := _rain_pos[i] + off
		if i < RAIN_FAR:
			far[i * 2] = p
			far[i * 2 + 1] = p - df
		else:
			var j := i - RAIN_FAR
			near[j * 2] = p
			near[j * 2 + 1] = p - dn
	draw_multiline(far, Color(0.55, 0.6, 0.9, 0.16), 1.0)
	draw_multiline(near, Color(0.7, 0.78, 1.0, 0.26), 2.0)
	for s in _splashes:
		var a: float = 0.4 * (1.0 - s.z / 0.16)
		var c := Color(0.75, 0.8, 1.0, a)
		var spread: float = 2.0 + floorf(s.z * 25.0) * 2.0
		draw_rect(Rect2(_cam + s.x - spread, s.y - 2, 2, 2), c)
		draw_rect(Rect2(_cam + s.x + spread, s.y - 2, 2, 2), c)
