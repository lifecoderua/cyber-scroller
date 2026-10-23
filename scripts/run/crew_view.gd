extends PanelContainer
## Crew sheet (between fights): one merc per page. Both dice face by face, trait, perk, gear
## slots, chrome load (glitch faces above the cap) and PORTS: which daemons hook this merc's
## implants. Chrome is an interface, both ways.

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
	var dd := DiceDB.merc_dice(m, run.fixer)
	_pager.text = "%s  %d/%d" % [String(c.name).to_upper(), _i + 1, run.crew.size()]
	var top := HubW.hbox(8)
	top.add_child(HubW.portrait(m.cls, int(m.seed), 4))
	var tv := HubW.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(HubW.wrap(HubW.lbl(String(m.name), 14, UITheme.TEXT)))
	tv.add_child(HubW.lbl("%s  ·  %s row  ·  %s" % [c.name, ["front", "mid", "back"][int(c.row)], c.weapon], 9, c.color))
	tv.add_child(RunW.hp_bar(m, run.fixer, 150))
	if int(m.scars) > 0:
		tv.add_child(HubW.lbl("SCARS x%d: -%d max HP" % [int(m.scars), int(m.scars)], 9, UITheme.RED))
	top.add_child(tv)
	_body.add_child(top)
	_body.add_child(RunW.dice_strip(m, run.fixer, 40.0))
	var faces := []
	for which in ["gear", "chrome"]:
		for f in dd[which]:
			var line := DiceDB.describe(f)
			if f.k != "blank" and not line in faces:
				faces.append(line)
	_body.add_child(HubW.wrap(HubW.lbl("\n".join(faces), 8, UITheme.TEXT_DIM)))

	var t := UnitDB.trait_def(m)
	if not t.is_empty():
		_body.add_child(_section("TRAIT: " + String(t.name).to_upper(), String(t.desc), UITheme.YELLOW))
	_body.add_child(_section("SIGNATURE: " + String(c.skill_name).to_upper(), String(c.skill_desc), c.color))
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
		_body.add_child(HubW.wrap(HubW.lbl("OVER CAP: signature faces turn into GLITCH (3 damage to a random unit, your crew included; fires by itself if unused).", 9, UITheme.RED)))

	_body.add_child(HubW.line(Color(UITheme.MAGENTA, 0.3)))
	_body.add_child(HubW.lbl("PORTS", 10, UITheme.TEXT_DIM))
	var ports := UnitDB.ports(m)
	if ports.is_empty():
		_body.add_child(HubW.lbl("No port implants: port daemons can't hook this merc.", 9, UITheme.TEXT_DIM))
	for p in ports:
		var hooked := []
		for ref in run.daemons:
			if ChipDB.get_def(ref).get("port", "") == p:
				hooked.append(ChipDB.display_name(ref))
		var txt := "On %s  ->  %s" % [String(p).capitalize(), ", ".join(hooked) if not hooked.is_empty() else "(free: a port daemon can hook it)"]
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
