extends SceneTree
## Dev tool: renders the hub and saves a screenshot. Run WITHOUT --headless.
## Usage: godot --path . --script res://tools/shot_hub.gd -- <out.png> [tab 0-4] [mode]
## Modes: "" (normal), "rich" (more money/crew/soft), "results", "wiped", "hint", "empty", "fx",
##   "tree_fresh" (7 shards, nothing bought), "tree" (partly bought tree, a node selected),
##   "tree_full" (everything bought, 4-runner squad), "offline" (side-gig payout popup).
## NOTE: this resets the save in user://save.json.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/hub.png"
	var tab := int(args[1]) if args.size() > 1 else 0
	var mode: String = args[2] if args.size() > 2 else ""
	var game: Node = root.get_node("Game")
	game.new_game()
	game.missions_run = 0 if mode == "hint" else 3
	if mode in ["rich", "results", "wiped"]:
		game.eddies = 1450
		game.rep = 7
		game.owned_soft.append_array(["contagion", "firewall", "biomonitor", "targeting_uplink"])
		game.hire(0)
		game.refresh_contracts()
		game.refresh_market()
		game.roster[0].level = 3
		game.roster[0].xp = 70
	if mode == "empty":
		game.squad = []
	if mode == "tree_fresh":
		game.shards = 7
	if mode in ["tree", "offline"]:
		game.shards = 9
		game.rep = 5
		for id in ["core", "n_ram", "n_ram", "n_regen", "n_hack", "c_dmg", "c_hp", "c_hp", "c_hp",
				"c_patch", "b_reward", "b_reward", "b_gigs", "i_xp"]:
			game.shards += game.node_cost(id)
			game.buy_node(id)
	if mode == "tree_full":
		game.eddies = 2400
		game.rep = 20
		for id in TreeDB.all_ids():
			game.tree_ranks[id] = TreeDB.max_rank(id)
		game.shards = 31
		game.hire(0)
		game.hire(0)
		game.refresh_contracts()
		game.refresh_hire_pool()
	if mode == "offline":
		game.offline_pending = 386
		game.offline_seconds = 3 * 3600 + 13 * 60
	if mode == "results":
		game.last_result = {
			"outcome": "success", "title": "Steal a data shard from Arasaka", "threat": 2,
			"bag": 184, "reward": 262, "rep": 2, "soft_drop": "smart_link",
			"flatlined": [], "level_ups": ["Jax \"Razor\" -> L2"], "kills": 23, "duration": 287.0,
			"shards": 8,
		}
	elif mode == "wiped":
		game.last_result = {
			"outcome": "wiped", "title": "Torch a Maelstrom chop shop", "threat": 3,
			"bag": 0, "reward": 0, "rep": 0, "soft_drop": "",
			"flatlined": ["Jax \"Razor\"", "Mira \"Volt\""], "level_ups": [], "kills": 11, "duration": 143.0,
		}
	var hub: Control = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	hub.select_tab(tab)
	if mode == "tree" and tab == 4:
		await process_frame
		hub._views[4]._on_node("c_trauma")
	for i in (240 if mode in ["results", "offline"] else 110):
		await process_frame
		if mode == "fx" and i == 80:
			hub.toast("Squad full (3/3). Bench someone first.", UITheme.RED)
			hub.toast("Bought Contagion (slotted)", UITheme.GREEN)
			game.eddies -= 150
			game.state_changed.emit()
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
