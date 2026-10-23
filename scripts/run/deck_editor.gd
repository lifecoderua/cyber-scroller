extends PanelContainer
## Deck loadout (between fights): HACK slots (active, spend RAM in a fight) and DAEMON slots
## (passive, react to dice events), plus the spare-chip drawer. Tap a spare chip, then a slot
## of its kind (or a slot, then a chip). Port daemons go dark without their implant.

const FILTERS := [["ALL", ""], ["HACK", "hack"], ["DAEMON", "daemon"]]

var screen
var run: RunState
var _sel_spare := -1
var _sel_slot := ["", -1]       # [kind, index]
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
	tv.add_child(HubW.lbl("RAM %d start, +%d/turn, cap %d  ·  %d rerolls  ·  HEAT cap %d" % [
		int(ch.ram_start) + int(fx.get("start_ram", 0)), int(ch.ram_turn), int(ch.ram_cap) + int(fx.get("max_ram", 0)),
		int(ch.rerolls) + int(fx.get("rerolls", 0)), int(ch.heat_cap) + int(fx.get("heat_cap", 0))], 9, UITheme.TEXT_DIM))
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
	for k in ["hack", "daemon"]:
		var p := HubW.panel(Color(ChipDB.kind_color(k), 0.4), HubW.PANEL_BG, 1, 6)
		var v := HubW.vbox(4)
		p.add_child(v)
		var t := "HACKS  (active: tap in a fight, costs RAM and Heat)" if k == "hack" else "DAEMONS  (passive: react to dice events)"
		v.add_child(HubW.lbl(t, 9, ChipDB.kind_color(k)))
		var row := HubW.hbox(5)
		var list := run.slots_of(k)
		for i in list.size():
			var tile := ChipTile.new()
			tile.ref = list[i]
			tile.custom_minimum_size = Vector2(58, 50)
			tile.hint = "RAM %d" % ChipDB.cost(list[i]) if k == "hack" and list[i] != "" else ("DARK" if ChipDB.is_dark(list[i], ports) else "")
			tile.dim = ChipDB.is_dark(list[i], ports)
			tile.selected = _sel_slot == [k, i]
			tile.pressed.connect(func(_x): _on_slot(k, i))
			row.add_child(tile)
		v.add_child(row)
		for i in list.size():
			if list[i] != "":
				var l := HubW.wrap(HubW.lbl("%s: %s" % [ChipDB.display_name(list[i]), ChipDB.desc(list[i])], 8, UITheme.TEXT if not ChipDB.is_dark(list[i], ports) else UITheme.RED))
				v.add_child(l)
		_board.add_child(p)


func _build_info() -> void:
	HubW.clear(_info)
	var ref := ""
	var from_slot: bool = _sel_slot[1] >= 0
	if _sel_spare >= 0 and _sel_spare < run.spare.size():
		ref = run.spare[_sel_spare]
	elif from_slot:
		ref = run.slots_of(_sel_slot[0])[_sel_slot[1]]
	if ref == "":
		var txt := "Tap a spare chip, then a slot of its kind. Hacks are your active tools in a fight; daemons trigger by themselves."
		if from_slot:
			txt = "Empty slot. Tap a spare chip of this kind to slot it."
		_info.add_child(HubW.wrap(HubW.lbl(txt, 9, UITheme.TEXT_DIM)))
		return
	_info.add_child(RunW.chip_block(ref, 3))
	var row := HubW.hbox(4)
	if from_slot:
		var rm := HubW.button("REMOVE", _remove, 10, UITheme.MAGENTA)
		rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rm)
	else:
		var k := ChipDB.kind(ref)
		row.add_child(HubW.lbl("Now tap a %s slot." % k.to_upper(), 10, ChipDB.kind_color(k)))
	_info.add_child(row)


func _build_drawer() -> void:
	HubW.clear(_filter_row)
	for f in FILTERS:
		var on: bool = _filter == f[1]
		var col := ChipDB.kind_color(f[1]) if f[1] != "" else UITheme.CYAN
		var b := HubW.button(f[0], func():
			_filter = f[1]
			_build_drawer(), 8, col, on)
		b.custom_minimum_size = Vector2(44, 24)
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
	if _sel_slot[1] >= 0:
		_place(_sel_slot[0], _sel_slot[1], i)
		return
	_sel_spare = -1 if _sel_spare == i else i
	refresh()


func _on_slot(k: String, i: int) -> void:
	if _sel_spare >= 0:
		_place(k, i, _sel_spare)
		return
	_sel_slot = ["", -1] if _sel_slot == [k, i] else [k, i]
	refresh()


func _place(k: String, i: int, spare_i: int) -> void:
	var ref: String = run.spare[spare_i]
	if ChipDB.kind(ref) != k:
		screen.deny(null, "That's a %s: it goes in a %s slot." % [ChipDB.kind(ref).to_upper(), ChipDB.kind(ref).to_upper()])
		return
	if run.place_chip(i, spare_i):
		Audio.play("ui_click", 0.0, 1.3)
		_sel_spare = -1
		_sel_slot = ["", -1]
		Game.run_changed()
		refresh()


func _remove() -> void:
	if run.remove_chip(_sel_slot[0], _sel_slot[1]):
		_sel_slot = ["", -1]
		Game.run_changed()
		refresh()
