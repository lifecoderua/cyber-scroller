extends HBoxContainer
## DECK tab: cyberdeck with active / daemon sockets, fixer stats, and the soft library.

var hub: Control
var _deck_title: Label
var _ram_cells: HubPips
var _ram_label: Label
var _active_label: Label
var _active_grid: GridContainer
var _passive_label: Label
var _passive_grid: GridContainer
var _stats: HFlowContainer
var _lib: VBoxContainer


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 6)

	var deck := HubW.panel(UITheme.MAGENTA.darkened(0.15), Color(0.04, 0.03, 0.09, 0.95), 2, 8)
	deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck.size_flags_stretch_ratio = 1.45
	add_child(deck)
	var dv := HubW.vbox(4)
	deck.add_child(dv)

	var head := HubW.hbox(6)
	_deck_title = HubW.lbl("CYBERDECK", 12, UITheme.MAGENTA)
	head.add_child(_deck_title)
	head.add_child(HubW.spacer())
	head.add_child(_vc(HubW.lbl("RAM", 9, UITheme.TEXT_DIM)))
	_ram_cells = HubPips.new(10, 16, UITheme.CYAN, HubPips.Mode.CELL)
	head.add_child(_ram_cells)
	_ram_label = _vc(HubW.lbl("", 10, UITheme.CYAN))
	head.add_child(_ram_label)
	dv.add_child(head)
	dv.add_child(HubW.line(Color(UITheme.MAGENTA, 0.3)))

	_active_label = HubW.lbl("", 9, UITheme.CYAN)
	dv.add_child(_active_label)
	_active_grid = GridContainer.new()
	_active_grid.columns = 3
	_active_grid.add_theme_constant_override("h_separation", 4)
	_active_grid.add_theme_constant_override("v_separation", 4)
	dv.add_child(_active_grid)
	_passive_label = HubW.lbl("", 9, UITheme.PURPLE)
	dv.add_child(_passive_label)
	_passive_grid = GridContainer.new()
	_passive_grid.columns = 4
	_passive_grid.add_theme_constant_override("h_separation", 4)
	_passive_grid.add_theme_constant_override("v_separation", 4)
	dv.add_child(_passive_grid)
	dv.add_child(HubW.spacer(true))
	dv.add_child(HubW.lbl("FIXER STATS", 9, UITheme.TEXT_DIM))
	_stats = HFlowContainer.new()
	_stats.add_theme_constant_override("h_separation", 4)
	_stats.add_theme_constant_override("v_separation", 4)
	dv.add_child(_stats)

	var right := HubW.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var rh := HubW.hbox(6)
	rh.add_child(HubW.lbl("SOFT LIBRARY", 12, UITheme.CYAN))
	rh.add_child(_vc(HubW.lbl("tap to slot / unslot", 9, UITheme.TEXT_DIM)))
	right.add_child(rh)
	_lib = HubW.vbox(3)
	right.add_child(HubW.scroll(_lib))


func _vc(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func refresh() -> void:
	var fs := Game.fixer_stats()
	var mk := 1 + (Game.active_slots - 4) + (Game.passive_slots - 2)
	_deck_title.text = "CYBERDECK MK%d" % mk
	var ram := int(fs.max_ram)
	_ram_cells.set_value(ram, maxi(16, ram), UITheme.CYAN)
	_ram_label.text = "%d  +%.2f/s" % [ram, float(fs.ram_regen)]
	_active_label.text = "ACTIVE SOFT  %d/%d" % [Game.deck_active.size(), Game.active_slots]
	_passive_label.text = "DAEMONS  %d/%d" % [Game.deck_passive.size(), Game.passive_slots]

	HubW.clear(_active_grid)
	for i in Game.active_slots:
		if i < Game.deck_active.size():
			_active_grid.add_child(_socket_card(Game.deck_active[i], true))
		else:
			_active_grid.add_child(_empty_socket(true))
	HubW.clear(_passive_grid)
	_passive_grid.columns = maxi(2, Game.passive_slots)
	for i in Game.passive_slots:
		if i < Game.deck_passive.size():
			_passive_grid.add_child(_socket_card(Game.deck_passive[i], false))
		else:
			_passive_grid.add_child(_empty_socket(false))
	HubW.clear(_stats)
	_stat_chip("MAX RAM", "%d" % ram, UITheme.CYAN)
	_stat_chip("REGEN", "%.2f/s" % float(fs.ram_regen), UITheme.CYAN)
	for b in _bonuses(fs):
		_stat_chip(b[0], b[1], UITheme.GREEN)

	HubW.clear(_lib)
	var owned := Game.owned_soft.duplicate()
	# Actives first, then daemons; equipped first within each group.
	owned.sort_custom(func(a, b):
		var ka := (0 if SoftDB.is_active(a) else 2) + (0 if Game.is_equipped(a) else 1)
		var kb := (0 if SoftDB.is_active(b) else 2) + (0 if Game.is_equipped(b) else 1)
		return ka < kb)
	for id in owned:
		_lib.add_child(_lib_row(id))


func _bonuses(fs: Dictionary) -> Array:
	var out := []
	if fs.dmg_pct > 0:
		out.append(["RUNNER DMG", "+%d%%" % int(fs.dmg_pct * 100)])
	if fs.hack_pct > 0:
		out.append(["HACK DMG", "+%d%%" % int(fs.hack_pct * 100)])
	if fs.regen > 0:
		out.append(["HP REGEN", "%.1f/s" % fs.regen])
	if fs.ram_on_kill > 0:
		out.append(["RAM/KILL", "+%d" % int(fs.ram_on_kill)])
	if fs.bounty_pct > 0:
		out.append(["BOUNTY", "+%d%%" % int(fs.bounty_pct * 100)])
	if fs.ice_sentry:
		out.append(["ICE SENTRY", "ON"])
	if fs.autopilot:
		out.append(["AUTOPILOT", "ON"])
	return out


func _stat_chip(key: String, value: String, col: Color) -> void:
	var p := HubW.panel(col.darkened(0.45), Color(col.darkened(0.85), 0.9), 1, 4)
	var h := HubW.hbox(4)
	h.add_child(HubW.lbl(key, 8, UITheme.TEXT_DIM))
	h.add_child(HubW.lbl(value, 10, col))
	p.add_child(h)
	_stats.add_child(p)


func _socket_card(id: String, active: bool) -> Control:
	var d := SoftDB.get_def(id)
	var col: Color = d.get("color", UITheme.CYAN)
	var card := HubCard.new(col, Color(col.darkened(0.86), 0.95), 1, 4)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(100, 58 if active else 34)
	card.tooltip_text = "Tap to unslot"
	card.content.add_child(HubW.clip(HubW.lbl(String(d.name), 10, col.lightened(0.25))))
	if active:
		card.content.add_child(HubW.lbl(HubW.soft_stats(id), 8, UITheme.TEXT))
		card.content.add_child(HubW.wrap(HubW.lbl(String(d.desc), 8, UITheme.TEXT_DIM), 2))
	else:
		card.content.add_child(HubW.clip(HubW.lbl(String(d.desc), 8, UITheme.TEXT_DIM)))
	card.seal()
	card.pressed.connect(func(): _toggle(id, card))
	if id == hub.flash_id:
		HubFx.pop_in.call_deferred(card, 0.0, 0.25)
	return card


func _empty_socket(active: bool) -> Control:
	var p := HubW.panel(Color(UITheme.TEXT_DIM, 0.3), Color(0, 0, 0, 0.45), 1, 2)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(100, 58 if active else 34)
	var l := HubW.lbl("[ EMPTY SOCKET ]" if active else "[ EMPTY ]", 8, Color(UITheme.TEXT_DIM, 0.55))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _lib_row(id: String) -> Control:
	var d := SoftDB.get_def(id)
	var col: Color = d.get("color", UITheme.CYAN)
	var on := Game.is_equipped(id)
	var card := HubCard.new(col if on else col.darkened(0.45),
		Color(col.darkened(0.8), 0.95) if on else HubW.PANEL_BG, 1, 4)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 36
	var top := HubW.hbox(4)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(3, 0)
	top.add_child(bar)
	var mid := HubW.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r1 := HubW.hbox(4)
	r1.add_child(HubW.clip(HubW.lbl(String(d.name), 10, col.lightened(0.2) if on else UITheme.TEXT)))
	r1.add_child(HubW.lbl(HubW.soft_stats(id) if SoftDB.is_active(id) else "DAEMON", 8, UITheme.TEXT_DIM))
	mid.add_child(r1)
	mid.add_child(HubW.clip(HubW.lbl(String(d.desc), 8, UITheme.TEXT_DIM)))
	top.add_child(mid)
	var state := HubW.lbl("SLOTTED" if on else "", 8, UITheme.GREEN)
	state.custom_minimum_size.x = 40
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(state)
	card.content.add_child(top)
	card.seal()
	card.pressed.connect(func(): _toggle(id, card))
	return card


func _toggle(id: String, from: Control) -> void:
	var was_on := Game.is_equipped(id)
	var nm: String = SoftDB.get_def(id).name
	if not was_on:
		hub.flash_id = id
	if not Game.toggle_equip(id):
		hub.flash_id = ""
		var active := SoftDB.is_active(id)
		hub.deny(from, "No free %s slot. Unslot one or buy an upgrade." % ("active" if active else "daemon"))
		HubFx.shake(_active_grid if active else _passive_grid, 3.0)
		return
	hub.toast(("Unslotted %s" if was_on else "Slotted %s") % nm, UITheme.TEXT_DIM if was_on else UITheme.CYAN)
