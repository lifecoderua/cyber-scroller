extends HBoxContainer
## NODES tab: the fixer skill tree. Pannable node graph on the left, info / buy panel
## on the right. Bought with Data Shards (Game.shards); see TreeDB.

var hub: Control
var graph: TreeGraph
var _info: VBoxContainer
var _count: Label


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 6)

	var frame := HubW.panel(HubShard.COLOR.darkened(0.45), Color(0.02, 0.02, 0.05, 0.92), 1, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(frame)
	var holder := Control.new()
	holder.clip_contents = true
	frame.add_child(holder)
	graph = TreeGraph.new()
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph.node_tapped.connect(_on_node)
	graph.empty_tapped.connect(func(): _select(""))
	holder.add_child(graph)

	# Overlay: title + counters (top-left), recenter (top-right).
	var top := HubW.hbox(6)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -4
	top.offset_top = 3
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(top)
	var tp := HubW.panel(Color(0, 0, 0, 0), Color(0.02, 0.02, 0.05, 0.78), 0, 4)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tv := HubW.vbox(0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(HubW.lbl("FIXER NET", 12, HubShard.COLOR.lightened(0.2)))
	_count = HubW.lbl("", 8, UITheme.TEXT_DIM)
	tv.add_child(_count)
	tp.add_child(tv)
	top.add_child(tp)
	top.add_child(HubW.spacer())
	var center := HubW.button("CENTER", func(): graph.recenter(), 9, UITheme.TEXT_DIM)
	center.custom_minimum_size = Vector2(54, 26)
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(center)
	var hint := HubW.panel(Color(0, 0, 0, 0), Color(0.02, 0.02, 0.05, 0.78), 0, 3)
	hint.add_child(HubW.lbl("drag to pan  ·  tap a node", 8, Color(UITheme.TEXT_DIM, 0.8)))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 3
	hint.offset_bottom = -3
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hint)

	var right := HubW.panel(HubShard.COLOR.darkened(0.4), HubW.PANEL_BG, 1, 7)
	right.custom_minimum_size.x = 186
	add_child(right)
	_info = HubW.vbox(4)
	right.add_child(_info)


func on_show() -> void:
	HubFx.pop_in(graph, 0.0, 0.25)


func refresh() -> void:
	var owned := 0
	var ranks := 0
	var total_ranks := 0
	for id in TreeDB.all_ids():
		if Game.tree_rank(id) > 0:
			owned += 1
		ranks += Game.tree_rank(id)
		total_ranks += TreeDB.max_rank(id)
	_count.text = "%d/%d nodes  ·  %d/%d ranks" % [owned, TreeDB.all_ids().size(), ranks, total_ranks]
	_build_info()


func _on_node(id: String) -> void:
	_select(id)
	graph.focus(id)


func _select(id: String) -> void:
	if graph.selected == id:
		return
	graph.selected = id
	_build_info()
	HubFx.pop_in(_info, 0.0, 0.14)


# --- info panel ------------------------------------------------------------------

func _shard_row(amount: int, size := 13, col := HubShard.COLOR) -> HBoxContainer:
	var row := HubW.hbox(4)
	row.add_child(HubShard.new(size - 2, col))
	var l := HubW.lbl(str(amount), size, col.lightened(0.25))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _build_info() -> void:
	HubW.clear(_info)
	var id := graph.selected
	if id == "":
		_build_overview()
		return
	var d := TreeDB.def(id)
	var col := TreeDB.branch_color(id)
	var rank := Game.tree_rank(id)
	var mr := TreeDB.max_rank(id)
	var state := Game.node_state(id)

	var head := HubW.hbox(4)
	var br: Dictionary = TreeDB.BRANCHES[d.branch]
	head.add_child(HubW.lbl(String(br.name), 8, Color(col, 0.85)))
	head.add_child(HubW.spacer())
	if id.ends_with("_cap"):
		head.add_child(HubW.lbl("CAPSTONE", 8, UITheme.YELLOW))
	_info.add_child(head)
	_info.add_child(HubW.wrap(HubW.lbl(String(d.name), 15, col.lightened(0.15))))
	var rr := HubW.hbox(6)
	rr.add_child(HubW.lbl("RANK %d/%d" % [rank, mr], 10, UITheme.TEXT if rank > 0 else UITheme.TEXT_DIM))
	rr.add_child(HubPips.new(rank, mr, col, HubPips.Mode.CELL))
	_info.add_child(rr)
	_info.add_child(HubW.line(Color(col, 0.3)))
	_info.add_child(HubW.wrap(HubW.lbl(String(d.desc), 10, UITheme.TEXT)))

	if d.has("show"):
		if rank > 0:
			_info.add_child(_effect_line("NOW", TreeDB.show_text(id, rank), col))
		if rank < mr:
			_info.add_child(_effect_line("NEXT", TreeDB.show_text(id, rank + 1), UITheme.GREEN))
	if state == "locked":
		var names := []
		for req in d.req:
			if Game.tree_rank(req) <= 0:
				names.append(String(TreeDB.def(req).name))
		_info.add_child(HubW.wrap(HubW.lbl("REQUIRES  " + ", ".join(names), 9, UITheme.RED)))

	_info.add_child(HubW.spacer(true))
	var bottom := HubW.hbox(6)
	if state == "maxed":
		var l := HubW.lbl("MAXED", 14, col.lightened(0.3))
		bottom.add_child(l)
		bottom.add_child(HubW.spacer())
		bottom.add_child(_shard_row(Game.shards, 11, Color(HubShard.COLOR, 0.8)))
	else:
		var cost := Game.node_cost(id)
		var afford := Game.shards >= cost
		var cv := HubW.vbox(0)
		cv.add_child(HubW.lbl("COST", 8, UITheme.TEXT_DIM))
		cv.add_child(_shard_row(cost, 14, HubShard.COLOR if afford else UITheme.RED))
		bottom.add_child(cv)
		bottom.add_child(HubW.spacer())
		var can := Game.can_buy_node(id)
		var label := "LOCKED" if state == "locked" else ("JACK IN" if id == "core" else ("BUY" if rank == 0 else "UPGRADE"))
		var b := HubW.button(label, func(): pass, 12, col if can else UITheme.TEXT_DIM, can)
		b.custom_minimum_size = Vector2(82, 34)
		b.pressed.connect(func(): _buy(id, b))
		bottom.add_child(b)
	_info.add_child(bottom)


func _effect_line(key: String, text: String, col: Color) -> Control:
	var row := HubW.hbox(6)
	var k := HubW.lbl(key, 8, UITheme.TEXT_DIM)
	k.custom_minimum_size.x = 28
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(k)
	row.add_child(HubW.wrap(HubW.lbl(text, 10, col)))
	return row


func _build_overview() -> void:
	_info.add_child(HubW.lbl("DATA SHARDS", 9, UITheme.TEXT_DIM))
	_info.add_child(_shard_row(Game.shards, 18))
	_info.add_child(HubW.wrap(HubW.lbl("Permanent upgrades for the fixer. Every job pays shards: 1 per fight cleared, a bonus for the boss, and even a wipe leaves a little.", 9, UITheme.TEXT)))
	_info.add_child(HubW.line(Color(HubShard.COLOR, 0.3)))
	for key in ["net", "cred", "biz", "intel"]:
		var b: Dictionary = TreeDB.BRANCHES[key]
		var row := HubW.vbox(0)
		row.add_child(HubW.lbl(String(b.name), 9, b.color))
		row.add_child(HubW.lbl(String(b.blurb), 8, UITheme.TEXT_DIM))
		_info.add_child(row)
	_info.add_child(HubW.spacer(true))
	var n := Game.nodes_affordable()
	var complete := true
	for id in TreeDB.all_ids():
		complete = complete and Game.node_state(id) == "maxed"
	var tip := "%d node%s ready to buy" % [n, "" if n == 1 else "s"] if n > 0 else "Run jobs to earn more shards"
	if complete:
		tip = "Net complete. You own this city."
	_info.add_child(HubW.lbl(tip, 10, UITheme.GREEN if n > 0 else UITheme.TEXT_DIM))


func _buy(id: String, btn: Control) -> void:
	var d := TreeDB.def(id)
	if not Game.node_unlocked(id):
		hub.deny(btn, "Locked. Buy a connected node first.")
		return
	if Game.node_cost(id) < 0:
		return
	if not Game.buy_node(id):
		hub.deny_shards(btn)
		return
	var col := TreeDB.branch_color(id)
	graph.burst(id)
	hub.screen_flash(col, 0.16, 0.3)
	var rank := Game.tree_rank(id)
	var mr := TreeDB.max_rank(id)
	if id == "core":
		hub.toast("Fixer Core online. The net is open.", col)
	elif mr == 1 or rank == mr:
		hub.toast("%s %s" % [d.name, "online" if mr == 1 else "MAXED"], col)
	else:
		hub.toast("%s  rank %d/%d" % [d.name, rank, mr], col)
