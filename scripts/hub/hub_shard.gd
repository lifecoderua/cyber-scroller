class_name HubShard
extends Control
## Data Shard icon: a faceted pixel diamond (drawn, so it never depends on font glyphs).

const COLOR := Color("c77dff")

var color := COLOR


func _init(px := 10.0, c := COLOR) -> void:
	color = c
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw(self, size * 0.5, minf(size.x, size.y) * 0.5, color)


## Draws the diamond on any CanvasItem, centred at `c` with half-height `r`.
static func draw(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var w := r * 0.78
	var top := c + Vector2(0, -r)
	var right := c + Vector2(w, 0)
	var bottom := c + Vector2(0, r)
	var left := c + Vector2(-w, 0)
	ci.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), col.darkened(0.25))
	# Lit upper-left facet and a highlight edge.
	ci.draw_colored_polygon(PackedVector2Array([top, c, left]), col.lightened(0.35))
	ci.draw_colored_polygon(PackedVector2Array([top, right, c]), col)
	ci.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), col.lightened(0.5), 1.0)
