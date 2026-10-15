extends Node
## Root scene: swaps between the hub (safehouse) and a mission.

const HUB_SCENE := "res://scenes/hub.tscn"
const MISSION_SCENE := "res://scenes/mission.tscn"

var _current: Node


func _ready() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	Game.mission_requested.connect(func(): _show(MISSION_SCENE))
	Game.mission_finished.connect(func(): _show(HUB_SCENE))
	_show(HUB_SCENE)


func _show(path: String) -> void:
	if _current:
		_current.queue_free()
		_current = null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Missing scene: %s" % path)
		return
	_current = packed.instantiate()
	add_child(_current)
