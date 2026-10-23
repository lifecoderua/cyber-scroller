class_name DiceCombat
extends RefCounted
## Turn-based dice fight (no nodes, no rendering). See docs/DICE_DESIGN.md.
##
## Turn: enemies roll intents -> crew dice roll -> ROLL phase (lock, reroll) -> ASSIGN phase
## (use dice on targets, any order; hacks any time) -> end_turn(): glitches fire, intents
## resolve, burns / turrets tick. Waves follow each other inside one fight; when a wave dies
## mid-turn the next one walks in and rolls its intents right away.
##
## Usage:
##   var c := DiceCombat.new()
##   c.setup(fight, crew_dicts, hacks, daemons, fixer_stats, seed)
##   c.toggle_lock(die) / c.reroll() / c.finish_roll()
##   c.use_die(die, target_id)    # target -1 for untargeted faces
##   c.hack(slot, target)         # target: unit id, or die index for die hacks
##   c.end_turn()
## Events (pop_events) have a "type" key:
##   turn_start {turn}  roll {}  reroll {}  intent {unit}  die_used {die, face, target}
##   damage {target, amount, absorbed, kind, src}  heal {target, amount}  shield {target, amount}
##   death {unit}  loot {unit, amount}  dodge {unit}  stun {unit}  blocked {unit, why}
##   intent_fire {unit, face, target}  hack {ref, target}  overheat {}  trace {amount, reason}
##   wave_start {index, total, boss}  wave_cleared {index}  daemon {ref}  enrage {unit}
##   summon {unit}  outcome {outcome}

const CREW := 0
const ENEMY := 1
const MAX_ENEMIES := 5
const LOW_PCT := 0.4
const UPLOAD_TRACE := 6.0
const TRACE_LIMIT := 100.0


class Unit:
	extends RefCounted
	var id := 0
	var team := 0
	var kind := ""
	var name := ""
	var seed := 0
	var merc_id := ""
	var hp := 1
	var max_hp := 1
	var shield := 0
	var armor := 0
	var alive := true
	var order := 0
	var front_shield := false
	var backline := false
	var flying := false
	var machine := false
	var boss := false
	var bounty := 0
	var affix := ""
	var dmg_plus := 0
	var die: Array = []         # enemy intent faces
	var intent := {}            # current intent face ({} = none)
	var intent_target := -1
	var aim_target := -1        # sniper: next turn snipes this merc
	var stunned := false
	var spoofed := false
	var hijacked := false
	var vuln := 0               # +damage taken per hit this turn (mark, breach)
	var breached := false
	var dodge := false
	var taunt := false
	var firewall := false
	var burns: Array = []       # {v, turns}
	var enraged := false
	var low_fired := false
	var analog := false
	var chrome_load := 0
	var ports: Array = []       # implant port events ("dodge", "knock", "blast")
	var extras := {}            # merc rules from DiceDB.merc_dice (ram_turn, shield_turn...)
	var turret_v := 0
	var turret_turns := 0
	var killed_by := ""

	func hp_pct() -> float:
		return clampf(float(hp) / float(max_hp), 0.0, 1.0)


class Die:
	extends RefCounted
	var index := 0
	var owner := 0              # unit id
	var which := "gear"         # "gear" | "chrome"
	var faces: Array = []
	var face_i := 0
	var locked := false
	var used := false
	var bonus := 0              # overclock pips this turn
	var echoed := false

	func face() -> Dictionary:
		var f: Dictionary = faces[face_i].duplicate()
		if bonus > 0 and int(f.v) > 0:
			f.v = int(f.v) + bonus
		return f


var rng := RandomNumberGenerator.new()
var fight := {}
var fixer := {}
var threat := 1
var units: Array = []
var _by_id := {}
var _next_id := 1
var dice: Array = []
var hacks: Array = []        # chip refs
var daemons: Array = []      # chip refs
var waves: Array = []
var wave := -1
var turn := 0
var phase := "roll"          # "roll" | "assign" | "over"
var ram := 0
var ram_cap := 6
var heat := 0
var heat_cap := 6
var rerolls := 0
var overheated := false      # hacks locked this turn
var overheat_next := false
var focus := 0
var trace := 0.0
var trace_start := 0.0
var outcome := ""
var kills := 0
var fried := 0
var killed_kinds: Array = []
var bag := 0
var interrupts := 0
var revives_left := 0
var events: Array = []


func setup(p_fight: Dictionary, crew: Array, p_hacks: Array, p_daemons: Array, p_fixer: Dictionary, seed := 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	fight = p_fight
	fixer = p_fixer
	threat = int(fight.get("threat", 1))
	waves = fight.get("waves", [])
	hacks = p_hacks.filter(func(r): return r != "")
	daemons = p_daemons.filter(func(r): return r != "")
	trace = float(fixer.get("trace", 0.0))
	trace_start = trace
	revives_left = int(fixer.get("revive", 0))
	var ch: Dictionary = ChipDB.CHASSIS
	ram_cap = int(ch.ram_cap) + int(fixer.get("max_ram", 0))
	heat_cap = int(ch.heat_cap) + int(fixer.get("heat_cap", 0))
	ram = ram_cap if fixer.get("full_ram", false) else int(ch.ram_start) + int(fixer.get("start_ram", 0))
	ram = mini(ram, ram_cap)
	var sorted := crew.duplicate()
	sorted.sort_custom(func(a, b): return int(UnitDB.CLASSES[a.cls].row) < int(UnitDB.CLASSES[b.cls].row))
	for i in sorted.size():
		_add_merc(sorted[i], i)
	_spawn_wave(0)
	_begin_turn()


func _add_merc(m: Dictionary, order: int) -> void:
	var dd := DiceDB.merc_dice(m, fixer)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = CREW
	u.kind = m.cls
	u.name = m.name
	u.seed = int(m.get("seed", 0))
	u.merc_id = str(m.get("id", ""))
	u.max_hp = int(dd.hp)
	u.hp = maxi(1, int(round(dd.hp * clampf(float(m.get("hp_pct", 1.0)), 0.0, 1.0))))
	u.order = order
	u.analog = UnitDB.trait_def(m).get("analog", false)
	u.chrome_load = UnitDB.chrome_load(m)
	u.ports = UnitDB.ports(m)
	u.extras = dd
	units.append(u)
	_by_id[u.id] = u
	for which in ["gear", "chrome"]:
		var d := Die.new()
		d.index = dice.size()
		d.owner = u.id
		d.which = which
		d.faces = dd[which]
		dice.append(d)


func _add_enemy(spec: String, order: int) -> Unit:
	var parts := spec.split(":")
	var kind := parts[0]
	var e := UnitDB.enemy_stats(kind, threat)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = ENEMY
	u.kind = kind
	u.name = e.name
	u.seed = rng.randi() % 1000
	u.affix = parts[1] if parts.size() > 1 else ""
	var hp := int(e.hp) - int(fixer.get("enemy_hp", 0))
	if u.affix == "chromed":
		hp = int(round(hp * 1.5))
	u.max_hp = maxi(1, hp)
	u.hp = u.max_hp
	u.armor = int(e.get("armor", 0))
	u.front_shield = e.get("front_shield", false)
	u.backline = e.get("backline", false)
	u.flying = e.get("flying", false)
	u.machine = e.get("machine", false)
	u.boss = e.get("boss", false)
	u.bounty = int(e.bounty)
	u.dmg_plus = int(e.dmg_plus) + (1 if u.affix == "overclocked" else 0)
	u.die = e.die.map(func(p): return DiceDB.face(p[0], p[1]))
	u.order = order
	units.append(u)
	_by_id[u.id] = u
	return u


func _spawn_wave(i: int) -> void:
	wave = i
	var group: Array = waves[i].duplicate()
	# Backline enemies stand behind the rest.
	group.sort_custom(func(a, b):
		var ba: bool = UnitDB.ENEMIES[String(a).split(":")[0]].get("backline", false)
		var bb: bool = UnitDB.ENEMIES[String(b).split(":")[0]].get("backline", false)
		return int(ba) < int(bb))
	var boss := false
	for k in mini(group.size(), MAX_ENEMIES):
		var u := _add_enemy(String(group[k]), k)
		boss = boss or u.boss
	_emit({"type": "wave_start", "index": i, "total": waves.size(), "boss": boss})
	_daemons("wave", {})


# --- queries ---------------------------------------------------------------------------

func get_unit(id: int) -> Unit:
	return _by_id.get(id, null)


func mercs(alive_only := true) -> Array:
	return units.filter(func(u): return u.team == CREW and (u.alive or not alive_only))


func enemies() -> Array:
	var out := units.filter(func(u): return u.team == ENEMY and u.alive)
	out.sort_custom(func(a, b): return a.order < b.order)
	return out


func crew_ports() -> Array:
	var out := []
	for u in mercs():
		for p in u.ports:
			if not p in out:
				out.append(p)
	return out


func dice_of(u: Unit) -> Array:
	return dice.filter(func(d): return d.owner == u.id)


func live_dice() -> Array:
	return dice.filter(func(d): return get_unit(d.owner).alive)


func total_waves() -> int:
	return waves.size()


func pop_events() -> Array:
	var e := events
	events = []
	return e


func _emit(ev: Dictionary) -> void:
	events.append(ev)


## Enemies a melee face can reach: front enemies (not backline / flying) while any stand.
func melee_targets() -> Array:
	var foes := enemies()
	var front := foes.filter(func(e): return not e.backline and not e.flying)
	if not front.is_empty():
		return front
	return foes.filter(func(e): return not e.flying)


## Unit ids a die can be used on. Untargeted faces return [owner] (tap the die again).
func valid_targets(d: Die) -> Array:
	if phase != "assign" or d.used or not get_unit(d.owner).alive:
		return []
	var f := d.face()
	match DiceDB.target_kind(f):
		"melee":
			return melee_targets().map(func(u): return u.id)
		"enemy":
			return enemies().map(func(u): return u.id)
		"ally":
			return mercs().map(func(u): return u.id)
		_:
			if f.k == "blank":
				return []
			return [d.owner]


func incoming(u: Unit) -> int:
	## Damage this merc takes if the enemies acted now (shields and dodge ignored).
	var n := 0
	var crew := mercs()
	for e in enemies():
		if e.intent.is_empty() or e.stunned or e.spoofed or e.hijacked:
			continue
		var k := String(e.intent.k)
		var v := int(e.intent.v)
		match k:
			"atk", "rush", "shot", "charge", "snipe":
				if e.intent_target == u.id:
					n += v
			"upload":
				if e.intent_target == u.id and not u.firewall and not u.analog:
					n += v
			"blast":
				var t := get_unit(e.intent_target)
				if t != null and absi(crew.find(t) - crew.find(u)) <= 1:
					n += v
			"rampage":
				n += v
	return n


# --- turn flow ----------------------------------------------------------------------------

func _begin_turn() -> void:
	if outcome != "":
		return
	turn += 1
	phase = "roll"
	focus = 0
	overheated = overheat_next
	overheat_next = false
	var ch: Dictionary = ChipDB.CHASSIS
	rerolls = int(ch.rerolls) + int(fixer.get("rerolls", 0))
	var cool := int(ch.heat_cool)
	for ref in _active_daemons():
		var dd := ChipDB.get_def(ref)
		rerolls += int(dd.get("rerolls", 0))
		cool += int(dd.get("cool", 0))
	heat = maxi(0, heat - cool)
	var gain := int(ch.ram_turn)
	for u in mercs():
		gain += int(u.extras.get("ram_turn", 0))
		var st := int(u.extras.get("shield_turn", 0)) + (int(fixer.get("front_shield", 0)) if u == mercs()[0] else 0)
		if st > 0:
			_shield(u, st)
		var ht := int(u.extras.get("heal_turn", 0))
		if ht > 0:
			_heal(u, ht)
	ram = mini(ram_cap, ram + gain)
	for e in enemies():
		if e.affix == "shielded":
			e.shield = maxi(e.shield, 4)
	_roll_intents()
	for d in dice:
		d.locked = false
		d.used = false
		d.bonus = 0
		d.echoed = false
		if get_unit(d.owner).alive:
			d.face_i = rng.randi() % d.faces.size()
	_emit({"type": "turn_start", "turn": turn})
	_emit({"type": "roll"})


func _roll_intents() -> void:
	for e in enemies():
		_roll_intent(e)


func _roll_intent(e: Unit) -> void:
	e.stunned = false
	e.spoofed = false
	e.hijacked = false
	var f: Dictionary
	if e.aim_target >= 0:
		f = DiceDB.face("snipe", 6)
	else:
		f = e.die[rng.randi() % e.die.size()].duplicate()
	if int(f.v) > 0:
		f.v = int(f.v) + e.dmg_plus + (1 if e.enraged else 0)
	e.intent = f
	e.intent_target = _pick_target(e, String(f.k))
	_emit({"type": "intent", "unit": e.id})


func _pick_target(e: Unit, k: String) -> int:
	var crew := mercs()
	if crew.is_empty():
		return -1
	var who := String(UnitDB.INTENTS.get(k, {}).get("who", "none"))
	match who:
		"front":
			return crew[0].id
		"back":
			return crew[crew.size() - 1].id
		"random":
			return crew[rng.randi() % crew.size()].id
		"fixed":
			var t := get_unit(e.aim_target)
			return t.id if t != null and t.alive else crew[rng.randi() % crew.size()].id
		"chrome":
			var best: Unit = null
			for u in crew:
				if u.analog:
					continue
				if best == null or u.chrome_load > best.chrome_load:
					best = u
			return best.id if best else crew[0].id
		"ally":
			var foes := enemies()
			return foes[rng.randi() % foes.size()].id
	return -1


func toggle_lock(d: Die) -> void:
	if phase == "roll" and not d.used:
		d.locked = not d.locked


func reroll() -> bool:
	if phase != "roll" or rerolls <= 0:
		return false
	rerolls -= 1
	for d in live_dice():
		if not d.locked and not d.used:
			d.face_i = rng.randi() % d.faces.size()
	_emit({"type": "reroll"})
	if rerolls <= 0:
		finish_roll()
	return true


func finish_roll() -> void:
	if phase == "roll":
		phase = "assign"


func use_die(d: Die, target := -1) -> bool:
	if phase == "roll":
		finish_roll()
	if phase != "assign" or d.used:
		return false
	var owner := get_unit(d.owner)
	if owner == null or not owner.alive:
		return false
	var valid := valid_targets(d)
	if valid.is_empty():
		return false
	if not target in valid:
		if valid.size() == 1 and valid[0] == d.owner:
			target = d.owner
		else:
			return false
	var f := d.face()
	if focus > 0 and int(f.v) > 0:
		f.v = int(f.v) + focus
		focus = 0
	d.used = true
	_emit({"type": "die_used", "die": d.index, "face": f, "target": target})
	_apply_face(f, owner, get_unit(target))
	_after_action()
	return true


func _apply_face(f: Dictionary, owner: Unit, t: Unit) -> void:
	var v := int(f.v)
	var burn := int(f.get("burn", 0))
	match String(f.k):
		"atk", "shot", "rage":
			_hit(t, v, String(f.k), owner, burn)
			if f.k == "rage":
				_damage_merc(owner, 1, "self", null)
			if f.k == "atk" and v >= 5 and "knock" in owner.ports:
				_daemons("knock", {"enemy": t.id})
		"pierce":
			_hit(t, v, "pierce", owner, burn)
		"cleave":
			var foes := enemies()
			var i := foes.find(t)
			var hit := [t]
			if i > 0:
				hit.append(foes[i - 1])
			if i >= 0 and i < foes.size() - 1:
				hit.append(foes[i + 1])
			for e in hit:
				_hit(e, v, "cleave", owner, burn)
		"slice":
			for e in enemies().slice(0, 3):
				_hit(e, v, "slice", owner, burn)
		"blast":
			for e in enemies():
				_hit(e, v, "blast", owner, burn)
			_daemons("blast", {})
		"shield":
			_shield(t, v)
			_daemons("shield_face", {})
		"heal":
			_heal(t, v)
		"triage":
			for u in mercs():
				_heal(u, v)
		"taunt":
			_shield(owner, v)
			owner.taunt = true
			for e in enemies():
				var who := String(UnitDB.INTENTS.get(String(e.intent.get("k", "blank")), {}).get("who", "none"))
				if who in ["front", "back", "random", "fixed"]:
					e.intent_target = owner.id
			_emit({"type": "status", "unit": owner.id, "text": "TAUNT"})
		"dodge":
			owner.dodge = true
			_emit({"type": "status", "unit": owner.id, "text": "DODGE READY"})
		"mark":
			t.vuln += v
			_emit({"type": "status", "unit": t.id, "text": "MARKED +%d" % v})
		"stun":
			_stun(t)
		"ram":
			_add_ram(v)
		"focus":
			focus += v
		"turret":
			owner.turret_v = maxi(owner.turret_v, v)
			owner.turret_turns = 2
			_emit({"type": "status", "unit": owner.id, "text": "TURRET"})
		"glitch":
			_glitch(v)


func _glitch(v: int) -> void:
	var pool := units.filter(func(u): return u.alive)
	if pool.is_empty():
		return
	var t: Unit = pool[rng.randi() % pool.size()]
	_emit({"type": "status", "unit": t.id, "text": "GLITCH"})
	if t.team == CREW:
		_damage_merc(t, v, "glitch", null)
	else:
		_hit(t, v, "glitch", null, 0)


## Damage to an enemy from the crew / fixer.
func _hit(t: Unit, v: int, kind: String, src: Unit, burn := 0) -> void:
	if t == null or not t.alive:
		return
	var pierce := kind in ["pierce", "hack"]
	if kind == "shot" and t.front_shield and not t.breached:
		_emit({"type": "blocked", "unit": t.id, "why": "front shield"})
		return
	var amount := v + t.vuln
	if not pierce and not t.breached:
		amount = maxi(0, amount - t.armor)
	var absorbed := 0
	if not pierce and t.shield > 0:
		absorbed = mini(t.shield, amount)
		t.shield -= absorbed
	var rest := amount - absorbed
	t.hp -= rest
	_emit({"type": "damage", "target": t.id, "amount": amount, "absorbed": absorbed, "kind": kind, "src": src.id if src else -1})
	if burn > 0 and t.hp > 0:
		t.burns.append({"v": burn, "turns": 2})
	if t.boss and not t.enraged and t.hp * 2 <= t.max_hp and t.hp > 0:
		t.enraged = true
		_emit({"type": "enrage", "unit": t.id})
	if t.hp <= 0:
		t.killed_by = kind
		_kill(t, src)


func _kill(t: Unit, src: Unit) -> void:
	t.alive = false
	t.hp = 0
	t.intent = {}
	kills += 1
	if t.killed_by == "burn":
		fried += 1
	killed_kinds.append(t.kind)
	bag += int(round(t.bounty * (1.0 + float(fixer.get("bounty_pct", 0.0)))))
	_emit({"type": "death", "unit": t.id})
	_emit({"type": "loot", "unit": t.id, "amount": t.bounty})
	if src != null and src.team == CREW:
		_add_ram(int(src.extras.get("ram_on_kill", 0)))
	_add_ram(int(fixer.get("ram_on_kill", 0)))
	_daemons("kill", {})


func _damage_merc(u: Unit, v: int, kind: String, src: Unit) -> void:
	if u == null or not u.alive or v <= 0:
		return
	if u.dodge and kind != "self" and kind != "glitch":
		u.dodge = false
		_emit({"type": "dodge", "unit": u.id})
		_daemons("dodge", {})
		return
	var absorbed := 0
	if u.shield > 0 and kind != "snipe":
		absorbed = mini(u.shield, v)
		u.shield -= absorbed
	var rest := v - absorbed
	u.hp -= rest
	_emit({"type": "damage", "target": u.id, "amount": v, "absorbed": absorbed, "kind": kind, "src": src.id if src else -1})
	if u.hp <= 0:
		if revives_left > 0:
			revives_left -= 1
			u.hp = maxi(1, int(round(u.max_hp * 0.3)))
			_emit({"type": "status", "unit": u.id, "text": "TRAUMA TEAM!"})
			return
		u.alive = false
		u.hp = 0
		u.shield = 0
		_emit({"type": "death", "unit": u.id})
		# Intents aimed at the fallen merc pick a new victim.
		for e in enemies():
			if e.intent_target == u.id and not e.intent.is_empty():
				e.intent_target = _pick_target(e, String(e.intent.k))
		return
	if not u.low_fired and u.hp_pct() < LOW_PCT:
		u.low_fired = true
		_daemons("low", {"merc": u.id})


func _shield(u: Unit, v: int) -> void:
	if u == null or not u.alive or v <= 0:
		return
	u.shield += v
	_emit({"type": "shield", "target": u.id, "amount": v})


func _heal(u: Unit, v: int) -> void:
	if u == null or not u.alive:
		return
	var real := mini(v, u.max_hp - u.hp)
	if real <= 0:
		return
	u.hp += real
	_emit({"type": "heal", "target": u.id, "amount": real})


func _stun(t: Unit) -> void:
	if t == null or not t.alive:
		return
	if not t.intent.is_empty() and t.intent.k != "blank":
		interrupts += 1
	t.stunned = true
	t.aim_target = -1
	_emit({"type": "stun", "unit": t.id})


func _add_ram(n: int) -> void:
	if n > 0:
		ram = mini(ram_cap, ram + n)


func add_trace(amount: float, reason: String) -> void:
	if amount <= 0.0 or outcome != "":
		return
	amount *= 1.0 - clampf(float(fixer.get("trace_pct", 0.0)), 0.0, 0.8)
	trace += amount
	_emit({"type": "trace", "amount": amount, "reason": reason})
	if trace >= TRACE_LIMIT:
		_finish("traced")


## After any crew action: a cleared wave lets the next one in (intents rolled at once).
func _after_action() -> void:
	if outcome != "":
		return
	if mercs().is_empty():
		_finish("wiped")
		return
	if enemies().is_empty():
		_emit({"type": "wave_cleared", "index": wave})
		if wave + 1 >= waves.size():
			_finish("won")
			return
		_spawn_wave(wave + 1)
		_roll_intents()


func _finish(o: String) -> void:
	if outcome != "":
		return
	outcome = o
	phase = "over"
	_emit({"type": "outcome", "outcome": o})


# --- hacks -------------------------------------------------------------------------------

## "" when hack `slot` can run on `target` now, else a reason.
func hack_block(slot: int, target := -1) -> String:
	if phase == "over" or slot < 0 or slot >= hacks.size():
		return "over"
	if overheated:
		return "overheated"
	var d := ChipDB.get_def(hacks[slot])
	if ram < hack_cost(slot):
		return "ram"
	if target < 0 and d.target != "none":
		return ""
	if not _hack_target_ok(d, target):
		return "target"
	return ""


func hack_cost(slot: int) -> int:
	return maxi(1, ChipDB.cost(hacks[slot]) - int(fixer.get("hack_disc", 0)))


func _hack_target_ok(d: Dictionary, target: int) -> bool:
	match String(d.target):
		"enemy":
			var u := get_unit(target)
			return u != null and u.alive and u.team == ENEMY
		"machine":
			var u := get_unit(target)
			return u != null and u.alive and u.team == ENEMY and u.machine and not u.boss
		"ally":
			var u := get_unit(target)
			return u != null and u.alive and u.team == CREW
		"die":
			return target >= 0 and target < dice.size() and not dice[target].used and get_unit(dice[target].owner).alive
		"used_die":
			return target >= 0 and target < dice.size() and dice[target].used and not dice[target].echoed and get_unit(dice[target].owner).alive
	return true


## Valid targets for a hack: unit ids, or die indexes for die hacks.
func hack_targets(slot: int) -> Array:
	var d := ChipDB.get_def(hacks[slot])
	var out := []
	if String(d.target) in ["die", "used_die"]:
		for i in dice.size():
			if _hack_target_ok(d, i):
				out.append(i)
	elif d.target != "none":
		for u in units:
			if _hack_target_ok(d, u.id):
				out.append(u.id)
	return out


func hack(slot: int, target := -1) -> bool:
	if hack_block(slot, target) != "":
		return false
	var d := ChipDB.get_def(hacks[slot])
	if d.target != "none" and not _hack_target_ok(d, target):
		return false
	ram -= hack_cost(slot)
	var pw := int(fixer.get("hack_power", 0))
	var t := get_unit(target) if not String(d.target) in ["die", "used_die"] else null
	match String(d.id):
		"short_circuit":
			_stun(t)
		"spoof":
			t.spoofed = true
			_emit({"type": "status", "unit": t.id, "text": "SPOOFED"})
		"overclock":
			dice[target].bonus += int(d.pips)
		"echo":
			dice[target].used = false
			dice[target].echoed = true
		"breach":
			t.breached = true
			t.shield = 0
			t.vuln += int(d.vuln) + pw
			_emit({"type": "status", "unit": t.id, "text": "BREACHED"})
		"ping":
			_hit(t, int(d.damage) + pw, "hack", null)
		"patch":
			_heal(t, int(d.heal) + pw)
		"firewall":
			_shield(t, int(d.shield) + pw)
			t.firewall = true
		"hijack":
			t.hijacked = true
			_emit({"type": "status", "unit": t.id, "text": "HIJACKED"})
		"bandwidth":
			rerolls += int(d.rerolls)
			if phase == "assign":
				phase = "roll"
	_emit({"type": "hack", "ref": hacks[slot], "target": target})
	add_trace(float(d.get("trace", 0.0)), String(d.name))
	heat += int(d.get("heat", 1))
	if heat >= heat_cap:
		heat = 0
		overheat_next = true
		_emit({"type": "overheat"})
		add_trace(float(ChipDB.CHASSIS.overheat_trace), "overheat")
	_after_action()
	return true


# --- daemons -------------------------------------------------------------------------------

func _active_daemons() -> Array:
	var ports := crew_ports()
	return daemons.filter(func(r): return not ChipDB.is_dark(r, ports))


func _daemons(event: String, ctx: Dictionary) -> void:
	for ref in _active_daemons():
		var d := ChipDB.get_def(ref)
		if String(d.event) != event:
			continue
		match String(d.id):
			"data_siphon", "wave_primer", "static_discharge", "dodge_relay":
				_add_ram(int(d.amount))
			"guardian":
				_shield(get_unit(int(ctx.get("merc", -1))), int(d.amount))
			"ice_sentry":
				var foes := enemies()
				if not foes.is_empty():
					_hit(foes[rng.randi() % foes.size()], int(d.amount), "hack", null)
			"shrapnel_link":
				for e in enemies():
					_hit(e, int(d.amount), "hack", null)
			"recoil_loop":
				_stun(get_unit(int(ctx.get("enemy", -1))))
				_add_ram(int(d.get("amount", 0)))
			_:
				continue
		_emit({"type": "daemon", "ref": ref})


# --- end of turn ---------------------------------------------------------------------------

func end_turn() -> void:
	if outcome != "":
		return
	phase = "resolve"
	# Unused glitch faces fire by themselves.
	for d in live_dice():
		if not d.used and String(d.face().k) == "glitch":
			d.used = true
			_glitch(int(d.face().v))
	if outcome == "":
		for e in enemies():
			if outcome != "":
				break
			if e.alive:
				_resolve_intent(e)
			if mercs().is_empty():
				_finish("wiped")
	if outcome == "":
		_end_effects()
	_after_action()
	if outcome != "":
		return
	for u in units:
		u.shield = 0 if u.team == CREW else u.shield
		u.vuln = 0
		u.breached = false
		u.dodge = false
		u.taunt = false
		u.firewall = false
	_begin_turn()


func _resolve_intent(e: Unit) -> void:
	var f := e.intent
	if f.is_empty() or e.stunned:
		return
	var k := String(f.k)
	var v := int(f.v)
	if (e.spoofed or e.hijacked) and k in ["atk", "rush", "shot", "charge", "snipe", "blast", "upload", "rampage"]:
		var others := enemies().filter(func(o): return o != e)
		if not others.is_empty():
			var o: Unit = others[rng.randi() % others.size()]
			_emit({"type": "intent_fire", "unit": e.id, "face": f, "target": o.id})
			_hit(o, v, "spoof", null)
		return
	var t := get_unit(e.intent_target)
	if t != null and t.team == CREW and not t.alive:
		t = get_unit(_pick_target(e, k))
	_emit({"type": "intent_fire", "unit": e.id, "face": f, "target": t.id if t else -1})
	match k:
		"atk", "rush", "shot", "charge", "snipe":
			_damage_merc(t, v, k, e)
			if k == "snipe":
				e.aim_target = -1
		"blast":
			var crew := mercs()
			var i := crew.find(t)
			for j in range(i - 1, i + 2):
				if j >= 0 and j < crew.size():
					_damage_merc(crew[j], v, "blast", e)
		"upload":
			if t == null:
				return
			if t.firewall or t.analog:
				_emit({"type": "blocked", "unit": t.id, "why": "firewall" if t.firewall else "analog"})
				return
			_damage_merc(t, v, "upload", e)
			add_trace(UPLOAD_TRACE, "netrunner")
		"aim":
			if t != null:
				e.aim_target = t.id
		"guard":
			if t != null and t.alive:
				t.shield += v
				_emit({"type": "shield", "target": t.id, "amount": v})
		"rampage":
			for u in mercs():
				_damage_merc(u, v, "rampage", e)
		"summon":
			if enemies().size() < MAX_ENEMIES:
				var g := _add_enemy("ganger", enemies().size() + 10)
				g.intent = {}
				_emit({"type": "summon", "unit": g.id})


func _end_effects() -> void:
	for e in enemies():
		var total := 0
		for b in e.burns:
			total += int(b.v)
			b.turns -= 1
		e.burns = e.burns.filter(func(b): return b.turns > 0)
		if total > 0:
			_hit(e, total, "burn", null)
	for u in mercs():
		if u.turret_turns > 0:
			u.turret_turns -= 1
			var foes := enemies()
			if not foes.is_empty():
				_emit({"type": "status", "unit": u.id, "text": "TURRET"})
				_hit(foes[0], u.turret_v, "turret", u)
	_daemons("end", {})


func result() -> Dictionary:
	var crew := []
	for u in mercs(false):
		crew.append({"id": u.merc_id, "hp_pct": u.hp_pct() if u.alive else 0.0, "down": not u.alive})
	return {
		"outcome": outcome if outcome != "" else "wiped", "bag": bag, "kills": kills, "fried": fried,
		"killed_kinds": killed_kinds, "crew": crew, "turns": turn, "duration": float(turn),
		"trace": trace, "trace_gain": trace - trace_start, "interrupts": interrupts,
	}
