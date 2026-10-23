class_name RunState
extends RefCounted
## One contract run: draft a crew, cross a district node map, fight, loot, reach the
## boss. Plain data + rules, no nodes; Game owns the instance and saves it after every
## step (to_dict / from_dict), so a run survives the app being closed between nodes.
##
## Phases: "draft" (pick a crew) -> "map" -> node screens ("loot", "fence", "ripper",
## "subnet", "safehouse", "event") -> "map" ... -> "over" (won / wiped / traced).
## Fights are played in the mission scene: Game.begin_fight() -> finish_fight(result).

const ROWS := 7                 # regular rows; the boss sits on row ROWS
const BASE_LOOT := 3
const SKIP_VALUE := 4           # €$ per unpicked loot option
const SKIP_ALL_BONUS := 6
const PATCH_UP := 0.2           # fraction of max HP healed after each fight
const DOWNED_HP := 0.25
const FIGHT_TRACE := {"fight": 4.0, "elite": 6.0, "boss": 5.0, "ambush": 3.0}
const ALERT_TRACE := 50.0       # from here corp security joins every wave
const START_EDDIES := 40
const DUO_BONUS := 50           # a 2-merc crew comes with extra cash
const STASH_BASE := 4
const SCRAP_FOR_OLD := 8        # €$ for gear replaced or removed
const PRICES := {"treat": 25, "upgrade": 35}
const SUBNET_SCRUB := 18.0
const THEMES := ["street", "clinic", "armory", "server"]
const THEME_NAMES := {"street": "Street", "clinic": "Clinic", "armory": "Armory", "server": "Server room"}
const NODE_INFO := {
	"fight": {"name": "FIGHT", "icon": "X", "color": Color("ff3d81"), "desc": "Waves of enemies, then a loot pick."},
	"elite": {"name": "ELITE", "icon": "!!", "color": Color("ff2a2a"), "desc": "Three waves with affixed elites. Better loot."},
	"cache": {"name": "CACHE", "icon": "$", "color": Color("f9c80e"), "desc": "Loot only. No fight."},
	"ripper": {"name": "RIPPERDOC", "icon": "+", "color": Color("ff6ad5"), "desc": "Treat scars, upgrade gear, remove implants."},
	"fence": {"name": "FENCE", "icon": "€", "color": Color("ffe066"), "desc": "Buy chips and gear. Hire a merc."},
	"subnet": {"name": "SUBNET", "icon": "#", "color": Color("2de2e6"), "desc": "Gain a chip, or scrub your Trace."},
	"safehouse": {"name": "SAFEHOUSE", "icon": "H", "color": Color("4cff8f"), "desc": "Heal the crew, or recompile a chip."},
	"event": {"name": "EVENT", "icon": "?", "color": Color("b388ff"), "desc": "Something's happening. Risk and reward."},
	"boss": {"name": "TARGET", "icon": "B", "color": Color("ff2a2a"), "desc": "The objective. Win this and the job is done."},
}

var rng := RandomNumberGenerator.new()
var contract := {}
var threat := 1
var fixer := {}             # skill tree bonuses at run start (Game.fixer_stats())
var phase := "draft"
var drafts: Array = []      # crew offers: Array[Array[merc]]
var crew: Array = []
var threads: Array = []     # Array[Array[chip ref]], "" = empty slot
var spare: Array = []       # chips not slotted
var trace := 0.0
var eddies := 0
var map: Array = []         # nodes: {id, row, x, type, theme, links, done, event, waves}
var pos := -1               # current node id (-1 = not on the map yet)
var pending := {}           # data for the current node screen
var fights_won := 0
var kills := 0
var outcome := ""
var stash_taken := ""
var seen_events: Array = []
var last_fight := {}        # summary of the last fight for the loot screen


# --- creation ------------------------------------------------------------------------

static func create(p_contract: Dictionary, p_fixer: Dictionary, seed := 0) -> RunState:
	var r := RunState.new()
	if seed != 0:
		r.rng.seed = seed
	else:
		r.rng.randomize()
	r.contract = p_contract
	r.threat = int(p_contract.get("threat", 1))
	r.fixer = p_fixer
	r.eddies = START_EDDIES + int(p_fixer.get("start_eddies", 0))
	var slots := int(ChipDB.CHASSIS.slots) + int(p_fixer.get("slots", 0))
	for row in ChipDB.STARTER_THREADS:
		var t: Array = row.duplicate()
		while t.size() < slots:
			t.append("")
		r.threads.append(t.slice(0, slots))
	r.spare = ChipDB.STARTER_SPARE.duplicate()
	r._make_drafts()
	r._make_map()
	return r


func _make_drafts() -> void:
	drafts = []
	var n := 3 + int(fixer.get("crew_offers", 0))
	var full: bool = float(fixer.get("crew_offers", 0)) > 0.0
	for i in n:
		var size := 2 if i == 1 and not full else 3
		var classes := []
		while classes.size() < size:
			var c := UnitDB.random_class(rng)
			if classes.count(c) < 1 or rng.randf() < 0.15:
				classes.append(c)
		var team := []
		for c in classes:
			var m := UnitDB.make_merc(c, rng)
			if rng.randf() < 0.35:
				var imps := ItemDB.all_ids().filter(func(id): return ItemDB.DEFS[id].slot == "implant" and ItemDB.DEFS[id].rarity != "rare")
				m.implants.append(imps[rng.randi() % imps.size()])
			team.append(m)
		drafts.append(team)


func choose_draft(i: int, stash_item := "", stash_target := -1) -> bool:
	if phase != "draft" or i < 0 or i >= drafts.size():
		return false
	crew = drafts[i]
	drafts = []
	if crew.size() <= 2:
		eddies += DUO_BONUS
	if stash_item != "" and stash_target >= 0 and stash_target < crew.size():
		var m: Dictionary = crew[stash_target]
		if _equip(m, stash_item, -1, false):
			stash_taken = stash_item
	phase = "map"
	return true


# --- map -----------------------------------------------------------------------------

func _make_map() -> void:
	map = []
	var id := 0
	var rows: Array = []
	for row in ROWS:
		var n := 1 if row == 0 else rng.randi_range(2, 3)
		var types := _row_types(row, n)
		var ids := []
		for k in n:
			var node := {"id": id, "row": row, "x": (k + 0.5) / n + rng.randf_range(-0.05, 0.05),
				"type": types[k], "theme": THEMES[rng.randi() % THEMES.size()], "links": [], "done": false,
				"event": "", "waves": []}
			if node.type == "event":
				var ev := EventDB.pick(rng, seen_events)
				node.event = ev.id
				seen_events.append(ev.id)
			map.append(node)
			ids.append(id)
			id += 1
		rows.append(ids)
	var boss := {"id": id, "row": ROWS, "x": 0.5, "type": "boss", "theme": "armory", "links": [], "done": false,
		"event": "", "waves": []}
	map.append(boss)
	rows.append([id])
	seen_events = []
	# Links: every node reaches the closest 1-2 nodes of the next row; nobody is orphaned.
	for r in range(rows.size() - 1):
		var cur: Array = rows[r]
		var nxt: Array = rows[r + 1]
		for a in cur:
			var na: Dictionary = map[a]
			var sorted := nxt.duplicate()
			sorted.sort_custom(func(p, q): return absf(map[p].x - na.x) < absf(map[q].x - na.x))
			na.links.append(sorted[0])
			if sorted.size() > 1 and absf(map[sorted[1]].x - na.x) < 0.42 and rng.randf() < 0.6:
				na.links.append(sorted[1])
		for b in nxt:
			var has := false
			for a in cur:
				has = has or b in map[a].links
			if not has:
				var best: int = cur[0]
				for a in cur:
					if absf(map[a].x - map[b].x) < absf(map[best].x - map[b].x):
						best = a
				map[best].links.append(b)
	for node in map:
		if node.type in ["fight", "elite", "boss"]:
			node.waves = _make_waves(node.type, int(node.row))


func _row_types(row: int, n: int) -> Array:
	if row == 0:
		return ["fight"]
	if row == ROWS - 1:
		var rest := ["safehouse", "ripper", "fence"]
		rest.shuffle()
		return rest.slice(0, n)
	var out := []
	if row == 3:
		out.append("elite")
	if row == 1:
		out.append("fight")
	var weights := {"fight": 4.0, "event": 1.6, "cache": 1.0, "subnet": 1.0}
	if row >= 2:
		weights.merge({"fence": 1.0, "ripper": 0.9, "elite": 0.6})
	if row >= 3:
		weights["safehouse"] = 0.6
	while out.size() < n:
		var t := _weighted(weights)
		if t != "fight" and t in out:
			continue
		out.append(t)
	out.shuffle()
	return out


func _weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]


## Waves for a fight node: Array[Array[enemy spec]] ("kind" or "kind:affix").
func _make_waves(type: String, row: int) -> Array:
	var depth := mini(5, threat + floori(row / 3.0))
	var pool := UnitDB.enemy_pool(depth)
	var n_waves := 2 if row < 3 else 3
	if type == "elite":
		n_waves = 3
	var out := []
	for w in n_waves:
		var size := clampi(2 + floori((row + w) / 3.0) + (1 if threat >= 3 else 0), 2, 4)
		var group := []
		for k in size:
			group.append(pool[rng.randi() % pool.size()])
		# Swarm waves: gangers come in fours.
		if rng.randf() < 0.25:
			group = ["ganger", "ganger", "rusher", "ganger"].slice(0, mini(4, size + 1))
		if type == "elite":
			var aff: Array = UnitDB.AFFIXES.keys()
			group[0] = "%s:%s" % [["netrunner", "esniper", "heavy", "grenadier"][w % 4], aff[rng.randi() % aff.size()]]
		out.append(group)
	if type == "boss":
		out = [["ganger", "gunman", "drone"], ["shield", "netrunner", "rusher"], ["cyberpsycho", "gunman", "ganger"]]
		if threat >= 3:
			out[1].append("esniper")
	return out


func node(id: int) -> Dictionary:
	return map[id] if id >= 0 and id < map.size() else {}


func reachable() -> Array:
	if pos < 0:
		return map.filter(func(n): return n.row == 0).map(func(n): return n.id)
	return node(pos).get("links", []).duplicate()


func current_row() -> int:
	return int(node(pos).get("row", -1))


# --- fights --------------------------------------------------------------------------

## Enter a node. Returns the screen to show: "fight" | "loot" | "fence" | ...
func enter(id: int) -> String:
	if phase != "map" or not id in reachable():
		return ""
	pos = id
	var n := node(id)
	pending = {}
	match n.type:
		"fight", "elite", "boss":
			pending = {"fight": fight_spec(n)}
			trace += FIGHT_TRACE.get(n.type, 2.0) * (1.0 - float(fixer.get("trace_pct", 0.0)))
			phase = "fight"
			if trace >= CombatSim.TRACE_LIMIT:
				_end("traced")
				return "over"
			return "fight"
		"cache":
			pending = {"loot": _loot_options(n, {"killed_kinds": [], "fried": 0, "kills": 0}, true)}
			phase = "loot"
		"fence":
			pending = {"stock": _fence_stock(n)}
			phase = "fence"
		"ripper":
			phase = "ripper"
		"subnet":
			pending = {"chips": _chip_offers(3, "server")}
			phase = "subnet"
		"safehouse":
			phase = "safehouse"
		"event":
			pending = {"event": n.event}
			phase = "event"
	return phase


func fight_spec(n: Dictionary) -> Dictionary:
	var waves: Array = n.waves.duplicate(true)
	if alert():
		for w in waves:
			if w.size() < 5:
				w.append("gunman")
	return {"waves": waves, "threat": threat, "type": n.type, "boss": n.type == "boss",
		"district": contract.get("district", "Neon Row"), "theme": n.theme, "alert": alert()}


## High Trace: corp security is on the way. Every wave gets an extra gunman.
func alert() -> bool:
	return trace >= ALERT_TRACE


## Apply a finished fight (CombatSim.result()).
func finish_fight(res: Dictionary) -> void:
	var n := node(pos)
	kills += int(res.get("kills", 0))
	eddies += int(res.get("bag", 0))
	trace = float(res.get("trace", trace))
	var o := String(res.get("outcome", "wiped"))
	var by_id := {}
	for c in res.get("crew", []):
		by_id[c.id] = c
	for m in crew:
		var c: Dictionary = by_id.get(m.id, {})
		if c.is_empty():
			continue
		if c.down:
			m.scars = int(m.scars) + 1
			m.hp_pct = DOWNED_HP
		else:
			m.hp_pct = minf(1.0, float(c.hp_pct) + PATCH_UP * (1.0 + float(fixer.get("patch_pct", 0.0))))
			m.fights = int(m.fights) + 1
			if int(m.fights) >= UnitDB.PERK_FIGHTS and m.perk == "":
				m.perk_ready = true
	last_fight = {"outcome": o, "bag": int(res.get("bag", 0)), "kills": int(res.get("kills", 0)),
		"trace_gain": float(res.get("trace_gain", 0.0)), "type": n.get("type", "fight"),
		"downed": res.get("crew", []).filter(func(c): return c.down).size(), "duration": float(res.get("duration", 0.0))}
	if o == "wiped" or o == "traced":
		_end(o)
		return
	fights_won += 1
	if n.get("type", "") == "boss":
		n.done = true
		_end("won")
		return
	pending = {"loot": _loot_options(n, res, false)}
	phase = "loot"


func _end(o: String) -> void:
	outcome = o
	phase = "over"
	pending = {}


func abandon() -> void:
	_end("abandoned")


## Leave the current node screen and return to the map.
func complete_node() -> void:
	if pos >= 0:
		node(pos).done = true
	pending = {}
	phase = "map"


# --- loot ----------------------------------------------------------------------------

func loot_count(n: Dictionary) -> int:
	var c := BASE_LOOT + int(fixer.get("loot_options", 0))
	for m in crew:
		c += int(UnitDB.trait_def(m).get("loot", 0))
	if n.get("type", "") == "elite":
		c += 1
	return mini(c, 6)


## Options: {kind: "item" | "chip" | "scrap", ref, source: "SALVAGE" | "SHARD" | "LOCATION", amount}
func _loot_options(n: Dictionary, res: Dictionary, cache: bool) -> Array:
	var count := loot_count(n)
	var kinds: Array = res.get("killed_kinds", [])
	var shard_kills := kinds.filter(func(k): return k in ["netrunner", "drone", "turret"]).size()
	var fried := int(res.get("fried", 0)) >= maxi(1, ceili(int(res.get("kills", 0)) * 0.6))
	var rare_bias := 0.15 if n.get("type", "") == "elite" else 0.0
	var out := []
	var theme: String = n.get("theme", "street")
	if cache:
		for i in count:
			if theme == "server" or i == count - 1:
				out.append({"kind": "chip", "ref": _rand_chip("", rare_bias), "source": "LOCATION"})
			else:
				out.append({"kind": "item", "ref": _rand_item(theme, rare_bias), "source": "LOCATION"})
		return _dedupe(out)
	var n_shard := clampi(1 + mini(shard_kills, 2), 1, count - 1)
	var n_loc := 1 if count >= 4 else 0
	var n_salv := count - n_shard - n_loc
	for i in n_salv:
		if fried and i == 0:
			out.append({"kind": "scrap", "ref": "", "source": "SALVAGE", "amount": 12})
		else:
			out.append({"kind": "item", "ref": _rand_item("armory" if rng.randf() < 0.5 else "street", rare_bias), "source": "SALVAGE"})
	for i in n_shard:
		out.append({"kind": "chip", "ref": _rand_chip("", rare_bias), "source": "SHARD"})
	for i in n_loc:
		if theme == "server":
			out.append({"kind": "chip", "ref": _rand_chip("", rare_bias), "source": "LOCATION"})
		else:
			out.append({"kind": "item", "ref": _rand_item(theme, rare_bias), "source": "LOCATION"})
	return _dedupe(out)


func _dedupe(opts: Array) -> Array:
	var seen := {}
	for o in opts:
		if o.kind == "scrap":
			continue
		var tries := 0
		while seen.has(o.ref) and tries < 8:
			o.ref = _rand_chip("", 0.0) if o.kind == "chip" else _rand_item("", 0.0)
			tries += 1
		seen[o.ref] = true
	return opts


func _rarity(bias: float) -> String:
	var r := rng.randf()
	if r < 0.1 + bias:
		return "rare"
	if r < 0.42 + bias:
		return "uncommon"
	return "common"


func _rand_chip(only_rarity: String, bias: float) -> String:
	var want := only_rarity if only_rarity != "" else _rarity(bias)
	var pool := ChipDB.all_ids().filter(func(id): return ChipDB.DEFS[id].rarity == want and id != "manual")
	if pool.is_empty():
		pool = ChipDB.all_ids()
	return pool[rng.randi() % pool.size()]


func _rand_item(theme: String, bias: float) -> String:
	var want := _rarity(bias)
	var pool := ItemDB.all_ids().filter(func(id): return ItemDB.DEFS[id].rarity == want and (theme == "" or theme in ItemDB.DEFS[id].theme))
	if pool.is_empty():
		pool = ItemDB.ids_for_theme(theme) if theme != "" else ItemDB.all_ids()
	if pool.is_empty():
		pool = ItemDB.all_ids()
	return pool[rng.randi() % pool.size()]


func _chip_offers(n: int, _theme: String) -> Array:
	var out := []
	while out.size() < n:
		var c := _rand_chip("", 0.1)
		if not c in out:
			out.append(c)
	return out


## What equipping `item` on merc i would do: {ok, text, warn, replaces}.
func fit_preview(item: String, i: int) -> Dictionary:
	var m: Dictionary = crew[i]
	var d := ItemDB.get_def(item)
	match String(d.get("slot", "")):
		"weapon", "armor":
			var cur := String(m.get(d.slot, ""))
			return {"ok": true, "text": "replaces " + ItemDB.display_name(cur) if cur != "" else "free slot", "warn": false, "replaces": cur}
		"implant":
			var load := UnitDB.chrome_load(m) + int(d.chrome)
			var over := load > UnitDB.chrome_cap(m)
			var full: bool = m.implants.size() >= UnitDB.sockets(m)
			if UnitDB.sockets(m) == 0:
				return {"ok": false, "text": "no sockets", "warn": true, "replaces": ""}
			var t := "choose implant to replace" if full else "socket free"
			if over and not full:
				t = "OVER CAP %d/%d" % [load, UnitDB.chrome_cap(m)]
			return {"ok": true, "text": t, "warn": over, "replaces": "?" if full else ""}
	return {"ok": false, "text": "", "warn": false, "replaces": ""}


## Equip gear on a merc. replace_index: implant slot to replace (-1 = append).
func _equip(m: Dictionary, item: String, replace_index: int, scrap_old := true) -> bool:
	var d := ItemDB.get_def(item)
	if d.is_empty():
		return false
	match String(d.slot):
		"weapon", "armor":
			if scrap_old and String(m.get(d.slot, "")) != "":
				eddies += SCRAP_FOR_OLD
			m[d.slot] = item
		"implant":
			if replace_index >= 0 and replace_index < m.implants.size():
				m.implants[replace_index] = item
				if scrap_old:
					eddies += SCRAP_FOR_OLD
			elif m.implants.size() < UnitDB.sockets(m):
				m.implants.append(item)
			else:
				return false
	return true


func take_loot(index: int, merc := -1, replace_index := -1) -> bool:
	var opts: Array = pending.get("loot", [])
	if phase != "loot" or index < 0 or index >= opts.size():
		return false
	var o: Dictionary = opts[index]
	match String(o.kind):
		"chip":
			spare.append(o.ref)
		"scrap":
			eddies += int(o.amount)
		"item":
			if merc < 0 or merc >= crew.size() or not _equip(crew[merc], o.ref, replace_index):
				return false
	eddies += int(SKIP_VALUE * (opts.size() - 1) * 0.5)
	complete_node()
	return true


func skip_value() -> int:
	var n: int = pending.get("loot", []).size()
	return int(round((SKIP_VALUE * n + SKIP_ALL_BONUS) * (1.0 + float(fixer.get("skip_pct", 0.0)))))


func skip_loot() -> void:
	eddies += skip_value()
	complete_node()


# --- deck editing ------------------------------------------------------------------

func crew_ports() -> Array:
	var out := []
	for m in crew:
		for p in UnitDB.ports(m):
			if not p in out:
				out.append(p)
	return out


## Put spare chip `spare_index` into a slot; whatever was there goes back to spare.
func place_chip(thread: int, slot: int, spare_index: int) -> bool:
	if thread < 0 or thread >= threads.size() or slot < 0 or slot >= threads[thread].size():
		return false
	if spare_index < 0 or spare_index >= spare.size():
		return false
	var ref: String = spare[spare_index]
	var k := ChipDB.kind(ref)
	if (slot == 0) != (k == "trigger"):
		return false
	spare.remove_at(spare_index)
	var old: String = threads[thread][slot]
	if old != "":
		spare.append(old)
	threads[thread][slot] = ref
	return true


func remove_chip(thread: int, slot: int) -> bool:
	if thread < 0 or thread >= threads.size() or slot < 0 or slot >= threads[thread].size():
		return false
	var old: String = threads[thread][slot]
	if old == "":
		return false
	threads[thread][slot] = ""
	spare.append(old)
	return true


func swap_slots(thread: int, a: int, b: int) -> bool:
	var t: Array = threads[thread]
	if a <= 0 or b <= 0 or a >= t.size() or b >= t.size():
		return false
	var tmp: String = t[a]
	t[a] = t[b]
	t[b] = tmp
	return true


# --- node actions --------------------------------------------------------------------

func price_mul() -> float:
	return 1.0 - clampf(float(fixer.get("fence_disc", 0.0)), 0.0, 0.6)


func _fence_stock(_n: Dictionary) -> Array:
	var out := []
	for c in _chip_offers(3, ""):
		out.append({"kind": "chip", "ref": c, "price": int(round(ChipDB.price(c) * price_mul())), "sold": false})
	for i in 2:
		var it := _rand_item("", 0.1)
		out.append({"kind": "item", "ref": it, "price": int(round(ItemDB.price(it) * price_mul())), "sold": false})
	if crew.size() < 3:
		var m := UnitDB.make_merc(UnitDB.random_class(rng), rng)
		out.append({"kind": "merc", "merc": m, "price": int(round(70 * price_mul())), "sold": false})
	return out


func fence_buy(index: int, merc := -1, replace_index := -1) -> bool:
	var stock: Array = pending.get("stock", [])
	if phase != "fence" or index < 0 or index >= stock.size():
		return false
	var o: Dictionary = stock[index]
	if o.sold or eddies < int(o.price):
		return false
	match String(o.kind):
		"chip":
			spare.append(o.ref)
		"item":
			if merc < 0 or merc >= crew.size() or not _equip(crew[merc], o.ref, replace_index):
				return false
		"merc":
			if crew.size() >= 3:
				return false
			crew.append(o.merc)
	eddies -= int(o.price)
	o.sold = true
	return true


func ripper_price(service: String) -> int:
	return int(round(int(PRICES.get(service, 0)) * price_mul()))


func ripper_treat(i: int) -> bool:
	var m: Dictionary = crew[i]
	var p := ripper_price("treat")
	if phase != "ripper" or int(m.scars) <= 0 or eddies < p:
		return false
	eddies -= p
	m.scars = int(m.scars) - 1
	return true


## slot: "weapon" | "armor" | "implant:<index>"
func ripper_upgrade(i: int, slot: String) -> bool:
	var m: Dictionary = crew[i]
	var p := ripper_price("upgrade")
	if phase != "ripper" or eddies < p:
		return false
	var ref := _slot_ref(m, slot)
	if ref == "" or ItemDB.tier(ref) >= 2:
		return false
	eddies -= p
	_set_slot(m, slot, ItemDB.upgraded(ref))
	return true


func ripper_remove(i: int, implant_index: int) -> bool:
	var m: Dictionary = crew[i]
	if phase != "ripper" or implant_index < 0 or implant_index >= m.implants.size():
		return false
	m.implants.remove_at(implant_index)
	eddies += SCRAP_FOR_OLD
	return true


func _slot_ref(m: Dictionary, slot: String) -> String:
	if slot.begins_with("implant:"):
		var k := int(slot.split(":")[1])
		return m.implants[k] if k >= 0 and k < m.implants.size() else ""
	return String(m.get(slot, ""))


func _set_slot(m: Dictionary, slot: String, ref: String) -> void:
	if slot.begins_with("implant:"):
		m.implants[int(slot.split(":")[1])] = ref
	else:
		m[slot] = ref


func subnet_take(index: int) -> bool:
	var chips: Array = pending.get("chips", [])
	if phase != "subnet" or index < 0 or index >= chips.size():
		return false
	spare.append(chips[index])
	complete_node()
	return true


func subnet_scrub_amount() -> float:
	return SUBNET_SCRUB + float(fixer.get("subnet_bonus", 0.0))


func subnet_scrub() -> void:
	trace = maxf(0.0, trace - subnet_scrub_amount())
	complete_node()


func safehouse_heal() -> void:
	for m in crew:
		m.hp_pct = 1.0
	complete_node()


## Recompile: +1 tier on a chip. where: "spare:<i>" or "thread:<t>:<slot>".
func safehouse_recompile(where: String) -> bool:
	var p := where.split(":")
	if p[0] == "spare":
		var i := int(p[1])
		if i < 0 or i >= spare.size() or ChipDB.tier(spare[i]) >= 2:
			return false
		spare[i] = ChipDB.upgraded(spare[i])
	else:
		var t := int(p[1])
		var s := int(p[2])
		var ref: String = threads[t][s]
		if ref == "" or ChipDB.tier(ref) >= 2:
			return false
		threads[t][s] = ChipDB.upgraded(ref)
	complete_node()
	return true


## Event choice. Returns {text, fight}: a short result line and whether a fight starts.
func event_choose(index: int) -> Dictionary:
	var ev := EventDB.get_event(String(pending.get("event", "")))
	if phase != "event" or ev.is_empty() or index < 0 or index >= ev.choices.size():
		return {}
	var fx: Dictionary = ev.choices[index].fx
	if int(fx.get("eddies", 0)) < 0 and eddies < -int(fx.eddies):
		return {"text": "Not enough eddies.", "fight": false, "denied": true}
	var lines := apply_effects(fx)
	if fx.get("fight", "") != "":
		var n := node(pos)
		n.waves = _make_waves("fight", int(n.row))
		pending = {"fight": fight_spec(n)}
		pending.fight.type = "ambush"
		phase = "fight"
		return {"text": "Ambush!", "fight": true}
	complete_node()
	if trace >= CombatSim.TRACE_LIMIT:
		_end("traced")
	return {"text": " ".join(lines) if not lines.is_empty() else "You move on.", "fight": false}


func apply_effects(fx: Dictionary) -> Array:
	var out := []
	if fx.has("gamble"):
		var g: Dictionary = fx.gamble
		var win := rng.randf() < float(g.p)
		out.append("Lucky!" if win else "It goes wrong.")
		out.append_array(apply_effects(g.win if win else g.lose))
	if fx.has("eddies"):
		eddies = maxi(0, eddies + int(fx.eddies))
		out.append("%+d €$." % int(fx.eddies))
	if fx.has("trace"):
		var t := float(fx.trace)
		if t > 0.0:
			t *= 1.0 - float(fixer.get("trace_pct", 0.0))
		trace = clampf(trace + t, 0.0, 100.0)
		out.append("Trace %+d." % int(round(t)))
	if fx.has("heal_pct"):
		for m in crew:
			m.hp_pct = minf(1.0, float(m.hp_pct) + float(fx.heal_pct))
		out.append("Crew patched up.")
	if fx.has("hurt_pct"):
		var m: Dictionary = crew[rng.randi() % crew.size()]
		m.hp_pct = maxf(0.05, float(m.hp_pct) - float(fx.hurt_pct))
		out.append("%s got hurt." % UnitDB.short_name(m))
	if fx.has("scar"):
		var m: Dictionary = crew[rng.randi() % crew.size()]
		m.scars = int(m.scars) + 1
		out.append("%s has a new scar." % UnitDB.short_name(m))
	if fx.has("unscar"):
		var best: Dictionary = crew[0]
		for m in crew:
			if int(m.scars) > int(best.scars):
				best = m
		if int(best.scars) > 0:
			best.scars = int(best.scars) - 1
			out.append("%s: scar removed." % UnitDB.short_name(best))
		else:
			out.append("Nobody needed it.")
	if fx.has("item"):
		var it := _rand_item(String(fx.item), 0.1)
		var placed := false
		var order := range(crew.size())
		order.shuffle()
		for i in order:
			if fit_preview(it, i).ok and fit_preview(it, i).replaces != "?" and _equip(crew[i], it, -1):
				out.append("%s got %s." % [UnitDB.short_name(crew[i]), ItemDB.display_name(it)])
				placed = true
				break
		if not placed:
			eddies += 15
			out.append("No room for %s: sold for 15 €$." % ItemDB.display_name(it))
	if fx.has("chip"):
		var c := _rand_chip("rare" if fx.chip == "rare" else "", 0.0)
		spare.append(c)
		out.append("New chip: %s." % ChipDB.display_name(c))
	if fx.has("upgrade_chip"):
		var cands := []
		for t in threads.size():
			for s in threads[t].size():
				if threads[t][s] != "" and ChipDB.tier(threads[t][s]) < 2:
					cands.append([t, s])
		if not cands.is_empty():
			var c: Array = cands[rng.randi() % cands.size()]
			threads[c[0]][c[1]] = ChipDB.upgraded(threads[c[0]][c[1]])
			out.append("%s recompiled." % ChipDB.display_name(threads[c[0]][c[1]]))
	return out


# --- perks ---------------------------------------------------------------------------

func perk_pending() -> int:
	for i in crew.size():
		if crew[i].get("perk_ready", false):
			return i
	return -1


func choose_perk(i: int, perk_id: String) -> bool:
	if i < 0 or i >= crew.size():
		return false
	var m: Dictionary = crew[i]
	for p in UnitDB.perk_choices(m):
		if p.id == perk_id:
			m.perk = perk_id
			m.perk_ready = false
			return true
	return false


# --- results ---------------------------------------------------------------------------

## Items the crew carries (candidates for the stash extract).
func crew_items() -> Array:
	var out := []
	for m in crew:
		for ref in [m.get("weapon", ""), m.get("armor", "")] + Array(m.implants):
			if ref != "":
				out.append(ref)
	return out


# --- save ----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"rng_seed": rng.seed, "rng_state": rng.state, "contract": contract, "threat": threat, "fixer": fixer,
		"phase": phase, "drafts": drafts, "crew": crew, "threads": threads, "spare": spare,
		"trace": trace, "eddies": eddies, "map": map, "pos": pos, "pending": pending,
		"fights_won": fights_won, "kills": kills, "outcome": outcome, "stash_taken": stash_taken,
		"last_fight": last_fight,
	}


static func from_dict(d: Dictionary) -> RunState:
	var r := RunState.new()
	r.rng.seed = int(d.get("rng_seed", 1))
	r.rng.state = int(d.get("rng_state", 0))
	r.contract = d.get("contract", {})
	r.threat = int(d.get("threat", 1))
	r.fixer = d.get("fixer", {})
	r.phase = String(d.get("phase", "map"))
	r.drafts = d.get("drafts", [])
	r.crew = d.get("crew", [])
	r.threads = d.get("threads", [])
	r.spare = d.get("spare", [])
	r.trace = float(d.get("trace", 0.0))
	r.eddies = int(d.get("eddies", 0))
	r.map = d.get("map", [])
	r.pos = int(d.get("pos", -1))
	r.pending = d.get("pending", {})
	r.fights_won = int(d.get("fights_won", 0))
	r.kills = int(d.get("kills", 0))
	r.outcome = String(d.get("outcome", ""))
	r.stash_taken = String(d.get("stash_taken", ""))
	r.last_fight = d.get("last_fight", {})
	r._fix_types()
	# A fight interrupted by closing the app restarts from its node.
	return r


## JSON turns ints into floats; normalize what the rules compare as ints.
func _fix_types() -> void:
	for team in drafts + [crew]:
		for m in team:
			_fix_merc(m)
	for n in map:
		n.id = int(n.id)
		n.row = int(n.row)
		n.links = n.links.map(func(x): return int(x))
	if pending.has("stock"):
		for o in pending.stock:
			o.price = int(o.price)
			if o.has("merc"):
				_fix_merc(o.merc)
	if pending.has("loot"):
		for o in pending.loot:
			if o.has("amount"):
				o.amount = int(o.amount)
	if pending.has("fight"):
		pending.fight.threat = int(pending.fight.threat)


static func _fix_merc(m: Dictionary) -> void:
	m.scars = int(m.get("scars", 0))
	m.fights = int(m.get("fights", 0))
	m.seed = int(m.get("seed", 0))
	m.hp_pct = float(m.get("hp_pct", 1.0))
