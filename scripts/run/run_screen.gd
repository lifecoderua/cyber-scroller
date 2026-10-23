extends ScreenBase
## Run scene: everything between fights. Header (contract, Trace, eddies), the current
## phase's view in the middle (crew draft, district map, loot, node screens, results)
## and a thumb-zone footer (CREW, DECK, menu). All rules live in RunState; this scene
## only shows them and saves through Game.run_changed().

const MapView := preload("res://scripts/run/map_view.gd")
const LootView := preload("res://scripts/run/loot_view.gd")
const NodeViews := preload("res://scripts/run/node_views.gd")
const DeckEditor := preload("res://scripts/run/deck_editor.gd")
const CrewView := preload("res://scripts/run/crew_view.gd")
const RunOver := preload("res://scripts/run/run_over_view.gd")
const BG_SCRIPT := preload("res://scripts/hub/hub_bg.gd")
const DeckMeters := preload("res://scripts/mission/deck_meters.gd")

var run: RunState
var fixer: Dictionary
var _content: Control
var _view: Control
var _phase := ""
var _title: Label
var _eddies: Label
var _trace: MeterBar
var _row_label: Label
var _footer: HBoxContainer
var _crew_btn: Button
var _deck_btn: Button
var _overlay: Control
var _shown_eddies := -1


func _ready() -> void:
	theme = screen_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(BG_SCRIPT.new())
	run = Game.run
	if run == null:
		Game.goto.call_deferred("hub")
		return
	fixer = run.fixer
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var root := HubW.vbox(6)
	margin.add_child(root)
	root.add_child(_build_header())
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	root.add_child(_content)
	root.add_child(_build_footer())
	build_layers(60)
	refresh()


func _build_header() -> Control:
	var v := HubW.vbox(3)
	var top := HubW.hbox(6)
	_title = HubW.clip(HubW.lbl("", 11, UITheme.CYAN))
	top.add_child(_title)
	var ep := HubW.panel(UITheme.YELLOW.darkened(0.35), HubW.DEEP_BG, 1, 5)
	_eddies = HubW.lbl("", 13, UITheme.YELLOW)
	ep.add_child(_eddies)
	top.add_child(ep)
	v.add_child(top)
	var tr := HubW.hbox(6)
	_trace = MeterBar.new("TRACE", UITheme.PURPLE, 14)
	_trace.ticks = true
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trace.tooltip_text = "Trace is your HP. Fights, netrunners, Hijack and overheats raise it. 100% burns the run."
	_trace.mouse_filter = Control.MOUSE_FILTER_PASS
	tr.add_child(_trace)
	_row_label = HubW.lbl("", 9, UITheme.TEXT_DIM)
	tr.add_child(_row_label)
	v.add_child(tr)
	return v


func _build_footer() -> Control:
	_footer = HubW.hbox(6)
	_footer.custom_minimum_size.y = 44
	_crew_btn = HubW.button("CREW", open_crew, 13, UITheme.MAGENTA)
	_crew_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_btn.custom_minimum_size.y = 42
	_footer.add_child(_crew_btn)
	_deck_btn = HubW.button("DECK", open_deck, 13, UITheme.CYAN)
	_deck_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_btn.custom_minimum_size.y = 42
	_footer.add_child(_deck_btn)
	var menu := HubW.button("≡", _open_menu, 15, UITheme.TEXT_DIM)
	menu.custom_minimum_size = Vector2(44, 42)
	_footer.add_child(menu)
	return _footer


func _update_header() -> void:
	var c := run.contract
	_title.text = "%s  //  %s" % [String(c.get("district", "")).to_upper(), String(c.get("title", ""))]
	if _shown_eddies >= 0 and run.eddies != _shown_eddies:
		var d := run.eddies - _shown_eddies
		float_text(("%+d €$" % d), UITheme.GREEN if d > 0 else UITheme.MAGENTA, _eddies.get_parent())
		HubFx.flash(_eddies.get_parent(), UITheme.GREEN if d > 0 else UITheme.MAGENTA, 0.4)
	_shown_eddies = run.eddies
	_eddies.text = "%d €$" % run.eddies
	_trace.color = DeckMeters.trace_color(run.trace)
	_trace.set_value(run.trace, 100.0, "%d%%" % int(run.trace))
	_trace.warn = run.trace >= 75.0
	var row := run.current_row()
	_row_label.text = "NODE %d/%d" % [row + 1, RunState.ROWS + 1] if row >= 0 else "START"
	_crew_btn.text = "CREW" + (" !" if run.perk_pending() >= 0 else "")
	_footer.visible = run.phase not in ["draft", "over"]


## Rebuild for the current phase. Views call this after every rule change.
func refresh() -> void:
	_update_header()
	if run.phase == _phase and _view and _view.has_method("refresh"):
		_view.refresh()
		return
	_phase = run.phase
	if _view:
		_view.queue_free()
		_view = null
	match run.phase:
		"draft":
			_view = _build_draft()
		"map":
			_view = _build_map()
		"loot":
			_view = LootView.new()
		"fence", "ripper", "subnet", "safehouse", "event":
			_view = NodeViews.new()
		"fight":
			_view = _build_jack_in()
		"over":
			_view = RunOver.new()
	if _view == null:
		return
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(_view)
	if _view.has_method("setup"):
		_view.setup(self)
	HubFx.pop_in(_view, 0.0, 0.18)
	if run.phase == "map":
		_maybe_perk.call_deferred()


## Save + redraw after a rule change.
func changed() -> void:
	Game.run_changed()
	refresh()


# --- draft ---------------------------------------------------------------------------

func _build_draft() -> Control:
	var v := HubW.vbox(6)
	v.add_child(HubW.lbl("JACK IN: PICK A CREW", 16, UITheme.CYAN))
	v.add_child(HubW.wrap(HubW.lbl("You never touch the street. Pick the hired guns you'll run through your deck. Two-merc crews come with +%d €$." % RunState.DUO_BONUS, 9, UITheme.TEXT_DIM)))
	var list := HubW.vbox(8)
	for i in run.drafts.size():
		list.add_child(_draft_card(i))
	v.add_child(HubW.scroll(list))
	return v


func _draft_card(i: int) -> Control:
	var team: Array = run.drafts[i]
	var p := HubW.panel(UITheme.CYAN.darkened(0.4), HubW.DEEP_BG, 1, 6)
	var v := HubW.vbox(4)
	p.add_child(v)
	var head := HubW.hbox(6)
	var names := team.map(func(m): return String(UnitDB.CLASSES[m.cls].name))
	head.add_child(HubW.clip(HubW.lbl("CREW %s:  %s" % ["ABC"[i] if i < 3 else str(i + 1), " / ".join(names)], 11, UITheme.TEXT)))
	if team.size() <= 2:
		head.add_child(HubW.lbl("+%d €$" % RunState.DUO_BONUS, 10, UITheme.YELLOW))
	v.add_child(head)
	for m in team:
		v.add_child(RunW.merc_row(m, fixer))
	var b := HubW.button("TAKE THIS CREW", func(): _pick_draft(i), 12, UITheme.CYAN, true)
	v.add_child(b)
	return p


func _pick_draft(i: int) -> void:
	if Game.stash.is_empty():
		_finish_draft(i, -1, -1)
		return
	var opts := [["Go without stash gear", "Keep the stash safe", UITheme.TEXT_DIM]]
	for ref in Game.stash:
		opts.append([ItemDB.display_name(ref), ItemDB.desc(ref), ItemDB.slot_color(String(ItemDB.get_def(ref).slot))])
	choose("BRING GEAR FROM THE STASH? (lost if the run fails)", opts, func(k: int):
		if k == 0:
			_finish_draft(i, -1, -1)
			return
		var team: Array = run.drafts[i]
		var mopts := []
		for m in team:
			mopts.append([UnitDB.short_name(m), String(UnitDB.CLASSES[m.cls].name), UnitDB.CLASSES[m.cls].color])
		choose("WHO CARRIES %s?" % ItemDB.display_name(Game.stash[k - 1]).to_upper(), mopts, func(t: int): _finish_draft(i, k - 1, t)))


func _finish_draft(i: int, stash_index: int, target: int) -> void:
	if Game.choose_draft(i, stash_index, target):
		screen_flash(UITheme.CYAN, 0.3, 0.4)
		toast("Crew linked. Pick your first node.", UITheme.CYAN)
		refresh()


# --- map -----------------------------------------------------------------------------

func _build_map() -> Control:
	var v := HubW.vbox(4)
	var hint := HubW.lbl("Tap a glowing node. Fights pay loot, rest nodes fix the crew.", 9, UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var mv: Control = MapView.new()
	mv.run = run
	mv.reveal = float(fixer.get("reveal", 0.0)) > 0.0
	mv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.node_tapped.connect(func(id): _preview(id, true))
	mv.peek.connect(func(id): _preview(id, false))
	v.add_child(mv)
	return v


func _preview(id: int, can_go: bool) -> void:
	var n := run.node(id)
	var info: Dictionary = RunState.NODE_INFO[n.type]
	var col: Color = info.color
	var pv := modal_panel(col)
	var v: VBoxContainer = pv[1]
	var head := HubW.hbox(6)
	head.add_child(HubW.lbl(String(info.name), 16, col))
	head.add_child(HubW.spacer())
	if n.type in ["fight", "elite", "cache", "boss"]:
		head.add_child(HubW.lbl(String(RunState.THEME_NAMES.get(n.theme, "")).to_upper(), 9, UITheme.TEXT_DIM))
	v.add_child(head)
	v.add_child(HubW.wrap(HubW.lbl(String(info.desc), 10, UITheme.TEXT)))
	if not n.waves.is_empty():
		v.add_child(HubW.line(Color(col, 0.3)))
		v.add_child(HubW.lbl("INTEL: %d WAVES" % n.waves.size(), 9, UITheme.TEXT_DIM))
		var roles := {}
		for w in n.waves:
			for spec in w:
				var parts := String(spec).split(":")
				var key := parts[0]
				roles[key] = int(roles.get(key, 0)) + 1
				if parts.size() > 1:
					roles["elite:" + parts[1]] = 1
		for k in roles:
			if String(k).begins_with("elite:"):
				var a: Dictionary = UnitDB.AFFIXES[String(k).split(":")[1]]
				v.add_child(HubW.wrap(HubW.lbl("ELITE %s: %s" % [String(a.name).to_upper(), a.desc], 9, Color("ff9f1c"))))
				continue
			var e: Dictionary = UnitDB.ENEMIES[k]
			var row := HubW.hbox(6)
			row.add_child(HubW.portrait(k, 3, 1))
			var tv := HubW.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_child(HubW.lbl("%s x%d" % [String(e.name).to_upper(), int(roles[k])], 10, UITheme.TEXT))
			tv.add_child(HubW.wrap(HubW.lbl(String(e.hint), 8, UITheme.TEXT_DIM), 2))
			row.add_child(tv)
			v.add_child(row)
		var tr: float = RunState.FIGHT_TRACE.get(n.type, 2.0)
		v.add_child(HubW.lbl("Jacking into the local net: +%d Trace" % int(tr), 9, UITheme.PURPLE))
		if run.alert() or run.trace + tr >= RunState.ALERT_TRACE:
			v.add_child(HubW.wrap(HubW.lbl("ALERT (Trace %d%%+): corp security adds a gunman to every wave." % int(RunState.ALERT_TRACE), 9, UITheme.RED)))
	elif n.type == "event" and float(fixer.get("reveal", 0.0)) > 0.0:
		var ev := EventDB.get_event(n.event)
		v.add_child(HubW.lbl(String(ev.get("title", "")), 10, UITheme.PURPLE))
	var row := HubW.hbox(8)
	var close := HubW.button("CLOSE", func(): close_from(v), 12, UITheme.TEXT_DIM)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(close)
	if can_go:
		var go := HubW.button("GO", func():
			close_from(v)
			_enter(id), 13, col, true)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(go)
	v.add_child(row)
	open_modal(pv[0])


func _enter(id: int) -> void:
	var screen := run.enter(id)
	Game.run_changed()
	if screen == "fight":
		_jack_in()
		return
	if screen == "over":
		screen_flash(UITheme.RED, 0.5, 0.6)
	refresh()


func _jack_in() -> void:
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color(UITheme.CYAN, 0.0)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(cover)
	var l := HubW.lbl("JACKING IN", 22, UITheme.CYAN)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	cover.add_child(l)
	var t := cover.create_tween()
	t.tween_property(cover, "color", Color(UITheme.CYAN, 0.5), 0.06)
	t.tween_property(cover, "color", Color(UITheme.BG, 0.97), 0.25)
	t.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	for i in 3:
		t.tween_callback(func(): l.text = "JACKING IN" + ".".repeat(i + 1))
		t.tween_interval(0.1)
	t.tween_callback(Game.begin_fight)


func _build_jack_in() -> Control:
	var v := HubW.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := HubW.lbl("CONTACT AHEAD", 18, UITheme.RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := HubW.button("JACK IN", _jack_in, 15, UITheme.RED, true)
	b.custom_minimum_size.y = 48
	v.add_child(b)
	return v


# --- perks ---------------------------------------------------------------------------

func _maybe_perk() -> void:
	var i := run.perk_pending()
	if i < 0 or modal_open() or run.phase != "map":
		return
	var m: Dictionary = run.crew[i]
	var opts := []
	for p in UnitDB.perk_choices(m):
		opts.append([String(p.name), String(p.desc), UnitDB.CLASSES[m.cls].color])
	var picks: Array = UnitDB.perk_choices(m)
	choose("%s EARNED A REP PERK" % UnitDB.short_name(m).to_upper(), opts, func(k: int):
		run.choose_perk(i, picks[k].id)
		toast("%s: %s" % [UnitDB.short_name(m), picks[k].name], UnitDB.CLASSES[m.cls].color)
		changed()
		_maybe_perk.call_deferred(), UnitDB.CLASSES[m.cls].color)


# --- shared pickers ------------------------------------------------------------------

## Choose who gets an item (with fit previews); implants on a full merc ask which one to
## replace. on_pick(merc_index, replace_index).
func pick_merc(item: String, on_pick: Callable) -> void:
	var opts := []
	for i in run.crew.size():
		var m: Dictionary = run.crew[i]
		var fit := run.fit_preview(item, i)
		opts.append(["%s  (%s)" % [UnitDB.short_name(m), UnitDB.CLASSES[m.cls].name], fit.text,
			UITheme.RED if fit.warn or not fit.ok else UnitDB.CLASSES[m.cls].color])
	choose("WHO GETS %s?" % ItemDB.display_name(item).to_upper(), opts, func(i: int):
		var fit := run.fit_preview(item, i)
		if not fit.ok:
			deny(null, "%s can't take it: %s" % [UnitDB.short_name(run.crew[i]), fit.text])
			return
		if fit.replaces != "?":
			on_pick.call(i, -1)
			return
		var m: Dictionary = run.crew[i]
		var iopts := []
		for ref in m.implants:
			iopts.append([ItemDB.display_name(ref), ItemDB.desc(ref), ItemDB.slot_color("implant")])
		choose("REPLACE WHICH IMPLANT?", iopts, func(k: int): on_pick.call(i, k), UITheme.MAGENTA))


# --- overlays ----------------------------------------------------------------------------

func _open_overlay(c: Control) -> void:
	close_overlay()
	_overlay = c
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(c)
	if c.has_method("setup"):
		c.setup(self)
	HubFx.pop_in(c, 0.0, 0.16)


func close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	refresh()


func open_deck() -> void:
	_open_overlay(DeckEditor.new())


func open_crew() -> void:
	_open_overlay(CrewView.new())


func _open_menu() -> void:
	var pv := modal_panel(UITheme.CYAN, 260)
	var v: VBoxContainer = pv[1]
	v.add_child(HubW.lbl("RUN", 15, UITheme.CYAN))
	v.add_child(HubW.lbl("Fights won %d  ·  kills %d  ·  threat %d" % [run.fights_won, run.kills, run.threat], 9, UITheme.TEXT_DIM))
	v.add_child(Audio.mute_row())
	v.add_child(HubW.button("ABANDON RUN", func():
		close_from(v)
		confirm("ABANDON THE RUN?", "The crew walks. You keep a few shards for the fights you won; stash gear on this crew is lost.", "ABANDON", func():
			Game.abandon_run()
			refresh()), 12, UITheme.RED))
	v.add_child(HubW.button("CLOSE", func(): close_from(v), 12, UITheme.TEXT_DIM))
	open_modal(pv[0])

