class_name HubFx
extends RefCounted
## Small UI juice helpers for the hub: press bounce, error shake, color flash, pop-in.


## Squash on press, springy release. Works for any BaseButton.
static func juice(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	if c is BaseButton:
		var b := c as BaseButton
		b.button_down.connect(func(): _press(c, true))
		b.button_up.connect(func(): _press(c, false))


static func _press(c: Control, down: bool) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	_kill(c, "_fx_press")
	var t := c.create_tween()
	c.set_meta("_fx_press", t)
	if down:
		t.tween_property(c, "scale", Vector2(0.93, 0.93), 0.05)
	else:
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "scale", Vector2.ONE, 0.2)


## Horizontal shake + red flash: "nope".
static func shake(c: Control, strength := 4.0, color := UITheme.RED) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	flash(c, color)
	if c.has_meta("_fx_shaking"):
		return
	c.set_meta("_fx_shaking", true)
	var base_x := c.position.x
	var t := c.create_tween()
	for i in 6:
		var dir := 1.0 if i % 2 == 0 else -1.0
		t.tween_property(c, "position:x", base_x + dir * strength * (1.0 - i / 6.0), 0.035)
	t.tween_property(c, "position:x", base_x, 0.035)
	t.tween_callback(func(): c.remove_meta("_fx_shaking"))


## Tints the control and fades back to normal.
static func flash(c: Control, color: Color, time := 0.35) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	_kill(c, "_fx_flash")
	var t := c.create_tween()
	c.set_meta("_fx_flash", t)
	c.modulate = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
	t.tween_property(c, "modulate", Color.WHITE, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Fade + scale in, optionally delayed (staggered lists).
static func pop_in(c: Control, delay := 0.0, time := 0.18) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.94, 0.94)
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "modulate:a", 1.0, time).set_delay(delay)
	t.tween_property(c, "scale", Vector2.ONE, time + 0.08).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Staggered pop-in of every Control child of a container (deferred to after layout).
static func stagger(container: Node, step := 0.04) -> void:
	var i := 0
	for ch in container.get_children():
		if ch is Control and not ch.is_queued_for_deletion():
			(ch as Control).modulate.a = 0.0
			pop_in.call_deferred(ch, i * step)
			i += 1


static func _kill(c: Object, key: String) -> void:
	if c.has_meta(key):
		var old = c.get_meta(key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
