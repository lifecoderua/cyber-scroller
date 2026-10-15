extends VBoxContainer
## CONTRACTS tab: three job cards plus a squad / deck summary strip.

var hub: Control
var _cards: HBoxContainer
var _strip: PanelContainer


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 5)
	_cards = HubW.hbox(6)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_cards)
	_strip = HubW.panel(UITheme.CYAN.darkened(0.55), HubW.PANEL_BG, 1, 5)
	add_child(_strip)


func on_show() -> void:
	HubFx.stagger(_cards, 0.06)


func refresh() -> void:
	HubW.clear(_cards)
	if Game.contracts.is_empty():
		_cards.add_child(HubW.lbl("No jobs on the board. Check back later.", 12, UITheme.TEXT_DIM))
	for i in Game.contracts.size():
		_cards.add_child(_contract_card(i, Game.contracts[i]))
	_build_strip()


func _contract_card(i: int, c: Dictionary) -> Control:
	var threat := int(c.threat)
	var tc := HubW.threat_color(threat)
	var p := HubW.panel(tc.darkened(0.35), HubW.PANEL_BG, 1, 7)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := HubW.vbox(3)
	p.add_child(v)

	var top := HubW.hbox(4)
	top.add_child(HubW.lbl("JOB %02d" % (i + 1), 9, UITheme.TEXT_DIM))
	top.add_child(HubW.spacer())
	top.add_child(HubW.lbl(String(c.district).to_upper(), 9, UITheme.CYAN))
	v.add_child(top)

	var title := HubW.wrap(HubW.lbl(String(c.title), 12, UITheme.TEXT), 3)
	title.custom_minimum_size.y = 30
	v.add_child(title)

	var who := HubW.hbox(4)
	who.add_child(HubW.lbl(String(c.client), 10, UITheme.TEXT))
	who.add_child(HubW.lbl("vs", 9, UITheme.TEXT_DIM))
	who.add_child(HubW.clip(HubW.lbl(String(c.target), 10, UITheme.MAGENTA)))
	v.add_child(who)

	var th := HubW.hbox(5)
	th.add_child(HubW.lbl("THREAT", 9, UITheme.TEXT_DIM))
	th.add_child(HubPips.new(threat, 5, tc))
	th.add_child(HubW.lbl(HubW.THREAT_NAMES[threat - 1], 9, tc))
	v.add_child(th)

	var encs: Array = c.get("encounters", [])
	var enc := HubW.hbox(4)
	enc.add_child(HubW.lbl("%d fights +" % maxi(0, encs.size() - 1), 10, UITheme.TEXT))
	enc.add_child(HubW.lbl("BOSS", 10, UITheme.RED))
	v.add_child(enc)
	v.add_child(HubW.spacer(true))
	v.add_child(_intel_row(encs))
	var bottom := HubW.hbox(6)
	var pay := HubW.vbox(0)
	pay.add_child(HubW.lbl("PAYOUT", 8, UITheme.TEXT_DIM))
	pay.add_child(HubW.lbl(UITheme.format_eddies(int(c.reward)), 15, UITheme.YELLOW))
	bottom.add_child(pay)
	bottom.add_child(HubW.spacer())
	var go := HubW.button("LAUNCH", func(): pass, 13, tc, true)
	go.custom_minimum_size = Vector2(80, 32)
	go.size_flags_vertical = Control.SIZE_SHRINK_END
	go.pressed.connect(func(): hub.launch(i, go))
	bottom.add_child(go)
	if not Game.can_start_mission():
		go.disabled = true
		go.text = "NO SQUAD"
		go.tooltip_text = "Assign runners to your squad in CREW first"
	v.add_child(bottom)
	return p


## Lineup of enemy sprites expected on the job, boss last.
func _intel_row(encs: Array) -> Control:
	var seen := []
	var total := 0
	for g in encs:
		total += g.size()
		for k in g:
			if k != "cyberpsycho" and not k in seen:
				seen.append(k)
	seen.append("cyberpsycho")
	var row := HubW.hbox(-4)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var names := []
	for k in seen:
		var tr := HubW.portrait(k, 3, 2)
		tr.flip_h = true
		if k == "cyberpsycho":
			tr.modulate = Color(1.15, 0.8, 0.8)
		row.add_child(tr)
		names.append(UnitDB.ENEMIES[k].name)
	row.add_child(HubW.spacer())
	var cnt := HubW.vbox(0)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_END
	var l1 := HubW.lbl("INTEL", 8, UITheme.TEXT_DIM)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.add_child(l1)
	var l2 := HubW.lbl("~%d hostiles" % total, 9, UITheme.TEXT)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.add_child(l2)
	row.add_child(cnt)
	row.tooltip_text = "Expected: " + ", ".join(names)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _build_strip() -> void:
	HubW.clear(_strip)
	var h := HubW.hbox(8)
	_strip.add_child(h)
	var sq := Game.squad_runners()
	var sl := HubW.vbox(0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.add_child(HubW.lbl("SQUAD", 9, UITheme.CYAN))
	sl.add_child(HubW.lbl("%d/%d" % [sq.size(), Game.SQUAD_MAX], 12, UITheme.TEXT))
	h.add_child(sl)
	if sq.is_empty():
		var warn := HubW.lbl("No runners assigned!", 11, UITheme.RED)
		warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(warn)
		var b := HubW.button("GO TO CREW", func(): hub.select_tab(1), 11, UITheme.RED)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	for r in sq:
		var unit := HubW.hbox(3)
		unit.add_child(HubW.portrait(r.cls, int(r.seed), 2))
		var info := HubW.vbox(0)
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(HubW.lbl(HubW.short_name(r), 10, UITheme.TEXT))
		info.add_child(HubW.lbl("%s L%d" % [UnitDB.CLASSES[r.cls].name, int(r.level)], 9, HubW.class_color(r.cls)))
		info.add_child(HubW.lbl("HP %d" % int(UnitDB.runner_stats(r).hp), 9, UITheme.TEXT_DIM))
		unit.add_child(info)
		h.add_child(unit)
	h.add_child(HubW.spacer())

	var sep := ColorRect.new()
	sep.color = Color(UITheme.CYAN, 0.25)
	sep.custom_minimum_size = Vector2(1, 0)
	h.add_child(sep)

	var deck := HubW.vbox(3)
	deck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fs := Game.fixer_stats()
	var dh := HubW.hbox(6)
	dh.add_child(HubW.lbl("DECK", 9, UITheme.MAGENTA))
	dh.add_child(HubW.lbl("RAM %d  +%.2f/s" % [int(fs.max_ram), float(fs.ram_regen)], 9, UITheme.CYAN))
	deck.add_child(dh)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 3)
	chips.add_theme_constant_override("v_separation", 3)
	chips.custom_minimum_size.x = 210
	for id in Game.deck_active + Game.deck_passive:
		var d := SoftDB.get_def(id)
		var col: Color = d.get("color", UITheme.CYAN)
		var chip := HubW.panel(col.darkened(0.3), Color(col.darkened(0.8), 0.9), 1, 3)
		chip.add_child(HubW.lbl(String(d.name), 9, col.lightened(0.2)))
		chips.add_child(chip)
	if Game.deck_active.is_empty() and Game.deck_passive.is_empty():
		chips.add_child(HubW.lbl("Deck empty", 9, UITheme.RED))
	deck.add_child(chips)
	h.add_child(deck)
