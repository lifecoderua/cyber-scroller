extends PanelContainer
## Deck editor (between fights): the thread board on top with a live dry-run readout per
## thread, the spare-chip drawer below. Tap a chip, then a slot (or a slot, then a chip).
## Slot 1 of every thread takes a trigger (yellow); the rest run left to right.

const FILTERS := [["ALL", ""], ["TRG", "trigger"], ["SEL", "selector"], ["MOD", "modifier"], ["PAY", "payload"]]

var screen
var run: RunState
var _sel_spare := -1
var _sel_slot := Vector2i(-1, -1)
var _filter := ""
var _board: VBoxContainer
var _info: VBoxContainer
var _drawer: GridContainer
var _filter_row: HBoxContainer


func setup(s) -> void:
	screen = s
	run = s.run
	add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.02, 0.05, 0.98), UITheme.CYAN.darkened(0.3), 1, 0, 8))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := HubW.vbox(6)
	add_child(root)
	var head := HubW.hbox(6)
	var tv := HubW.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HubW.lbl("CYBERDECK  //  %s" % String(ChipDB.CHASSIS.name).to_upper(), 14, UITheme.CYAN))
	var fx := run.fixer
	var ch: Dictionary = ChipDB.CHASSIS
	tv.add_child(HubW.lbl("RAM %d  ·  regen %.1f/s  ·  HEAT cap %d  ·  %d threads" % [
		int(ch.max_ram + float(fx.get("max_ram", 0.0))), ch.ram_regen * (1.0 + float(fx.get("ram_regen_pct", 0.0))),
		int(ch.heat_cap + float(fx.get("heat_cap", 0.0))), run.threads.size()], 9, UITheme.TEXT_DIM))
	head.add_child(tv)
	var close := HubW.button("DONE", func(): screen.close_overlay(), 12, UITheme.CYAN, true)
	close.custom_minimum_size = Vector2(70, 36)
	head.add_child(close)
	root.add_child(head)

	var body := HubW.vbox(6)
	_board = HubW.vbox(6)
	body.add_child(_board)
	_info = HubW.vbox(4)
	var info_panel := HubW.panel(UITheme.CYAN.darkened(0.55), HubW.DEEP_BG, 1, 6)
	info_panel.custom_minimum_size.y = 76
	info_panel.add_child(_info)
	body.add_child(info_panel)
	var dh := HubW.hbox(4)
	dh.add_child(HubW.lbl("SPARE CHIPS", 10, UITheme.TEXT_DIM))
	dh.add_child(HubW.spacer())
	_filter_row = HubW.hbox(3)
	dh.add_child(_filter_row)
	body.add_child(dh)
	_drawer = GridContainer.new()
	_drawer.columns = 6
	_drawer.add_theme_constant_override("h_separation", 5)
	_drawer.add_theme_constant_override("v_separation", 5)
	body.add_child(_drawer)
	root.add_child(HubW.scroll(body))
	refresh()


func refresh() -> void:
	_build_board()
	_build_info()
	_build_drawer()


func _build_board() -> void:
	HubW.clear(_board)
	var ports := run.crew_ports()
	for t in run.threads.size():
		var chips: Array = run.threads[t]
		var p := HubW.panel(Color("2a2a48"), HubW.PANEL_BG, 1, 5)
		var v := HubW.vbox(3)
		p.add_child(v)
		var row := HubW.hbox(4)
		var lab := HubW.lbl("T%d" % (t + 1), 11, UITheme.TEXT)
		lab.custom_minimum_size.x = 20
		lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lab)
		for s in chips.size():
			var tile := ChipTile.new()
			tile.ref = chips[s]
			tile.custom_minimum_size = Vector2(52 if chips.size() <= 4 else 44, 50)
			tile.hint = "TRIGGER" if s == 0 else str(s + 1)
			tile.selected = _sel_slot == Vector2i(t, s)
			tile.pressed.connect(func(_x): _on_slot(t, s))
			row.add_child(tile)
		var st := ChipDB.thread_stats(chips, run.fixer)
		var cost := HubW.vbox(0)
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.add_child(HubW.lbl("%d RAM" % int(st.ram), 10, UITheme.CYAN))
		cost.add_child(HubW.lbl("%.1fs" % float(st.cycle), 9, UITheme.TEXT_DIM))
		row.add_child(cost)
		v.add_child(row)
		v.add_child(HubW.wrap(HubW.lbl(ChipDB.readout(chips, run.fixer), 9, UITheme.TEXT)))
		var warn := ChipDB.thread_warning(chips, ports)
		if warn != "":
			v.add_child(HubW.wrap(HubW.lbl("! " + warn, 9, UITheme.RED)))
		_board.add_child(p)


func _build_info() -> void:
	HubW.clear(_info)
	var ref := ""
	var from_slot := _sel_slot.x >= 0
	if _sel_spare >= 0 and _sel_spare < run.spare.size():
		ref = run.spare[_sel_spare]
	elif from_slot:
		ref = run.threads[_sel_slot.x][_sel_slot.y]
	if ref == "":
		var txt := "Tap a spare chip, then a slot. Slot 1 = trigger (when). Then selectors (who), modifiers (how, stack on the next payload) and payloads (what)."
		if from_slot:
			txt = "Empty slot. Tap a spare chip below to put it here."
		_info.add_child(HubW.wrap(HubW.lbl(txt, 9, UITheme.TEXT_DIM)))
		return
	_info.add_child(RunW.chip_block(ref, 3))
	var row := HubW.hbox(4)
	if from_slot:
		var rm := HubW.button("REMOVE", _remove, 10, UITheme.MAGENTA)
		rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rm)
		if _sel_slot.y > 0:
			var left := HubW.button("<", func(): _move(-1), 11, UITheme.TEXT_DIM)
			left.custom_minimum_size.x = 40
			row.add_child(left)
			var right := HubW.button(">", func(): _move(1), 11, UITheme.TEXT_DIM)
			right.custom_minimum_size.x = 40
			row.add_child(right)
	else:
		var k := ChipDB.kind(ref)
		row.add_child(HubW.lbl("Now tap a %s." % ("TRIGGER slot (1)" if k == "trigger" else "slot 2+"), 10, ChipDB.kind_color(k)))
	_info.add_child(row)


func _build_drawer() -> void:
	HubW.clear(_filter_row)
	for f in FILTERS:
		var on: bool = _filter == f[1]
		var col := ChipDB.kind_color(f[1]) if f[1] != "" else UITheme.CYAN
		var b := HubW.button(f[0], func():
			_filter = f[1]
			_build_drawer(), 8, col, on)
		b.custom_minimum_size = Vector2(34, 24)
		_filter_row.add_child(b)
	HubW.clear(_drawer)
	var shown := 0
	for i in run.spare.size():
		var ref: String = run.spare[i]
		if _filter != "" and ChipDB.kind(ref) != _filter:
			continue
		var tile := ChipTile.new()
		tile.ref = ref
		tile.custom_minimum_size = Vector2(50, 42)
		tile.selected = i == _sel_spare
		tile.pressed.connect(func(_x): _on_spare(i))
		_drawer.add_child(tile)
		shown += 1
	if shown == 0:
		_drawer.add_child(HubW.lbl("none", 9, UITheme.TEXT_DIM))


func _on_spare(i: int) -> void:
	if _sel_slot.x >= 0:
		_place(_sel_slot.x, _sel_slot.y, i)
		return
	_sel_spare = -1 if _sel_spare == i else i
	refresh()


func _on_slot(t: int, s: int) -> void:
	if _sel_spare >= 0:
		_place(t, s, _sel_spare)
		return
	_sel_slot = Vector2i(-1, -1) if _sel_slot == Vector2i(t, s) else Vector2i(t, s)
	refresh()


func _place(t: int, s: int, spare_i: int) -> void:
	var ref: String = run.spare[spare_i]
	var k := ChipDB.kind(ref)
	if s == 0 and k != "trigger":
		screen.deny(null, "Slot 1 takes a TRIGGER (yellow).")
		return
	if s > 0 and k == "trigger":
		screen.deny(null, "Triggers only go in slot 1.")
		return
	if run.place_chip(t, s, spare_i):
		Audio.play("ui_click", 0.0, 1.3)
		_sel_spare = -1
		_sel_slot = Vector2i(-1, -1)
		Game.run_changed()
		refresh()


func _remove() -> void:
	if run.remove_chip(_sel_slot.x, _sel_slot.y):
		_sel_slot = Vector2i(-1, -1)
		Game.run_changed()
		refresh()


func _move(dir: int) -> void:
	var t := _sel_slot.x
	var s := _sel_slot.y
	if run.swap_slots(t, s, s + dir):
		_sel_slot = Vector2i(t, s + dir)
		Game.run_changed()
		refresh()
