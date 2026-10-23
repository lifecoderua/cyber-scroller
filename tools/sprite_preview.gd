extends SceneTree
## Dev tool: renders every sprite frame into one PNG sheet (x4) for review.
## Usage: godot --headless --script res://tools/sprite_preview.gd -- <out.png>

func _init() -> void:
	var out := "user://sprite_preview.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var kinds := ["solo", "borg", "medtech", "techie", "sniper", "ganger", "rusher", "gunman", "shield", "esniper",
		"grenadier", "netrunner", "heavy", "turret", "turret_ally", "cyberpsycho", "drone"]
	var scale := 4
	var sheet := Image.create_empty(kinds.size() * 17 * scale, 3 * 25 * scale, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1a1a2e"))
	for i in kinds.size():
		var fr := PixelSprites.frames(kinds[i], i * 13)
		for f in fr.size():
			var img: Image = fr[f].get_image()
			img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * 17 * scale, f * 25 * scale))
	sheet.save_png(out)
	print("saved ", out)
	quit()
