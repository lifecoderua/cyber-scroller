extends HBoxContainer
## MARKET tab: soft offers and cyberdeck slot upgrades.

var hub: Control
var _grid: GridContainer
var _upgrades: VBoxContainer


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 6)
	var left := HubW.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var head := HubW.hbox(6)
	head.add_child(HubW.lbl("BLACK MARKET", 12, UITheme.MAGENTA))
	var sub := HubW.lbl("stock rotates after every job", 9, UITheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	left.add_child(head)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(HubW.scroll(_grid))

	var right := HubW.panel(UITheme.CYAN.darkened(0.4), HubW.PANEL_BG, 1, 7)
	right.custom_minimum_size.x = 178
	add_child(right)
	_upgrades = HubW.vbox(6)
	right.add_child(_upgrades)


func on_show() -> void:
	HubFx.stagger(_grid, 0.05)


func refresh() -> void:
	HubW.clear(_grid)
	if Game.market.is_empty():
		_grid.add_child(HubW.lbl("Sold out. New stock after the next job.", 11, UITheme.TEXT_DIM))
	for id in Game.market:
		_grid.add_child(_offer(id))

	HubW.clear(_upgrades)
	_upgrades.add_child(HubW.lbl("DECK UPGRADES", 12, UITheme.CYAN))
	_upgrades.add_child(_upgrade("active", "ACTIVE SLOT", Game.active_slots, UITheme.CYAN))
	_upgrades.add_child(_upgrade("passive", "DAEMON SLOT", Game.passive_slots, UITheme.PURPLE))
	_upgrades.add_child(HubW.spacer(true))
	_upgrades.add_child(HubW.lbl("SOFT OWNED  %d/%d" % [Game.owned_soft.size(), SoftDB.all_ids().size()], 9, UITheme.TEXT_DIM))


func _offer(id: String) -> Control:
	var d := SoftDB.get_def(id)
	var col: Color = d.get("color", UITheme.CYAN)
	var rarity: String = d.get("rarity", "common")
	var rc := HubW.rarity_color(rarity)
	var price := SoftDB.price(id)
	var afford := Game.eddies >= price
	var p := HubW.panel(rc.darkened(0.25), HubW.PANEL_BG, 1, 6)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := HubW.vbox(2)
	p.add_child(v)
	var top := HubW.hbox(4)
	top.add_child(HubW.clip(HubW.lbl(String(d.name), 12, col.lightened(0.15))))
	var tag := HubW.panel(rc.darkened(0.2), Color(rc.darkened(0.8), 0.9), 1, 2)
	tag.add_child(HubW.lbl(rarity.to_upper(), 8, rc))
	top.add_child(tag)
	v.add_child(top)
	var kind := "ACTIVE  " + HubW.soft_stats(id) if SoftDB.is_active(id) else "DAEMON  passive"
	var tgt: String = d.get("target", "")
	if tgt != "":
		kind += "  " + ("TARGET " + tgt.to_upper() if tgt != "none" else "INSTANT")
	v.add_child(HubW.clip(HubW.lbl(kind, 8, UITheme.TEXT_DIM)))
	var desc := HubW.wrap(HubW.lbl(String(d.desc), 10, UITheme.TEXT), 3)
	desc.custom_minimum_size.y = 26
	v.add_child(desc)
	var bottom := HubW.hbox(6)
	var pl := HubW.lbl(UITheme.format_eddies(price), 13, UITheme.YELLOW if afford else UITheme.RED)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(pl)
	bottom.add_child(HubW.spacer())
	var b := HubW.button("BUY", func(): pass, 12, UITheme.GREEN if afford else UITheme.TEXT_DIM, afford)
	b.custom_minimum_size = Vector2(64, 32)
	b.pressed.connect(func(): _buy(id, b))
	bottom.add_child(b)
	v.add_child(bottom)
	return p


func _buy(id: String, btn: Control) -> void:
	var d := SoftDB.get_def(id)
	if not Game.buy_soft(id):
		hub.deny_money(btn)
		return
	var slotted := Game.is_equipped(id)
	hub.screen_flash(d.get("color", UITheme.CYAN), 0.18, 0.3)
	hub.toast("Bought %s%s" % [d.name, " (slotted)" if slotted else " (in library)"], UITheme.GREEN)


func _upgrade(kind: String, title: String, current: int, col: Color) -> Control:
	var p := HubW.panel(col.darkened(0.35), Color(0.04, 0.04, 0.1, 0.9), 1, 6)
	var v := HubW.vbox(2)
	p.add_child(v)
	v.add_child(HubW.lbl(title, 10, col))
	var price := Game.slot_upgrade_price(kind)
	var row := HubW.hbox(6)
	if price < 0:
		row.add_child(HubW.lbl("%d slots" % current, 13, UITheme.TEXT))
		row.add_child(HubW.spacer())
		row.add_child(HubW.lbl("MAXED", 12, UITheme.GREEN))
		v.add_child(row)
		return p
	row.add_child(HubW.lbl("%d -> %d" % [current, current + 1], 13, UITheme.TEXT))
	row.add_child(HubW.spacer())
	var afford := Game.eddies >= price
	row.add_child(HubW.lbl(UITheme.format_eddies(price), 12, UITheme.YELLOW if afford else UITheme.RED))
	v.add_child(row)
	var b := HubW.button("UPGRADE", func(): pass, 11, col if afford else UITheme.TEXT_DIM, afford)
	b.pressed.connect(func():
		if not Game.buy_slot(kind):
			hub.deny_money(b)
			return
		hub.screen_flash(col, 0.2, 0.3)
		hub.toast("Deck upgraded: +1 %s" % title.to_lower(), col))
	v.add_child(b)
	return p
