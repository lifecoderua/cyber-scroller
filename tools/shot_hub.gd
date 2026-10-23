extends SceneTree
## Dev tool: renders the hub and saves a screenshot. Run WITHOUT --headless.
## Usage: godot --path . --script res://tools/shot_hub.gd -- <out.png> [tab 0-2] [mode]
## Modes: "" (normal), "results" (won-run debrief), "lost" (traced debrief), "hint",
##   "tree_fresh" (7 shards, nothing bought), "tree" (partly bought tree, a node selected),
##   "tree_full" (everything bought), "stash" (a few stashed items).
## NOTE: this resets the save in user://save.json.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(360, 640)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/hub.png"
	var tab := int(args[1]) if args.size() > 1 else 0
	var mode: String = args[2] if args.size() > 2 else ""
	var game: Node = root.get_node("Game")
	game.new_game()
	game.runs_played = 0 if mode == "hint" else 3
	game.rep = 5
	game.refresh_contracts()
	if mode == "tree_fresh":
		game.shards = 7
	if mode == "tree":
		game.shards = 9
		for id in ["core", "n_ram", "n_ram", "n_regen", "n_hack", "c_dmg", "c_hp", "c_hp", "c_hp",
				"c_patch", "b_reward", "b_reward", "b_gigs", "i_xp"]:
			game.shards += game.node_cost(id)
			game.buy_node(id)
	if mode == "tree_full":
		for id in TreeDB.all_ids():
			game.tree_ranks[id] = TreeDB.max_rank(id)
		game.shards = 31
		game.refresh_contracts()
	if mode == "stash":
		game.stash = ["kerenzikov", "smart_rifle+", "nanoweave"]
	if mode == "results":
		game.last_result = {"outcome": "won", "title": "Steal a data shard from Arasaka", "threat": 2,
			"shards": 8, "rep": 2, "fights": 6, "kills": 41, "trace": 64, "extracted": ["kerenzikov"],
			"crew": ["Jax \"Razor\"", "Mira \"Volt\"", "Kai \"Static\""]}
	elif mode == "lost":
		game.last_result = {"outcome": "traced", "title": "Torch a Maelstrom chop shop", "threat": 3,
			"shards": 2, "rep": 0, "fights": 4, "kills": 22, "trace": 100, "extracted": [],
			"crew": ["Jax \"Razor\"", "Mira \"Volt\""]}
	var hub: Control = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.select_tab(tab)
	if mode == "tree" and tab == 1:
		await process_frame
		hub._views[1]._on_node("c_trauma")
	for i in (200 if mode in ["results", "lost"] else 100):
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
