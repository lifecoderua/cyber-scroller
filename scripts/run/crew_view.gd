extends PanelContainer
## Crew sheet (between fights): one merc per page. Stats, trait, signature, gear slots,
## chrome load (psychosis risk above the cap) and PORTS: which deck threads hook this
## merc's implants. Chrome is an interface, both ways.

var screen
var run: RunState
var _i := 0
var _body: VBoxContainer
var _pager: Label


func setup(s) -> void:
	screen = s
	run = s.run
	add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.02, 0.05, 0.98), UITheme.MAGENTA.darkened(0.3), 1, 0, 8))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := HubW.vbox(6)
	add_child(root)
	var head := HubW.hbox(4)
	var prev := HubW.button("<", func(): _page(-1), 14, UITheme.TEXT_DIM)
	prev.custom_minimum_size = Vector2(44, 36)
	head.add_child(prev)
	_pager = HubW.lbl("", 12, UITheme.MAGENTA)
	_pager.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pager.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_pager)
	var next := HubW.button(">", func(): _page(1), 14, UITheme.TEXT_DIM)
	next.custom_minimum_size = Vector2(44, 36)
	head.add_child(next)
	var close := HubW.button("DONE", func(): screen.close_overlay(), 12, UITheme.MAGENTA, true)
	close.custom_minimum_size = Vector2(64, 36)
	head.add_child(close)
	root.add_child(head)
	_body = HubW.vbox(6)
	root.add_child(HubW.scroll(_body))
	var p := run.perk_pending()
	if p >= 0:
		_i = p
	refresh()


func _page(d: int) -> void:
	_i = posmod(_i + d, run.crew.size())
	refresh()
	HubFx.pop_in(_body, 0.0, 0.12)


func refresh() -> void:
	HubW.clear(_body)
	var m: Dictionary = run.crew[_i]
	var c: Dictionary = UnitDB.CLASSES[m.cls]
	var s := UnitDB.merc_stats(m, run.fixer)
	_pager.text = "%s  %d/%d" % [String(c.name).to_upper(), _i + 1, run.crew.size()]
	var top := HubW.hbox(8)
	top.add_child(HubW.portrait(m.cls, int(m.seed), 4))
	var tv := HubW.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HubW.wrap(HubW.lbl(String(m.name), 14, UITheme.TEXT)))
	tv.add_child(HubW.lbl("%s  ·  %s row  ·  %s" % [c.name, ["front", "mid", "back"][int(c.row)], c.weapon], 9, c.color))
	tv.add_child(RunW.hp_bar(m, run.fixer, 150))
	tv.add_child(HubW.lbl("DMG %.0f  ·  every %.2fs  ·  armor %d  ·  %s" % [s.dmg, s.interval, int(s.armor), "melee" if s.melee else "range %d" % int(s.range)], 9, UITheme.TEXT_DIM))
	if int(m.scars) > 0:
		tv.add_child(HubW.lbl("SCARS x%d: -%d%% max HP" % [int(m.scars), int(int(m.scars) * UnitDB.SCAR_HP * 100)], 9, UITheme.RED))
	top.add_child(tv)
	_body.add_child(top)

	var t := UnitDB.trait_def(m)
	if not t.is_empty():
		_body.add_child(_section("TRAIT: " + String(t.name).to_upper(), String(t.desc), UITheme.YELLOW))
	_body.add_child(_section("SIGNATURE: " + String(c.skill_name).to_upper(), "%s  (every %.0fs)" % [c.skill_desc, s.skill_cd], c.color))
	if String(m.get("perk", "")) != "":
		for pk in UnitDB.perk_choices(m):
			if pk.id == m.perk:
				_body.add_child(_section("REP PERK: " + String(pk.name).to_upper(), String(pk.desc), UITheme.GREEN))
	elif m.get("perk_ready", false):
		_body.add_child(_section("REP PERK READY", "Pick it on the map.", UITheme.GREEN))
	else:
		_body.add_child(HubW.lbl("Rep perk after %d fights (%d/%d)" % [UnitDB.PERK_FIGHTS, int(m.fights), UnitDB.PERK_FIGHTS], 9, UITheme.TEXT_DIM))

	_body.add_child(HubW.line(Color(UITheme.MAGENTA, 0.3)))
	_body.add_child(HubW.lbl("GEAR", 10, UITheme.TEXT_DIM))
	_body.add_child(_slot("WEAPON", String(m.get("weapon", "")), "base: " + String(c.weapon)))
	_body.add_child(_slot("ARMOR", String(m.get("armor", "")), "none"))
	for k in UnitDB.sockets(m):
		_body.add_child(_slot("IMPLANT", m.implants[k] if k < m.implants.size() else "", "empty socket"))
	if UnitDB.sockets(m) == 0:
		_body.add_child(HubW.lbl("No implant sockets.", 9, UITheme.TEXT_DIM))
	var cb := RunW.chrome_bar(m, 200)
	_body.add_child(cb)
	if UnitDB.chrome_load(m) > UnitDB.chrome_cap(m):
		_body.add_child(HubW.wrap(HubW.lbl("OVER CAP: stress builds when hit; at max the merc goes cyberpsycho for 5s (double damage, hits anyone close, ignores your deck).", 9, UITheme.RED)))

	_body.add_child(HubW.line(Color(UITheme.MAGENTA, 0.3)))
	_body.add_child(HubW.lbl("PORTS", 10, UITheme.TEXT_DIM))
	var ports := UnitDB.ports(m)
	if ports.is_empty():
		_body.add_child(HubW.lbl("No port implants: port triggers can't hook this merc.", 9, UITheme.TEXT_DIM))
	for p in ports:
		var hooked := []
		for ti in run.threads.size():
			var trig := ChipDB.get_def(run.threads[ti][0])
			if trig.get("port", "") == p:
				hooked.append("T%d" % (ti + 1))
		var txt := "On %s  ->  %s" % [String(p).capitalize(), ", ".join(hooked) if not hooked.is_empty() else "(free: slot an On %s trigger)" % String(p).capitalize()]
		_body.add_child(HubW.lbl(txt, 10, UITheme.CYAN if not hooked.is_empty() else UITheme.TEXT_DIM))


func _section(title: String, text: String, col: Color) -> Control:
	var v := HubW.vbox(1)
	v.add_child(HubW.lbl(title, 10, col))
	v.add_child(HubW.wrap(HubW.lbl(text, 9, UITheme.TEXT)))
	return v


func _slot(slot_name: String, ref: String, empty: String) -> Control:
	var p := HubW.panel(Color("2a2a48"), HubW.PANEL_BG, 1, 5)
	var h := HubW.hbox(6)
	p.add_child(h)
	var k := HubW.lbl(slot_name, 8, UITheme.TEXT_DIM)
	k.custom_minimum_size.x = 50
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(k)
	if ref == "":
		h.add_child(HubW.lbl(empty, 10, UITheme.TEXT_DIM))
	else:
		var b := RunW.item_block(ref, 3)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return p
