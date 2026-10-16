extends HBoxContainer
## CREW tab: squad slots, roster (assign / dismiss) and the hire pool.

var hub: Control
var _squad_label: Label
var _squad_row: HBoxContainer
var _roster_count: Label
var _roster: VBoxContainer
var _hire: VBoxContainer
var _reroll: Button
var _restagger_hire := false


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 6)

	var left := HubW.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	add_child(left)
	var top := HubW.hbox(6)
	_squad_label = HubW.lbl("SQUAD", 12, UITheme.CYAN)
	_squad_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_squad_label)
	_squad_row = HubW.hbox(4)
	top.add_child(_squad_row)
	top.add_child(HubW.spacer())
	_roster_count = HubW.lbl("", 9, UITheme.TEXT_DIM)
	_roster_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_roster_count)
	left.add_child(top)
	_roster = HubW.vbox(4)
	left.add_child(HubW.scroll(_roster))

	var right := HubW.panel(UITheme.MAGENTA.darkened(0.4), HubW.PANEL_BG, 1, 6)
	right.custom_minimum_size.x = 226
	add_child(right)
	var rv := HubW.vbox(4)
	right.add_child(rv)
	var rh := HubW.hbox(6)
	var title := HubW.vbox(0)
	title.add_child(HubW.lbl("HIRE POOL", 12, UITheme.MAGENTA))
	title.add_child(HubW.lbl("fresh faces after every job", 8, UITheme.TEXT_DIM))
	rh.add_child(title)
	rh.add_child(HubW.spacer())
	_reroll = HubW.button("REROLL %d €$" % Game.HIRE_REROLL_COST, _on_reroll, 10, UITheme.MAGENTA)
	rh.add_child(_reroll)
	rv.add_child(rh)
	_hire = HubW.vbox(4)
	rv.add_child(HubW.scroll(_hire))


func refresh() -> void:
	_build_squad()
	_build_roster()
	_build_hire()
	if _restagger_hire:
		_restagger_hire = false
		HubFx.stagger(_hire, 0.05)


func _build_squad() -> void:
	HubW.clear(_squad_row)
	var sq := Game.squad_runners()
	_squad_label.text = "SQUAD %d/%d" % [sq.size(), Game.squad_max()]
	_squad_label.add_theme_color_override("font_color", UITheme.RED if sq.is_empty() else UITheme.CYAN)
	_roster_count.text = "%d ON\nPAYROLL" % Game.roster.size()
	var card_w := 76.0 if Game.squad_max() <= 3 else 62.0  # Full Crew node: 4 slots
	for i in Game.squad_max():
		if i < sq.size():
			var r: Dictionary = sq[i]
			var col := HubW.class_color(r.cls)
			var card := HubCard.new(col, Color(col.darkened(0.8), 0.9), 1, 2)
			card.custom_minimum_size = Vector2(card_w, 32)
			card.tooltip_text = "Tap to remove from squad"
			var row := HubW.hbox(3)
			row.add_child(HubW.headshot(r.cls, int(r.seed), 2))
			var nm := HubW.clip(HubW.lbl(HubW.short_name(r), 10, UITheme.TEXT))
			nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(nm)
			card.content.add_child(row)
			card.seal()
			var id: String = r.id
			card.pressed.connect(func():
				Game.toggle_squad(id)
				hub.toast("%s benched" % HubW.short_name(r), UITheme.TEXT_DIM))
			_squad_row.add_child(card)
		else:
			var empty := HubW.panel(Color(UITheme.TEXT_DIM, 0.35), Color(0, 0, 0, 0.35), 1, 2)
			empty.custom_minimum_size = Vector2(card_w, 32)
			var l := HubW.lbl("EMPTY", 9, Color(UITheme.TEXT_DIM, 0.6))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.add_child(l)
			_squad_row.add_child(empty)


func _build_roster() -> void:
	HubW.clear(_roster)
	if Game.roster.is_empty():
		_roster.add_child(HubW.lbl("Nobody on the payroll. Hire someone ->", 11, UITheme.TEXT_DIM))
	for r in Game.roster:
		var row := _roster_row(r)
		_roster.add_child(row)
		if r.id == hub.flash_id:
			HubFx.pop_in.call_deferred(row, 0.0, 0.3)


func _roster_row(r: Dictionary) -> Control:
	var in_squad: bool = r.id in Game.squad
	var col := HubW.class_color(r.cls)
	var p := HubW.panel(col.darkened(0.2) if in_squad else Color(col, 0.25),
		Color(col.darkened(0.88), 0.94) if in_squad else HubW.PANEL_BG, 1, 5)
	var h := HubW.hbox(6)
	p.add_child(h)
	h.add_child(HubW.portrait(r.cls, int(r.seed), 2))

	var info := HubW.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HubW.hbox(5)
	name_row.add_child(HubW.clip(HubW.lbl(String(r.name), 12, UITheme.TEXT)))
	name_row.add_child(HubW.lbl(UnitDB.CLASSES[r.cls].name.to_upper(), 9, col))
	name_row.add_child(HubW.lbl("L%d" % int(r.level), 11, UITheme.YELLOW))
	info.add_child(name_row)
	var xp_row := HubW.hbox(4)
	xp_row.add_child(HubW.xp_bar(r, 80))
	var lvl := int(r.level)
	var xp_text := "MAX LEVEL" if lvl >= UnitDB.MAX_LEVEL else "%d/%d XP" % [int(r.xp), UnitDB.xp_to_next(lvl)]
	xp_row.add_child(HubW.lbl(xp_text, 8, UITheme.TEXT_DIM))
	info.add_child(xp_row)
	info.add_child(HubW.clip(HubW.lbl(HubW.runner_stats_text(r, Game.fixer_stats()), 9, UITheme.TEXT)))
	var cls: Dictionary = UnitDB.CLASSES[r.cls]
	var skill := HubW.clip(HubW.lbl("%s: %s" % [cls.skill_name, cls.skill_desc], 9, col.lerp(UITheme.TEXT, 0.35)))
	skill.mouse_filter = Control.MOUSE_FILTER_PASS
	skill.tooltip_text = "Innate skill, auto-cast every %ds" % int(cls.skill_cd)
	info.add_child(skill)
	info.add_child(_trait_label(r))
	h.add_child(info)

	var btns := HubW.vbox(4)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id: String = r.id
	var tog := HubW.button("IN SQUAD" if in_squad else "+ SQUAD", func(): pass, 11, col if in_squad else UITheme.CYAN, in_squad)
	tog.custom_minimum_size = Vector2(78, 32)
	tog.pressed.connect(func(): _toggle(id, tog))
	btns.add_child(tog)
	var dis := HubW.button("DISMISS", func(): _dismiss(r), 9, UITheme.RED)
	dis.custom_minimum_size = Vector2(78, 32)
	btns.add_child(dis)
	h.add_child(btns)
	return p


func _trait_label(r: Dictionary) -> Label:
	var t: String = r.get("trait", "")
	if t == "":
		return HubW.lbl("No trait", 9, Color(UITheme.TEXT_DIM, 0.6))
	var td: Dictionary = UnitDB.TRAITS[t]
	var l := HubW.clip(HubW.lbl("%s  %s" % [String(td.name).to_upper(), td.desc], 9, UITheme.YELLOW.lerp(UITheme.TEXT, 0.2)))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = "%s: %s" % [td.name, td.desc]
	return l


func _toggle(id: String, btn: Control) -> void:
	var was_in: bool = id in Game.squad
	if not Game.toggle_squad(id):
		hub.deny(btn, "Squad full (%d/%d). Bench someone first." % [Game.squad_max(), Game.squad_max()])
		HubFx.shake(_squad_row, 3.0)
		return
	var r := Game.get_runner(id)
	if was_in:
		hub.toast("%s benched" % HubW.short_name(r), UITheme.TEXT_DIM)
	else:
		hub.toast("%s joins the squad" % HubW.short_name(r), UITheme.CYAN)


func _dismiss(r: Dictionary) -> void:
	var id: String = r.id
	var nm: String = r.name
	hub.confirm("DISMISS RUNNER?", "%s walks out for good. Their levels and XP are lost." % nm, "DISMISS", func():
		Game.dismiss(id)
		hub.toast("%s is gone" % nm, UITheme.MAGENTA))


func _build_hire() -> void:
	HubW.clear(_hire)
	_reroll.modulate = Color(1, 0.6, 0.6) if Game.eddies < Game.HIRE_REROLL_COST else Color.WHITE
	if Game.hire_pool.is_empty():
		_hire.add_child(HubW.wrap(HubW.lbl("Everyone's hired. Reroll or finish a job for new candidates.", 10, UITheme.TEXT_DIM)))
	for i in Game.hire_pool.size():
		_hire.add_child(_hire_row(i, Game.hire_pool[i]))


func _hire_row(i: int, r: Dictionary) -> Control:
	var col := HubW.class_color(r.cls)
	var cost := Game.hire_cost(r)
	var afford := Game.eddies >= cost
	var p := HubW.panel(Color(col, 0.35), Color(0.05, 0.05, 0.11, 0.9), 1, 4)
	var h := HubW.hbox(5)
	p.add_child(h)
	h.add_child(HubW.portrait(r.cls, int(r.seed), 2))
	var info := HubW.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(HubW.clip(HubW.lbl(String(r.name), 10, UITheme.TEXT)))
	info.add_child(HubW.lbl("%s  L%d" % [UnitDB.CLASSES[r.cls].name.to_upper(), int(r.level)], 9, col))
	var s := Game.runner_stats(r)
	info.add_child(HubW.clip(HubW.lbl("HP %d  DMG %s" % [int(s.hp), HubW._num(snappedf(float(s.dmg), 0.1))], 9, UITheme.TEXT_DIM)))
	info.add_child(_trait_label(r))
	h.add_child(info)
	var buy := HubW.vbox(2)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var price := HubW.lbl(UITheme.format_eddies(cost), 11, UITheme.YELLOW if afford else UITheme.RED)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buy.add_child(price)
	var b := HubW.button("HIRE", func(): pass, 11, UITheme.GREEN, afford)
	b.custom_minimum_size = Vector2(58, 32)
	b.disabled = not afford
	b.tooltip_text = "" if afford else "Not enough eddies"
	b.pressed.connect(func(): _on_hire(i, r, b))
	buy.add_child(b)
	h.add_child(buy)
	return p


func _on_hire(i: int, r: Dictionary, btn: Control) -> void:
	var squad_had_room := Game.squad.size() < Game.squad_max()
	var nm := HubW.short_name(r)
	var id: String = r.id
	hub.flash_id = id
	if not Game.hire(i):
		hub.flash_id = ""
		hub.deny_money(btn)
		return
	hub.toast("%s hired%s" % [nm, " and added to squad" if squad_had_room else ""], UITheme.GREEN)


func _on_reroll() -> void:
	if not Game.reroll_hire_pool():
		hub.deny_money(_reroll)
		return
	_restagger_hire = true
	hub.toast("New candidates on the board", UITheme.MAGENTA)
