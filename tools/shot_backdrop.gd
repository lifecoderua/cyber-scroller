extends SceneTree
## Dev tool: renders CityBackdrop at several camera positions (and districts) into PNGs,
## with placeholder units standing on the street to check readability, then runs a
## short scroll benchmark. Needs rendering (run WITHOUT --headless):
##   godot --path . --script res://tools/shot_backdrop.gd -- <out_prefix>
## Writes <out_prefix>_<district>_<camx>.png

var _out := "user://backdrop"
var _world: Node2D
var _bd: CityBackdrop
var _units: Node2D
var _wide := 640


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	_world = Node2D.new()
	root.add_child(_world)
	_bd = CityBackdrop.new()
	_world.add_child(_bd)
	_units = Node2D.new()
	_world.add_child(_units)

	var shots := [["Neon Row", 0.0], ["Neon Row", 1500.0], ["Neon Row", 6000.0],
		["Kabuki", 800.0], ["Watson Docks", 2400.0], ["Glen Spire", 3600.0]]
	for s in shots:
		_bd.set_district(s[0])
		await _shot(s[1], "%s_%s_%d.png" % [_out, (s[0] as String).replace(" ", "").to_lower(), int(s[1])])

	# Wide-phone view (e.g. 19.5:9 -> ~780 px wide).
	_wide = 780
	root.size = Vector2i(_wide, 360)
	_bd.set_district("Neon Row")
	await _shot(9000.0, "%s_wide_9000.png" % _out)
	_wide = 640
	root.size = Vector2i(640, 360)

	# Benchmark: scroll 3 px/frame for 600 frames.
	_bd.set_district("Neon Row")
	var t_update := 0
	var t0 := Time.get_ticks_usec()
	var max_frame := 0
	var draw_calls := 0
	for i in 600:
		var cam := 10000.0 + i * 3.0
		var a := Time.get_ticks_usec()
		_place(cam)
		t_update += Time.get_ticks_usec() - a
		var f0 := Time.get_ticks_usec()
		await process_frame
		max_frame = maxi(max_frame, Time.get_ticks_usec() - f0)
		draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var total := Time.get_ticks_usec() - t0
	print("bench: 600 frames, avg frame %.2f ms, max frame %.2f ms, avg update_view %.3f ms, max draw calls %d, chunks %d" % [
		total / 600000.0, max_frame / 1000.0, t_update / 600000.0, draw_calls, _bd._chunks.size()])
	for layer in 4:
		var tg := Time.get_ticks_usec()
		for i in 10:
			_bd._gen_chunk(layer, 900 + i)
		print("chunk gen layer %d: %.2f ms avg" % [layer, (Time.get_ticks_usec() - tg) / 10000.0])
	quit()


func _place(cam: float) -> void:
	_world.position.x = -cam
	_bd.update_view(cam, Vector2(_wide, 360))


func _shot(cam: float, path: String) -> void:
	_place(cam)
	for c in _units.get_children():
		c.queue_free()
	# placeholder 32x48 unit rects + real sprites standing at y = 292
	var cols := [Color("2de2e6"), Color("ff3d81"), Color("c8c8d8")]
	for i in 3:
		var r := ColorRect.new()
		r.color = cols[i]
		r.size = Vector2(32, 48)
		r.position = Vector2(cam + 60 + i * 50, 244)
		_units.add_child(r)
	var kinds := ["solo", "borg", "medtech", "ganger", "heavy"]
	for i in kinds.size():
		var sp := Sprite2D.new()
		sp.texture = PixelSprites.frames(kinds[i], i * 7)[0]
		sp.centered = false
		sp.scale = Vector2(2, 2)
		sp.position = Vector2(cam + 260 + i * 60, 244)
		sp.flip_h = i >= 3
		_units.add_child(sp)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
