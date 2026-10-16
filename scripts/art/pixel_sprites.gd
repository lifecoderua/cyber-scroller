class_name PixelSprites
extends RefCounted
## Procedural pixel art. Sprites are built from ASCII templates plus palettes and cached.
##
## Humanoids are 16x24 and face RIGHT (flip for enemies). Frames: [walk_a, walk_b, attack].
## Palette keys:
##   o outline, s skin, h hair/hood, v visor/eyes (glow), j jacket, J jacket shade,
##   p pants, b boots, a accent (neon), g gear/gun metal, w weapon glow

const W := 16
const H := 24

const HEAD := [
	"................",
	"......oooo......",
	".....ohhhho.....",
	"....ohhhhhho....",
	"....ohssvvvo....",
	"....osssssso....",
	".....ossssoo....",
	"......osso......",
]
const TORSO := [
	"....ojjjajjo....",
	"...ojjjjajjjo...",
	"..ojJjjjajjJjo..",
	"..ojJjjjajjJjo..",
	"..osJjjjjjjJso..",
	"..ooJjjjjjjJoo..",
	"...oappppppao...",
	"....oppppppo....",
]
const LEGS_A := [
	"....oppppppo....",
	"....oppo.oppo...",
	"...oppo...oppo..",
	"...oppo...oppo..",
	"...oppo....opo..",
	"..obbo.....obbo.",
	"..obbbo....obbbo",
	"..ooooo....ooooo",
]
const LEGS_B := [
	"....oppppppo....",
	"....opppoppo....",
	".....oppoppo....",
	".....oppoppo....",
	".....oppoppo....",
	".....obbobbo....",
	".....obbbobbbo..",
	".....oooooooooo.",
]

## Overlays: list of [row, col, string]; '.' is transparent, other chars are palette keys.
const OVERLAYS := {
	"rifle": [[11, 8, "gggggggg"], [12, 9, "gg.g"]],
	"pistol": [[11, 10, "gggg"], [12, 10, "g"]],
	"blades": [[9, 12, "...w"], [10, 12, "..w."], [11, 11, "aww."], [12, 11, "w..."]],
	"pipe": [[8, 13, "g"], [9, 13, "g"], [10, 12, "g"], [11, 12, "a"]],
	"backpack": [[8, 1, "gg"], [9, 0, "ogg"], [10, 0, "ogg"], [11, 0, "oga"], [12, 1, "gg"]],
	"medcross": [[9, 5, "a"], [10, 4, "aaa"], [11, 5, "a"]],
	"mohawk": [[0, 7, "aa"], [1, 7, "aa"]],
	"hood": [[2, 4, "h"], [3, 3, "h"], [4, 3, "h"], [5, 3, "h"], [6, 4, "hh"]],
	"pads": [[8, 1, "oJJ"], [9, 0, "oJJ"], [8, 12, "JJo"], [9, 13, "JJo"]],
	"bigun": [[10, 7, "ggggggggg"], [11, 7, "gggggggga"], [12, 9, "gg"]],
	"cables": [[7, 2, "w"], [8, 1, "w"], [9, 1, "w"], [10, 2, "w"]],
	"spikes": [[0, 5, "a.a.a"], [1, 4, "a"], [1, 11, "a"]],
}

const SKIN_TONES := [Color("f2c7a5"), Color("d9a07a"), Color("a86b4c"), Color("7a4a32"), Color("c8d0d8")]
const HAIR_COLORS := [Color("1b1b2a"), Color("ff3d81"), Color("2de2e6"), Color("f9c80e"), Color("e8e8f0"), Color("6a3dff")]

## Base palettes per unit kind. Missing "s"/"h" keys are filled from the vseed.
const KINDS := {
	# runners
	"solo": {"pal": {"j": "7a1f3d", "J": "4e1428", "p": "2a2a3d", "b": "15151f", "a": "ff3d81", "v": "ff3d81", "g": "8a8fa8", "w": "ff9fc4"}, "over": ["blades"]},
	"gunner": {"pal": {"j": "6b5a1e", "J": "463b12", "p": "2e3324", "b": "15151f", "a": "f9c80e", "v": "f9c80e", "g": "6d7285", "w": "ffe066"}, "over": ["rifle"]},
	"medtech": {"pal": {"j": "d8e2e8", "J": "9aa8b2", "p": "2a3a3d", "b": "15151f", "a": "4cff8f", "v": "4cff8f", "g": "6d7285", "w": "4cff8f"}, "over": ["medcross", "pistol"]},
	"techie": {"pal": {"j": "1e4f5c", "J": "123640", "p": "2a2a3d", "b": "15151f", "a": "2de2e6", "v": "2de2e6", "g": "8a8fa8", "w": "2de2e6"}, "over": ["backpack", "pistol"]},
	# enemies
	"ganger": {"pal": {"j": "2b2b2b", "J": "1a1a1a", "p": "3d2a5c", "b": "15151f", "a": "ff6a2a", "v": "ff6a2a", "g": "8a8fa8", "w": "ff6a2a", "h": "ff6a2a"}, "over": ["mohawk", "pipe"]},
	"gunman": {"pal": {"j": "3a3f52", "J": "262a38", "p": "1f2230", "b": "101018", "a": "ff2a2a", "v": "ff2a2a", "g": "6d7285", "w": "ff2a2a"}, "over": ["pistol"]},
	"heavy": {"pal": {"j": "4a5a3a", "J": "2f3a24", "p": "2a3020", "b": "101018", "a": "ff9f1c", "v": "ff9f1c", "g": "5a5f70", "w": "ff9f1c", "s": "7d8796"}, "over": ["pads", "bigun"]},
	"netrunner": {"pal": {"j": "3d1f5c", "J": "28143d", "p": "1f1430", "b": "101018", "a": "b388ff", "v": "b388ff", "g": "6d7285", "w": "b388ff", "h": "3d1f5c"}, "over": ["hood", "cables"]},
	"cyberpsycho": {"pal": {"j": "5c0f1a", "J": "3d0a12", "p": "2a1a1a", "b": "101018", "a": "ff2a2a", "v": "ff2a2a", "g": "a0a5b8", "w": "ff2a2a", "s": "b8c0cc", "h": "15151f"}, "over": ["spikes", "pads", "blades"]},
}

const DRONE := [
	"................",
	"..gggg....gggg..",
	"....oo....oo....",
	"....oooooooo....",
	"...ojjjjjjjjo...",
	"..ojjJvvvvJjjo..",
	"..ojjJvaavJjjo..",
	"...ojjjjjjjjo...",
	"....oggggggo....",
	".....o.aa.o.....",
	"................",
	"................",
]
const DRONE_PAL := {"j": "2f3446", "J": "1c2030", "g": "8a8fa8", "a": "ff2a2a", "v": "ff6a6a"}

static var _cache := {}


## Frames [walk_a, walk_b, attack] for a runner class or enemy kind.
static func frames(kind: String, vseed := 0) -> Array:
	var key := "%s_%d" % [kind, vseed]
	if _cache.has(key):
		return _cache[key]
	var out := []
	if kind == "drone":
		out = _drone_frames()
	else:
		var pal := _palette(kind, vseed)
		var over: Array = KINDS.get(kind, KINDS["gunman"]).over
		var a := _compose(LEGS_A, over, false)
		var b := _compose(LEGS_B, over, false)
		var atk := _compose(LEGS_B, over, true)
		out = [_texture(a, pal), _texture(b, pal), _texture(atk, pal)]
	_cache[key] = out
	return out


## A single texture usable as a portrait/icon.
static func portrait(kind: String, vseed := 0) -> Texture2D:
	return frames(kind, vseed)[0]


static func _palette(kind: String, vseed: int) -> Dictionary:
	var base: Dictionary = KINDS.get(kind, KINDS["gunman"]).pal
	var pal := {"o": Color("0b0b14")}
	for k in base:
		pal[k] = Color(base[k])
	if not pal.has("s"):
		pal["s"] = SKIN_TONES[vseed % SKIN_TONES.size()]
	if not pal.has("h"):
		pal["h"] = HAIR_COLORS[floori(vseed / 7.0) % HAIR_COLORS.size()]
	return pal


static func _compose(legs: Array, overlays: Array, attack: bool) -> Array:
	var rows: Array = []
	for r in HEAD + TORSO + legs:
		rows.append(r.rpad(W, ".").substr(0, W))
	for name in overlays:
		for o in OVERLAYS.get(name, []):
			var shift := 1 if attack and name in ["rifle", "pistol", "bigun", "blades", "pipe"] else 0
			rows = _stamp(rows, o[0], o[1] + shift, o[2])
	if attack:
		# Muzzle flash / swing spark at the weapon tip.
		rows = _stamp(rows, 10, 15, "w")
		rows = _stamp(rows, 11, 15, "w")
	return rows


static func _stamp(rows: Array, row: int, col: int, s: String) -> Array:
	if row < 0 or row >= rows.size():
		return rows
	var line: String = rows[row]
	for i in s.length():
		var c := col + i
		if c >= 0 and c < W and s[i] != ".":
			line = line.substr(0, c) + s[i] + line.substr(c + 1)
	rows[row] = line
	return rows


static func _texture(rows: Array, pal: Dictionary) -> ImageTexture:
	var img := Image.create_empty(W, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var line: String = rows[y]
		for x in mini(W, line.length()):
			var ch := line[x]
			if ch != "." and pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return ImageTexture.create_from_image(img)


static func _drone_frames() -> Array:
	var pal := {"o": Color("0b0b14")}
	for k in DRONE_PAL:
		pal[k] = Color(DRONE_PAL[k])
	var a := DRONE.duplicate()
	var b := DRONE.duplicate()
	b[1] = "...gg......gg..."  # rotor blur frame
	var atk := DRONE.duplicate()
	atk[9] = ".....o.aa.o.aa.."
	return [_texture(a, pal), _texture(b, pal), _texture(atk, pal)]


## 1x1 white texture, handy for tinted rects/particles.
static func white() -> Texture2D:
	if _cache.has("__white"):
		return _cache["__white"]
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var t := ImageTexture.create_from_image(img)
	_cache["__white"] = t
	return t
