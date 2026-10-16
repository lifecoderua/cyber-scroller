extends SceneTree
## Dev tool: smoke-tests hub -> mission -> hub through main.tscn (headless OK).
## Backs up and restores user://save.json so the real save is untouched.
##   godot --headless --path . --script res://tools/sim_flow_check.gd

const SAVE := "user://save.json"


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var backup := FileAccess.get_file_as_string(SAVE) if FileAccess.file_exists(SAVE) else ""
	var game: Node = root.get_node("Game")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	print("hub loaded: ", main.get_child_count() > 0, " -> ", main.get_child(0).name if main.get_child_count() else "none")
	game.start_mission(0)
	await _frames(10)
	var m: Node = main.get_child(main.get_child_count() - 1)
	print("mission loaded: ", m.name, " encounters=", m.sim.total_encounters())
	# Run the sim quickly (bot-less) until the mission resolves.
	var sim: CombatSim = m.sim
	while sim.outcome == "" and sim.time < 1200.0:
		sim.step(0.25)
		if sim.time > 20.0 and sim.can_extract():
			sim.extract()
		await _frames(1)
	print("outcome: ", sim.outcome, " bag=", sim.bag, " kills=", sim.kills, " t=", int(sim.time))
	await create_timer(2.5).timeout
	print("end overlay shown: ", m.end_panel != null)
	m._on_continue()
	await _frames(10)
	print("back in hub: ", main.get_child(main.get_child_count() - 1).name, " last_result=", game.last_result.get("outcome", "?"))
	# Restore the real save.
	if backup != "":
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("flow check done")
	quit()
