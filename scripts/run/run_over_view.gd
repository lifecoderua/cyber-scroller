extends VBoxContainer
## End of a run. Won: pick gear to extract into the safehouse stash. Lost (wiped /
## traced / abandoned): the debrief. FINISH pays shards and returns to the hub.

const TITLES := {
	"won": ["JOB DONE", Color("4cff8f"), "Target down. Pick what the crew brings home."],
	"wiped": ["FLATLINED", Color("ff2a2a"), "The whole crew is down."],
	"traced": ["TRACED", Color("ff2a2a"), "Corp security burned your connection."],
	"abandoned": ["WALKED AWAY", Color("f9c80e"), "The crew scatters."],
}

var screen
var run: RunState
var _picked: Array = []   # indices into run.crew_items()
var _list: VBoxContainer
var _finish: Button


func setup(s) -> void:
	screen = s
	run = s.run
	add_theme_constant_override("separation", 6)
	var info: Array = TITLES.get(run.outcome, TITLES.wiped)
	var t := HubW.lbl(info[0], 26, info[1])
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 4)
	add_child(t)
	var sub := HubW.lbl(info[2], 10, UITheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	add_child(HubW.line(Color(info[1], 0.35)))
	var won := run.outcome == "won"
	var shards := Game.shards_for(run.outcome, run.threat, run.fights_won)
	for row in [["Fights won", str(run.fights_won)], ["Kills", str(run.kills)], ["Trace", "%d%%" % int(run.trace)],
			["Data Shards", "+%d" % shards], ["Rep", "+%d" % (run.threat if won else 0)]]:
		var h := HubW.hbox(6)
		h.add_child(HubW.lbl(row[0], 11, UITheme.TEXT_DIM))
		h.add_child(HubW.spacer())
		h.add_child(HubW.lbl(row[1], 12, UITheme.TEXT))
		add_child(h)
	if won:
		var room := Game.stash_cap() - Game.stash.size()
		var n := mini(Game.extract_count(), room)
		add_child(HubW.line(Color(info[1], 0.35)))
		add_child(HubW.lbl("EXTRACT TO STASH: pick %d  (stash %d/%d)" % [n, Game.stash.size(), Game.stash_cap()], 11, UITheme.YELLOW))
		if n <= 0:
			add_child(HubW.wrap(HubW.lbl("The stash is full. Clear space in the hub to extract next time.", 9, UITheme.RED)))
		_list = HubW.vbox(4)
		var items := run.crew_items()
		for k in items.size():
			_list.add_child(_item_row(k, items[k], n))
		if run.crew_items().is_empty():
			_list.add_child(HubW.lbl("The crew carries no gear.", 9, UITheme.TEXT_DIM))
		add_child(HubW.scroll(_list))
	else:
		add_child(HubW.spacer(true))
	_finish = HubW.button("FINISH", _done, 14, info[1], true)
	_finish.custom_minimum_size.y = 46
	add_child(_finish)
	Audio.play_result({"outcome": run.outcome})


func _item_row(k: int, ref: String, cap: int) -> Control:
	var pb := RunW.card(UITheme.YELLOW)
	var p: PanelContainer = pb[0]
	p.add_child(RunW.item_block(ref))
	p.add_child(pb[1])
	(pb[1] as Button).pressed.connect(func():
		if k in _picked:
			_picked.erase(k)
		elif _picked.size() < cap:
			_picked.append(k)
		else:
			screen.deny(null, "Pick %d." % cap)
			return
		RunW.set_selected(p, UITheme.YELLOW, k in _picked))
	return p


func _done() -> void:
	var items := run.crew_items()
	Game.end_run(_picked.map(func(k): return items[k]))
