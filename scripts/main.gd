extends Node
## Root scene: swaps between the hub (safehouse), the run (map and node screens) and a
## fight (mission scene), as Game requests.

const SCENES := {
	"hub": "res://scenes/hub.tscn",
	"run": "res://scenes/run.tscn",
	"fight": "res://scenes/mission.tscn",
}

var _current: Node


func _ready() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	Game.screen_requested.connect(_show)
	_show(Game.start_screen())


func _show(screen: String) -> void:
	if _current:
		_current.queue_free()
		_current = null
	var packed := load(SCENES.get(screen, SCENES.hub)) as PackedScene
	if packed == null:
		push_error("Missing scene: %s" % screen)
		return
	_current = packed.instantiate()
	add_child(_current)
