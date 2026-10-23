extends VBoxContainer
## Non-fight node screens: Fence (shop), Ripperdoc (scars / upgrades / removal), Subnet
## (chip or Trace scrub), Safehouse (heal or recompile) and Events (text choices).

var screen
var run: RunState
var _event_result := {}


func setup(s) -> void:
	screen = s
	run = s.run
	add_theme_constant_override("separation", 6)
	refresh()


func refresh() -> void:
	HubW.clear(self)
	var info: Dictionary = RunState.NODE_INFO.get(run.node(run.pos).get("type", "event"), RunState.NODE_INFO.event)
	match run.phase:
		"fence": _fence(info)
		"ripper": _ripper(info)
		"subnet": _subnet(info)
		"safehouse": _safehouse(info)
		"event": _event()


func _title(text: String, col: Color, sub: String) -> void:
	add_child(HubW.lbl(text, 16, col))
	if sub != "":
		add_child(HubW.wrap(HubW.lbl(sub, 9, UITheme.TEXT_DIM)))


func _leave_button(text := "LEAVE") -> void:
	var b := HubW.button(text, func():
		run.complete_node()
		screen.changed(), 12, UITheme.TEXT_DIM)
	b.custom_minimum_size.y = 38
	add_child(b)


# --- fence ---------------------------------------------------------------------------

func _fence(info: Dictionary) -> void:
	_title("FENCE", info.color, "Chips, gear and a merc for hire. Pay in eddies.")
	var list := HubW.vbox(5)
	var stock: Array = run.pending.get("stock", [])
	for i in stock.size():
		list.add_child(_stock_row(i, stock[i]))
	add_child(HubW.scroll(list))
	_leave_button()


func _stock_row(i: int, o: Dictionary) -> Control:
	var p := HubW.panel(UITheme.YELLOW.darkened(0.5), HubW.PANEL_BG, 1, 6)
	var h := HubW.hbox(6)
	p.add_child(h)
	var body: Control
	if o.kind == "merc":
		var m: Dictionary = o.merc
		body = RunW.merc_row(m, run.fixer)
	else:
		body = RunW.option_block(o)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(body)
	var afford := run.eddies >= int(o.price)
	var label := "SOLD"
	if not o.sold:
		label = ("HIRE\n%d €$" if o.kind == "merc" else "BUY\n%d €$") % int(o.price)
	var b := HubW.button(label, func(): _buy(i), 10, UITheme.YELLOW if afford and not o.sold else UITheme.TEXT_DIM, afford and not o.sold)
	b.custom_minimum_size = Vector2(62, 44)
	b.disabled = o.sold
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return p


func _buy(i: int) -> void:
	var o: Dictionary = run.pending.stock[i]
	if run.eddies < int(o.price):
		screen.deny(null, "Not enough eddies.")
		return
	match String(o.kind):
		"item":
			screen.pick_merc(o.ref, func(m: int, rep: int):
				if run.fence_buy(i, m, rep):
					screen.toast("%s -> %s" % [ItemDB.display_name(o.ref), UnitDB.short_name(run.crew[m])], UITheme.GREEN)
					screen.changed())
		"merc":
			if run.crew.size() >= 3:
				screen.deny(null, "The crew is full (3).")
				return
			if run.fence_buy(i):
				screen.toast("%s joins the crew." % UnitDB.short_name(o.merc), UITheme.GREEN)
				screen.changed()
		_:
			if run.fence_buy(i):
				screen.toast("%s added to spare chips." % ChipDB.display_name(o.ref), UITheme.CYAN)
				screen.changed()


# --- ripperdoc -----------------------------------------------------------------------

func _ripper(info: Dictionary) -> void:
	_title("RIPPERDOC", info.color, "Treat scars (%d €$), upgrade gear one tier (%d €$), pull implants (+%d €$ scrap)." % [
		run.ripper_price("treat"), run.ripper_price("upgrade"), RunState.SCRAP_FOR_OLD])
	var list := HubW.vbox(6)
	for i in run.crew.size():
		list.add_child(_ripper_card(i))
	add_child(HubW.scroll(list))
	_leave_button()


func _ripper_card(i: int) -> Control:
	var m: Dictionary = run.crew[i]
	var v := HubW.vbox(3)
	v.add_child(RunW.merc_row(m, run.fixer))
	if int(m.scars) > 0:
		v.add_child(_service_row("Scar x%d (-%d%% max HP each)" % [int(m.scars), int(UnitDB.SCAR_HP * 100)], "TREAT %d €$" % run.ripper_price("treat"),
			func(): return run.ripper_treat(i), UITheme.GREEN))
	for slot in ["weapon", "armor"]:
		var ref := String(m.get(slot, ""))
		if ref != "" and ItemDB.tier(ref) < 2:
			v.add_child(_service_row(ItemDB.display_name(ref), "UPGRADE %d €$" % run.ripper_price("upgrade"),
				func(): return run.ripper_upgrade(i, slot), UITheme.CYAN))
	for k in m.implants.size():
		var ref: String = m.implants[k]
		var row := HubW.hbox(4)
		var l := HubW.clip(HubW.lbl("%s  (%d chrome)" % [ItemDB.display_name(ref), int(ItemDB.get_def(ref).get("chrome", 0))], 10, UITheme.TEXT))
		row.add_child(l)
		if ItemDB.tier(ref) < 2:
			var up := HubW.button("UP %d" % run.ripper_price("upgrade"), func(): _service(func(): return run.ripper_upgrade(i, "implant:%d" % k)), 9, UITheme.CYAN)
			up.custom_minimum_size = Vector2(58, 30)
			row.add_child(up)
		var rm := HubW.button("PULL", func(): _service(func(): return run.ripper_remove(i, k)), 9, UITheme.MAGENTA)
		rm.custom_minimum_size = Vector2(48, 30)
		row.add_child(rm)
		v.add_child(row)
	return v


func _service_row(text: String, btn: String, action: Callable, col: Color) -> Control:
	var row := HubW.hbox(4)
	row.add_child(HubW.clip(HubW.lbl(text, 10, UITheme.TEXT)))
	var b := HubW.button(btn, func(): _service(action), 9, col)
	b.custom_minimum_size = Vector2(98, 30)
	row.add_child(b)
	return row


func _service(action: Callable) -> void:
	if action.call():
		Audio.play("purchase")
		screen.changed()
	else:
		screen.deny(null, "Not enough eddies.")


# --- subnet --------------------------------------------------------------------------

func _subnet(info: Dictionary) -> void:
	_title("SUBNET", info.color, "A quiet node in the local net. Take a chip, or use it to scrub your Trace.")
	var chips: Array = run.pending.get("chips", [])
	for i in chips.size():
		var pb := RunW.card(info.color)
		var p: PanelContainer = pb[0]
		p.add_child(RunW.chip_block(chips[i]))
		p.add_child(pb[1])
		(pb[1] as Button).pressed.connect(func():
			run.subnet_take(i)
			screen.toast("%s added to spare chips." % ChipDB.display_name(chips[i]), UITheme.CYAN)
			screen.changed())
		add_child(p)
	add_child(HubW.lbl("- OR -", 10, UITheme.TEXT_DIM))
	var amt := int(run.subnet_scrub_amount())
	var b := HubW.button("SCRUB TRACE  -%d%%   (now %d%%)" % [amt, int(run.trace)], func():
		run.subnet_scrub()
		screen.toast("Trace scrubbed.", UITheme.PURPLE)
		screen.changed(), 12, UITheme.PURPLE, true)
	b.custom_minimum_size.y = 42
	add_child(b)


# --- safehouse -----------------------------------------------------------------------

func _safehouse(info: Dictionary) -> void:
	_title("SAFEHOUSE", info.color, "One night off. Patch everyone up, or spend it recompiling a chip to tier II.")
	var hurt := 0.0
	for m in run.crew:
		hurt += 1.0 - float(m.hp_pct)
	var heal := HubW.button("HEAL THE CREW  (missing %d%%)" % int(hurt * 100.0 / maxf(1, run.crew.size())), func():
		run.safehouse_heal()
		screen.toast("Crew at full HP.", UITheme.GREEN)
		screen.changed(), 12, UITheme.GREEN, true)
	heal.custom_minimum_size.y = 44
	add_child(heal)
	for m in run.crew:
		add_child(RunW.merc_row(m, run.fixer))
	add_child(HubW.lbl("- OR -", 10, UITheme.TEXT_DIM))
	var rec := HubW.button("RECOMPILE A CHIP", _recompile, 12, UITheme.CYAN, true)
	rec.custom_minimum_size.y = 44
	add_child(rec)


func _recompile() -> void:
	var opts := []
	var where := []
	for t in run.threads.size():
		for s in run.threads[t].size():
			var ref: String = run.threads[t][s]
			if ref != "" and ChipDB.tier(ref) < 2:
				opts.append(["T%d: %s -> %s" % [t + 1, ChipDB.display_name(ref), ChipDB.display_name(ChipDB.upgraded(ref))],
					ChipDB.desc(ChipDB.upgraded(ref)), ChipDB.color(ref)])
				where.append("thread:%d:%d" % [t, s])
	for i in run.spare.size():
		var ref: String = run.spare[i]
		if ChipDB.tier(ref) < 2:
			opts.append(["Spare: %s -> %s" % [ChipDB.display_name(ref), ChipDB.display_name(ChipDB.upgraded(ref))],
				ChipDB.desc(ChipDB.upgraded(ref)), ChipDB.color(ref)])
			where.append("spare:%d" % i)
	if opts.is_empty():
		screen.deny(null, "Every chip is already tier II.")
		return
	screen.choose("RECOMPILE WHICH CHIP?", opts, func(k: int):
		if run.safehouse_recompile(where[k]):
			screen.toast("Recompiled.", UITheme.CYAN)
			screen.changed(), UITheme.CYAN)


# --- event ---------------------------------------------------------------------------

func _event() -> void:
	var ev := EventDB.get_event(String(run.pending.get("event", "")))
	if ev.is_empty():
		_leave_button("CONTINUE")
		return
	_title(String(ev.title), UITheme.PURPLE, "")
	var body := HubW.panel(UITheme.PURPLE.darkened(0.5), HubW.DEEP_BG, 1, 10)
	body.add_child(HubW.wrap(HubW.lbl(String(ev.text), 12, UITheme.TEXT)))
	add_child(body)
	for i in ev.choices.size():
		var c: Dictionary = ev.choices[i]
		var b := HubW.button("", func(): _choose(i), 11, UITheme.PURPLE)
		b.custom_minimum_size.y = 46
		var v := HubW.vbox(0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 6
		v.add_child(HubW.lbl(String(c.label), 12, UITheme.TEXT))
		v.add_child(HubW.lbl(String(c.hint), 9, UITheme.TEXT_DIM))
		b.add_child(v)
		add_child(b)


func _choose(i: int) -> void:
	var res := run.event_choose(i)
	if res.is_empty():
		return
	if res.get("denied", false):
		screen.deny(null, String(res.text))
		return
	Game.run_changed()
	screen.toast(String(res.text), UITheme.PURPLE)
	if res.get("fight", false):
		screen._jack_in()
		return
	screen.refresh()
