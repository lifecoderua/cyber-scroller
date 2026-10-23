extends VBoxContainer
## STASH tab: gear extracted from won runs. At the next crew draft you may send one piece
## out with the crew; it is lost if that run fails.

var hub: Control
var _list: VBoxContainer
var _head: Label


func setup(h: Control) -> void:
	hub = h
	add_theme_constant_override("separation", 5)
	_head = HubW.lbl("", 13, UITheme.YELLOW)
	add_child(_head)
	add_child(HubW.wrap(HubW.lbl("Win a run to extract gear here. At the crew draft you can send one piece out with the new crew. If that run fails, the gear is gone.", 9, UITheme.TEXT_DIM)))
	_list = HubW.vbox(5)
	add_child(HubW.scroll(_list))


func on_show() -> void:
	HubFx.stagger(_list, 0.04)


func refresh() -> void:
	_head.text = "STASH  %d/%d" % [Game.stash.size(), Game.stash_cap()]
	HubW.clear(_list)
	if Game.stash.is_empty():
		_list.add_child(HubW.lbl("Empty.", 11, UITheme.TEXT_DIM))
	for i in Game.stash.size():
		var ref: String = Game.stash[i]
		var p := HubW.panel(UITheme.YELLOW.darkened(0.5), HubW.PANEL_BG, 1, 6)
		var h := HubW.hbox(6)
		p.add_child(h)
		var b := RunW.item_block(ref, 3)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		var del := HubW.button("DROP", func():
			hub.confirm("DROP %s?" % ItemDB.display_name(ref).to_upper(), "It's gone for good.", "DROP", func(): Game.stash_discard(i)), 9, UITheme.RED)
		del.custom_minimum_size = Vector2(50, 32)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(del)
		_list.add_child(p)
