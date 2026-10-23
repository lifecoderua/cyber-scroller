extends VBoxContainer
## Loot pick after a fight (or at a cache): pick 1 of N. Items go on a merc (with fit
## previews), chips go to the deck's spare pool. Unpicked options turn into scrap eddies.
## Crew and deck compete for the same pick: that's the decision.

var screen
var run: RunState
var _selected := -1
var _cards: Array = []
var _action: VBoxContainer


func setup(s) -> void:
	screen = s
	run = s.run
	add_theme_constant_override("separation", 5)
	refresh()


func refresh() -> void:
	HubW.clear(self)
	_cards.clear()
	var opts: Array = run.pending.get("loot", [])
	var lf := run.last_fight
	var head := HubW.hbox(6)
	var cache: bool = run.node(run.pos).get("type", "") == "cache"
	head.add_child(HubW.lbl("CACHE" if cache else "SALVAGE", 16, UITheme.YELLOW))
	head.add_child(HubW.lbl("pick 1 of %d" % opts.size(), 10, UITheme.TEXT_DIM))
	add_child(head)
	if not cache and not lf.is_empty():
		var bits := ["+%d €$" % int(lf.bag), "%d kills" % int(lf.kills), "Trace +%d" % int(round(float(lf.trace_gain)))]
		if int(lf.get("downed", 0)) > 0:
			bits.append("%d downed: +1 scar" % int(lf.downed))
		add_child(HubW.lbl("  ·  ".join(bits), 9, UITheme.TEXT_DIM))
	var list := HubW.vbox(5)
	for i in opts.size():
		list.add_child(_option_card(i, opts[i]))
	add_child(HubW.scroll(list))
	_action = HubW.vbox(4)
	add_child(_action)
	_build_action()


func _option_card(i: int, o: Dictionary) -> Control:
	var accent: Color = RunW.SOURCE_COLORS.get(o.source, UITheme.CYAN)
	var pb := RunW.card(accent)
	var p: PanelContainer = pb[0]
	var v := HubW.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HubW.hbox(4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(RunW.source_tag(o.source))
	top.add_child(HubW.spacer())
	var kind_txt := "CHIP -> DECK" if o.kind == "chip" else ("GEAR -> MERC" if o.kind == "item" else "SCRAP")
	top.add_child(HubW.lbl(kind_txt, 8, UITheme.TEXT_DIM))
	v.add_child(top)
	v.add_child(RunW.option_block(o))
	p.add_child(v)
	p.add_child(pb[1])
	(pb[1] as Button).pressed.connect(func(): _select(i))
	RunW.set_selected(p, accent, i == _selected)
	_cards.append([p, accent])
	return p


func _select(i: int) -> void:
	_selected = i
	for k in _cards.size():
		RunW.set_selected(_cards[k][0], _cards[k][1], k == i)
	_build_action()


func _build_action() -> void:
	HubW.clear(_action)
	var opts: Array = run.pending.get("loot", [])
	if _selected >= 0 and _selected < opts.size():
		var o: Dictionary = opts[_selected]
		match String(o.kind):
			"chip":
				var b := HubW.button("ADD %s TO DECK" % ChipDB.display_name(o.ref).to_upper(), func(): _take(-1, -1), 12, UITheme.CYAN, true)
				_action.add_child(b)
			"scrap":
				_action.add_child(HubW.button("TAKE %d €$ SCRAP" % int(o.amount), func(): _take(-1, -1), 12, UITheme.YELLOW, true))
			"item":
				var row := HubW.hbox(4)
				for m in run.crew.size():
					row.add_child(_merc_button(o.ref, m))
				_action.add_child(row)
	else:
		_action.add_child(HubW.lbl("Tap an option. Unpicked loot turns into scrap €$.", 9, UITheme.TEXT_DIM))
	_action.add_child(HubW.button("SKIP ALL  ->  +%d €$" % run.skip_value(), _skip, 11, UITheme.TEXT_DIM))


## Merc target button with a fit preview (red = over chrome cap / can't take).
func _merc_button(item: String, i: int) -> Control:
	var m: Dictionary = run.crew[i]
	var fit := run.fit_preview(item, i)
	var col: Color = UnitDB.CLASSES[m.cls].color
	if fit.warn or not fit.ok:
		col = UITheme.RED
	var b := HubW.button("", func(): _give(item, i), 10, col)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 44
	var v := HubW.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := HubW.lbl(UnitDB.short_name(m), 11, UITheme.TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	v.add_child(n)
	var f := HubW.lbl(fit.text, 8, col.lightened(0.2))
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.clip_text = true
	v.add_child(f)
	b.add_child(v)
	return b


func _give(item: String, i: int) -> void:
	var fit := run.fit_preview(item, i)
	if not fit.ok:
		screen.deny(null, "%s: %s" % [UnitDB.short_name(run.crew[i]), fit.text])
		return
	if fit.replaces == "?":
		var m: Dictionary = run.crew[i]
		var iopts := []
		for ref in m.implants:
			iopts.append([ItemDB.display_name(ref), ItemDB.desc(ref), ItemDB.slot_color("implant")])
		screen.choose("REPLACE WHICH IMPLANT?", iopts, func(k: int): _take(i, k), UITheme.MAGENTA)
		return
	_take(i, -1)


func _take(merc: int, replace_index: int) -> void:
	var o: Dictionary = run.pending.loot[_selected]
	if not run.take_loot(_selected, merc, replace_index):
		screen.deny(null, "Can't take that.")
		return
	match String(o.kind):
		"chip":
			screen.toast("%s added to spare chips. Slot it in DECK." % ChipDB.display_name(o.ref), UITheme.CYAN)
		"item":
			screen.toast("%s -> %s" % [ItemDB.display_name(o.ref), UnitDB.short_name(run.crew[merc])], UITheme.GREEN)
	Audio.play("purchase")
	screen.changed()


func _skip() -> void:
	run.skip_loot()
	screen.toast("Sold for scrap.", UITheme.YELLOW)
	screen.changed()
