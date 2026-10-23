extends VBoxContainer
## JOBS tab: the contract board. Each job is one run: crew draft, district map, target.

var hub: Control
var _list: VBoxContainer


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 5)
	var head := HubW.hbox(6)
	head.add_child(HubW.lbl("CONTRACTS", 13, UITheme.CYAN))
	head.add_child(HubW.spacer())
	head.add_child(HubW.lbl("pick a job, then a crew", 9, UITheme.TEXT_DIM))
	add_child(head)
	_list = HubW.vbox(8)
	add_child(HubW.scroll(_list))


func on_show() -> void:
	HubFx.stagger(_list, 0.06)


func refresh() -> void:
	HubW.clear(_list)
	if Game.contracts.is_empty():
		_list.add_child(HubW.lbl("No jobs on the board. Check back later.", 12, UITheme.TEXT_DIM))
	for i in Game.contracts.size():
		_list.add_child(_contract_card(i, Game.contracts[i]))
	var stats := HubW.lbl("Runs %d  ·  won %d  ·  stash %d/%d" % [Game.runs_played, Game.runs_won, Game.stash.size(), Game.stash_cap()], 9, UITheme.TEXT_DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(stats)


func _contract_card(i: int, c: Dictionary) -> Control:
	var threat := int(c.threat)
	var tc := HubW.threat_color(threat)
	var p := HubW.panel(tc.darkened(0.35), HubW.PANEL_BG, 1, 8)
	var v := HubW.vbox(4)
	p.add_child(v)
	var top := HubW.hbox(4)
	top.add_child(HubW.lbl("JOB %02d" % (i + 1), 9, UITheme.TEXT_DIM))
	top.add_child(HubW.spacer())
	top.add_child(HubW.lbl(String(c.district).to_upper(), 9, UITheme.CYAN))
	v.add_child(top)
	v.add_child(HubW.wrap(HubW.lbl(String(c.title), 13, UITheme.TEXT), 2))
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
	var foes := UnitDB.enemy_pool(mini(5, threat + 1))
	var lineup := HubW.hbox(-4)
	for k in foes.slice(0, 6):
		var tr := HubW.portrait(k, 3, 1)
		tr.flip_h = true
		lineup.add_child(tr)
	var boss := HubW.portrait("cyberpsycho", 3, 2)
	boss.flip_h = true
	boss.modulate = Color(1.15, 0.8, 0.8)
	lineup.add_child(boss)
	lineup.tooltip_text = "Expected: " + ", ".join(foes.map(func(k): return String(UnitDB.ENEMIES[k].name)))
	lineup.mouse_filter = Control.MOUSE_FILTER_PASS
	var bottom := HubW.hbox(6)
	bottom.add_child(lineup)
	bottom.add_child(HubW.spacer())
	var pay := HubW.vbox(0)
	var pl := HubW.lbl("WIN PAYS", 8, UITheme.TEXT_DIM)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pay.add_child(pl)
	var sr := HubW.hbox(3)
	sr.add_child(HubShard.new(10))
	sr.add_child(HubW.lbl("~%d  +%d rep" % [int(c.get("shards", 0)), threat], 12, HubShard.COLOR.lightened(0.3)))
	pay.add_child(sr)
	bottom.add_child(pay)
	v.add_child(bottom)
	var go := HubW.button("TAKE THE JOB", func(): pass, 13, tc, true)
	go.custom_minimum_size.y = 40
	go.pressed.connect(func(): hub.launch(i, go))
	v.add_child(go)
	return p
