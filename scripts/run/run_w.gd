class_name RunW
extends RefCounted
## Widget builders for the run screens (mercs, gear, chips, loot cards).

const SOURCE_COLORS := {"SALVAGE": Color("ff9f1c"), "SHARD": Color("2de2e6"), "LOCATION": Color("4cff8f")}


static func hp_bar(m: Dictionary, fixer: Dictionary, w := 90.0) -> MeterBar:
	var s := UnitDB.merc_stats(m, fixer)
	var pct := float(m.get("hp_pct", 1.0))
	var col := UITheme.GREEN if pct > 0.5 else (UITheme.YELLOW if pct > 0.25 else UITheme.RED)
	var b := MeterBar.new("", col, 10)
	b.custom_minimum_size.x = w
	b.set_value(pct, 1.0, "%d/%d" % [int(round(pct * s.hp)), int(s.hp)])
	return b


static func chrome_bar(m: Dictionary, w := 70.0) -> MeterBar:
	var load := UnitDB.chrome_load(m)
	var cap := UnitDB.chrome_cap(m)
	var b := MeterBar.new("CHR", Color("ff6ad5") if load <= cap else UITheme.RED, 10)
	b.custom_minimum_size.x = w
	b.warn = load > cap
	b.set_value(load, cap, "%d/%d" % [load, cap])
	return b


## Compact merc summary: face, name, class, trait, HP, chrome, scars, perk.
static func merc_row(m: Dictionary, fixer: Dictionary, extra: Control = null) -> PanelContainer:
	var c: Dictionary = UnitDB.CLASSES[m.cls]
	var p := HubW.panel(Color(c.color, 0.45), HubW.PANEL_BG, 1, 5)
	var h := HubW.hbox(6)
	p.add_child(h)
	var face := HubW.headshot(m.cls, int(m.seed), 2)
	h.add_child(face)
	var v := HubW.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HubW.hbox(4)
	top.add_child(HubW.clip(HubW.lbl(UnitDB.short_name(m), 12, UITheme.TEXT)))
	top.add_child(HubW.lbl(String(c.name).to_upper(), 9, c.color))
	v.add_child(top)
	var t := UnitDB.trait_def(m)
	var sub := []
	if not t.is_empty():
		sub.append(String(t.name))
	if int(m.scars) > 0:
		sub.append("%d scar%s" % [int(m.scars), "" if int(m.scars) == 1 else "s"])
	if String(m.get("perk", "")) != "":
		sub.append("perk: " + UnitDB.perk_name(m))
	if m.get("perk_ready", false):
		sub.append("PERK READY")
	var subl := HubW.lbl("  ·  ".join(sub) if not sub.is_empty() else "no trait", 8, UITheme.TEXT_DIM)
	if not t.is_empty():
		subl.tooltip_text = String(t.desc)
		subl.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(HubW.clip(subl))
	var bars := HubW.hbox(4)
	bars.add_child(hp_bar(m, fixer, 92))
	bars.add_child(chrome_bar(m, 66))
	v.add_child(bars)
	var gear := []
	for ref in [m.get("weapon", ""), m.get("armor", "")] + Array(m.implants):
		if ref != "":
			gear.append(ItemDB.display_name(ref))
	var gl := HubW.lbl(("GEAR " + ", ".join(gear)) if not gear.is_empty() else "%s, no gear" % c.weapon, 8, UITheme.TEXT_DIM)
	v.add_child(HubW.clip(gl))
	if extra:
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(extra)
	return p


static func item_icon(ref: String, size := 22.0) -> Control:
	var d := ItemDB.get_def(ref)
	var col := ItemDB.slot_color(String(d.get("slot", "")))
	var p := HubW.panel(col, Color(col.darkened(0.75), 0.95), 1, 0)
	p.custom_minimum_size = Vector2(size, size)
	var l := HubW.lbl(String(ItemDB.SLOT_ICONS.get(d.get("slot", ""), "?")), int(size * 0.5), col.lightened(0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Item line: icon, name, slot / chrome / port, rule text.
static func item_block(ref: String, desc_lines := 2) -> HBoxContainer:
	var d := ItemDB.get_def(ref)
	var h := HubW.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(item_icon(ref, 26))
	var v := HubW.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HubW.hbox(4)
	top.add_child(HubW.clip(HubW.lbl(ItemDB.display_name(ref), 11, HubW.rarity_color(String(d.get("rarity", "common"))).lightened(0.2))))
	var tag := String(d.get("slot", "")).to_upper()
	if d.has("chrome"):
		tag += "  %d CHR" % int(d.chrome)
	if d.has("port"):
		tag += "  PORT"
	top.add_child(HubW.lbl(tag, 8, ItemDB.slot_color(String(d.get("slot", "")))))
	v.add_child(top)
	v.add_child(HubW.wrap(HubW.lbl(ItemDB.desc(ref), 9, UITheme.TEXT), desc_lines))
	h.add_child(v)
	return h


static func chip_icon(ref: String, w := 40.0, h := 34.0) -> ChipTile:
	var t := ChipTile.new()
	t.ref = ref
	t.custom_minimum_size = Vector2(w, h)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Chip line: tile, name, kind, RAM, rule text.
static func chip_block(ref: String, desc_lines := 2) -> HBoxContainer:
	var d := ChipDB.get_def(ref)
	var h := HubW.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(chip_icon(ref))
	var v := HubW.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HubW.hbox(4)
	top.add_child(HubW.clip(HubW.lbl(ChipDB.display_name(ref), 11, HubW.rarity_color(String(d.get("rarity", "common"))).lightened(0.2))))
	var tag: String = ChipDB.KIND_NAMES.get(d.get("kind", ""), "")
	if int(d.get("ram", 0)) > 0:
		tag += "  %d RAM" % int(d.ram)
	top.add_child(HubW.lbl(tag, 8, ChipDB.kind_color(String(d.get("kind", "")))))
	v.add_child(top)
	v.add_child(HubW.wrap(HubW.lbl(ChipDB.desc(ref), 9, UITheme.TEXT), desc_lines))
	h.add_child(v)
	return h


## Loot / shop option body (item, chip or scrap).
static func option_block(o: Dictionary) -> Control:
	match String(o.get("kind", "")):
		"chip":
			return chip_block(o.ref)
		"item":
			return item_block(o.ref)
		"scrap":
			var h := HubW.hbox(6)
			h.add_child(HubW.lbl("FRIED", 11, UITheme.TEXT_DIM))
			h.add_child(HubW.wrap(HubW.lbl("Burned-out chrome (burn kills fry implants). +%d €$ as scrap." % int(o.amount), 9, UITheme.TEXT_DIM)))
			return h
	return Control.new()


static func source_tag(source: String) -> Label:
	return HubW.lbl(source, 8, SOURCE_COLORS.get(source, UITheme.TEXT_DIM))


## A tappable card: panel + button overlay. Returns [card, button].
static func card(accent: Color) -> Array:
	var p := HubW.panel(Color(accent, 0.5), HubW.PANEL_BG, 1, 6)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", UITheme.box(Color(accent, 0.06), Color(accent, 0.6)))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(accent, 0.15), accent))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return [p, b]


static func set_selected(p: PanelContainer, accent: Color, on: bool) -> void:
	p.add_theme_stylebox_override("panel", UITheme.box(Color(accent.darkened(0.8), 0.95) if on else HubW.PANEL_BG,
		accent if on else Color(accent, 0.5), 2 if on else 1, 2, 6))
