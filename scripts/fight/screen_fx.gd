extends Control
## Full-screen overlays. mode "tint": active-pause cyan tint + scanlines + vignette
## (behind HUD widgets). mode "front": hit-stop flash, flying eddie coins, and link lines
## from a deck thread in the HUD to the unit its payload hit (every automatic action is
## visible).

var mode := "tint"
var tint := 0.0         # 0..1 target-select tint
var pause_tint := 0.0   # 0..1 manual pause tint
var flash := 0.0
var flash_color := Color.WHITE
var coins: Array = []   # {from, mid, to, t, life, cb}
var links: Array = []   # {from, to, col, w, t, life}
var _t := 0.0
var _scan: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var img := Image.create_empty(1, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(0, 0, Color(0, 0, 0, 0.35))
	_scan = ImageTexture.create_from_image(img)


func add_coin(from: Vector2, to: Vector2, delay: float, on_arrive: Callable) -> void:
	var mid := from + Vector2(randf_range(-30, 30), randf_range(-50, -20))
	coins.append({"from": from, "mid": mid, "to": to, "t": -delay, "life": 0.7 + randf() * 0.2, "cb": on_arrive})


func link(from: Vector2, to: Vector2, col: Color, w := 1.5, life := 0.45) -> void:
	links.append({"from": from, "to": to, "col": col, "w": w, "t": 0.0, "life": life})


func _process(delta: float) -> void:
	_t += delta
	for l in links:
		l.t += delta
	links = links.filter(func(l): return l.t < l.life)
	flash = maxf(0.0, flash - delta * 4.0)
	for c in coins:
		c.t += delta
		if c.t >= c.life and c.cb.is_valid():
			c.cb.call()
			c.cb = Callable()
	coins = coins.filter(func(c): return c.t < c.life)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if mode == "tint":
		var a := maxf(tint, pause_tint * 0.6)
		if a <= 0.01:
			return
		var col := UITheme.CYAN if tint > 0.01 else UITheme.PURPLE
		draw_rect(r, Color(col.r * 0.2, col.g * 0.35, col.b * 0.45, 0.32 * a))
		draw_texture_rect(_scan, r, true, Color(1, 1, 1, a))
		var y := fmod(_t * 60.0, size.y + 40.0) - 20.0
		draw_rect(Rect2(0, y, size.x, 10), Color(col.r, col.g, col.b, 0.06 * a))
		for i in 6:
			draw_rect(r.grow(-6.0 * i - 3.0), Color(col.r, col.g, col.b, 0.06 * a), false, 6.0)
		return
	for l in links:
		var k: float = 1.0 - l.t / l.life
		var head: float = minf(1.0, l.t / (l.life * 0.35))
		var c: Color = l.col
		var a: Vector2 = l.from
		var b: Vector2 = a.lerp(l.to, head)
		var mid := a.lerp(b, 0.5) + Vector2(0, -18.0 * head)
		var pts := PackedVector2Array()
		for i in 9:
			var f := float(i) / 8.0
			pts.append(a.lerp(mid, f).lerp(mid.lerp(b, f), f))
		draw_polyline(pts, Color(c, 0.3 * k), l.w * 3.0)
		draw_polyline(pts, Color(c, k), l.w)
		draw_circle(b, 2.5 + l.w, Color(c, k))
	for c in coins:
		if c.t < 0.0:
			continue
		var k: float = c.t / c.life
		var p: Vector2 = c.from.lerp(c.mid, minf(1.0, k * 2.5)).lerp(c.to, k * k)
		var s := 3.0 + 1.0 * sin(_t * 20.0 + c.life * 10.0)
		draw_rect(Rect2(p - Vector2(s / 2, 2.5), Vector2(s, 5)), Color("8a6a00"))
		draw_rect(Rect2(p - Vector2(s / 2 - 0.5, 2), Vector2(maxf(1.0, s - 1), 4)), UITheme.YELLOW)
	if flash > 0.0:
		draw_rect(r, Color(flash_color.r, flash_color.g, flash_color.b, flash * 0.35))
