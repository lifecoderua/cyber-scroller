extends PanelContainer
## Mission debrief modal: glitchy outcome reveal, staggered rows, payout count-up.

const GLYPHS := "#$%&*+=?@01<>/\\|_"
const OUTCOMES := {
	"success": ["SUCCESS", Color("4cff8f"), "Contract fulfilled. Client paid in full."],
	"extracted": ["EXTRACTED", Color("f9c80e"), "Pulled out with the bag. No contract pay."],
	"wiped": ["FLATLINED", Color("ff2a2a"), "Squad lost. The bag went down with them."],
}

var hub: Control
var overlay: Control
var res: Dictionary
var _word := ""
var _color := Color.WHITE
var _title: Label
var _total: Label
var _total_value := 0
var _rows: Array[Control] = []
var _continue: Button


func setup(h: Control, r: Dictionary) -> void:
	hub = h
	res = r
	var info: Array = OUTCOMES.get(String(r.get("outcome", "wiped")), OUTCOMES.wiped)
	_word = info[0]
	_color = info[1]
	add_theme_stylebox_override("panel", UITheme.box(Color(0.025, 0.025, 0.07, 0.97), _color, 2, 2, 12))
	custom_minimum_size.x = 330

	var v := HubW.vbox(3)
	add_child(v)
	var head := HubW.lbl("// JOB REPORT  THREAT %d" % int(r.get("threat", 1)), 9, UITheme.TEXT_DIM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var job := HubW.wrap(HubW.lbl(String(r.get("title", "")), 10, UITheme.TEXT_DIM), 2)
	job.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(job)
	_title = HubW.lbl(_word, 30, _color)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 4)
	v.add_child(_title)
	var sub := HubW.lbl(info[2], 10, _color.lerp(UITheme.TEXT, 0.45))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HubW.line(Color(_color, 0.35)))

	var wiped := String(r.get("outcome", "")) == "wiped"
	var bag := int(r.get("bag", 0))
	var reward := int(r.get("reward", 0))
	_total_value = bag + reward
	_row(v, "BAG", "lost" if wiped else "+" + UITheme.format_eddies(bag), UITheme.RED if wiped else UITheme.YELLOW)
	if reward > 0:
		_row(v, "CONTRACT", "+" + UITheme.format_eddies(reward), UITheme.YELLOW)
	if int(r.get("rep", 0)) > 0:
		_row(v, "REP", "+%d" % int(r.rep), UITheme.PURPLE)
	var dur := float(r.get("duration", 0.0))
	_row(v, "KILLS / TIME", "%d  /  %d:%02d" % [int(r.get("kills", 0)), int(dur) / 60, int(dur) % 60], UITheme.TEXT)
	var drop := String(r.get("soft_drop", ""))
	if drop != "":
		var d := SoftDB.get_def(drop)
		_row(v, "SOFT DROP", String(d.get("name", drop)), d.get("color", UITheme.CYAN))
	var ups: Array = r.get("level_ups", [])
	if not ups.is_empty():
		_row(v, "LEVEL UP", ", ".join(ups), UITheme.CYAN)
	var dead: Array = r.get("flatlined", [])
	if not dead.is_empty():
		_row(v, "FLATLINED", ", ".join(dead), UITheme.RED)

	v.add_child(HubW.line(Color(_color, 0.35)))
	var tot := HubW.hbox(6)
	tot.add_child(HubW.lbl("TOTAL", 11, UITheme.TEXT_DIM))
	tot.add_child(HubW.spacer())
	_total = HubW.lbl(UITheme.format_eddies(0), 18, UITheme.YELLOW if _total_value > 0 else UITheme.TEXT_DIM)
	tot.add_child(_total)
	v.add_child(tot)
	_continue = HubW.button("CONTINUE", _close, 13, _color, true)
	v.add_child(_continue)


func _row(v: VBoxContainer, key: String, value: String, color: Color) -> void:
	var row := HubW.hbox(8)
	var k := HubW.lbl(key, 9, UITheme.TEXT_DIM)
	k.custom_minimum_size.x = 84
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	var val := HubW.wrap(HubW.lbl(value, 11, color), 3)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	v.add_child(row)
	_rows.append(row)


func play() -> void:
	for r in _rows:
		r.modulate.a = 0.0
	_continue.modulate.a = 0.0
	var wiped := _word == "FLATLINED"
	hub.screen_flash(_color, 0.5 if wiped else 0.3, 0.5)
	var t := create_tween().set_parallel(true)
	t.tween_method(_reveal, 0.0, 1.0, 0.35)
	for i in _rows.size():
		t.tween_property(_rows[i], "modulate:a", 1.0, 0.12).set_delay(0.2 + i * 0.07)
	var count_start := 0.25 + _rows.size() * 0.07
	t.tween_method(func(x: float): _total.text = UITheme.format_eddies(int(round(x))), 0.0, float(_total_value), 0.45) \
		.set_delay(count_start).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_continue, "modulate:a", 1.0, 0.15).set_delay(count_start)
	if wiped:
		get_tree().create_timer(0.05).timeout.connect(func():
			if is_inside_tree():
				HubFx.shake(self, 7.0))


## Glitchy decode of the outcome word; p goes 0..1.
func _reveal(p: float) -> void:
	var n := _word.length()
	var shown := int(p * n)
	var chars := []
	for i in n:
		chars.append(_word[i] if i < shown else GLYPHS[randi() % GLYPHS.length()])
	_title.text = "".join(chars)


func _close() -> void:
	hub.close_modal(overlay)
	hub.results_closed()
