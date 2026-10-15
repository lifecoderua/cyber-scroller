class_name CombatSim
extends RefCounted
## Pure combat simulation for a mission (no nodes, no rendering).
##
## World is 1D: every unit has an x along the street (runners walk right, enemies come
## from the right). Flying units only differ visually. The view reads `units`, `ram`,
## `slots` etc. every frame and drains `pop_events()` for juice.
##
## Usage:
##   var sim := CombatSim.new()
##   sim.setup(contract, runner_dicts, deck_active_ids, fixer_stats, seed)
##   sim.step(dt)                      # dt in sim seconds
##   sim.cast(slot, target_id)         # target_id = -1 for untargeted soft
##   sim.extract()                     # only when sim.can_extract()
##
## Events are dictionaries with a "type" key:
##   attack {src, target, ranged, missed}       damage {target, amount, crit, kind, src, color}
##   heal {target, amount, quiet}                miss {target}
##   death {unit}                                loot {unit, amount}
##   cast {slot, soft, target, color}            skill {unit, skill, x, radius, target}
##   telegraph {unit, name, duration, target}    interrupt {unit}
##   cast_fire {unit, target, name}              enrage {unit}
##   status {unit, text, color}                  ice {target}
##   encounter_start {index, boss}               encounter_cleared {index, boss}
##   outcome {outcome}

const WALK_SPEED := 40.0
const FORMATION_GAP := 22.0
const FIRST_ENCOUNTER_GAP := 120.0
const ENCOUNTER_GAP := 260.0
const DEFAULT_SPAWN_AHEAD := 430.0
const ENGAGE_DIST := 205.0  # squad halts when an enemy gets this close to the front runner
const BASE_CRIT := 0.05
const CRIT_MULT := 1.75
const MAX_STEP := 0.05
const DOT_TICK := 0.5
const HEAL_TICK := 1.0
const RANGED_LOCK := 3.0
const BURST_GAP := 0.12
const START_RAM_PCT := 0.6

# --- balance knobs (mission side; data tables stay as in DESIGN.md) ---------------
const ENEMY_HP_MUL := 1.8
const ENEMY_DMG_MUL := 0.85
const BOSS_HP_MUL := 0.5
const BOSS_DMG_MUL := 1.35
const NETRUNNER_FIRST_CAST := 3.0
const BOSS_FIRST_CAST := 6.0

const RUNNER := 0
const ENEMY := 1

const CLASS_ORDER := ["solo", "gunner", "techie", "medtech"]


class Unit:
	extends RefCounted
	var id := 0
	var team := 0
	var kind := ""
	var name := ""
	var seed := 0
	var runner_id := ""
	var max_hp := 1.0
	var hp := 1.0
	var armor := 0.0
	var dmg := 1.0
	var interval := 1.0
	var range := 30.0
	var melee := true
	var speed := 40.0
	var flying := false
	var boss := false
	var bounty := 0
	var crit := 0.0
	var lvl_mul := 1.0
	var x := 0.0
	var lane := 0.0
	var alive := true
	var encounter := -1
	var order := 0
	var target := -1
	var target_lock := 0.0
	var atk_timer := 0.0
	var skill := ""
	var skill_cd := 0.0
	var skill_timer := 0.0
	var burst_left := 0
	var burst_timer := 0.0
	var stun := 0.0
	var taunt_by := -1
	var taunt_t := 0.0
	var shield := 0.0
	var shield_t := 0.0
	var dots: Array = []  # {dps, t, color}
	var hots: Array = []  # {hps, t}
	var dot_tick := DOT_TICK
	var heal_tick := HEAL_TICK
	var haste := 0.0
	var haste_t := 0.0
	var weaken := 0.0
	var weaken_t := 0.0
	var miss := 0.0
	var miss_t := 0.0
	var crit_t := 0.0
	var psycho_t := 0.0
	var cast_def := {}
	var cast_name := ""
	var cast_t := 0.0
	var cast_total := 0.0
	var cast_target := -1
	var cast_cd_timer := 0.0
	var enraged := false
	var moving := false
	var engaged := false
	var stop_jitter := 0.0
	var death_time := 0.0

	func hp_pct() -> float:
		return clampf(hp / max_hp, 0.0, 1.0)

	func is_casting() -> bool:
		return cast_name != ""

	func attack_interval() -> float:
		var h := 1.0 + (haste if haste_t > 0.0 else 0.0)
		if enraged:
			h += float(cast_def.get("enrage_haste", 0.0))
		return interval / h

	func centre_y_offset() -> float:
		return 48.0 if flying else 0.0


var rng := RandomNumberGenerator.new()
var contract := {}
var fixer := {}
var threat := 1
var units: Array = []  # all units, including dead ones (view keeps corpses)
var _by_id := {}
var _next_id := 1
var slots: Array = []  # {id, def, cd_t, charges}
var ram := 0.0
var max_ram := 10.0
var ram_regen := 0.7
var time := 0.0
var anchor := 0.0  # squad formation anchor (front runner target position)
var spawn_ahead := DEFAULT_SPAWN_AHEAD
var encounters: Array = []
var next_encounter := 0
var active_encounter := -1
var encounters_cleared := 0
var next_spawn_x := FIRST_ENCOUNTER_GAP
var kills := 0
var bag := 0
var outcome := ""
var ice_timer := 4.0
var events: Array = []
var casts_made := 0
var interrupts := 0


func setup(p_contract: Dictionary, runners: Array, deck_active: Array, p_fixer: Dictionary, seed := 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	contract = p_contract
	fixer = p_fixer
	threat = int(contract.get("threat", 1))
	encounters = contract.get("encounters", [])
	max_ram = float(fixer.get("max_ram", 10.0))
	ram_regen = float(fixer.get("ram_regen", 0.7))
	ram = max_ram * START_RAM_PCT
	ice_timer = 4.0
	for id in deck_active:
		var d := SoftDB.get_def(id)
		if d.is_empty():
			continue
		slots.append({"id": id, "def": d, "cd_t": 0.0, "charges": int(d.get("charges", 0))})
	# Runners: melee first, then by class order.
	var sorted := runners.duplicate()
	sorted.sort_custom(func(a, b): return CLASS_ORDER.find(a.cls) < CLASS_ORDER.find(b.cls))
	for i in sorted.size():
		_add_runner(sorted[i], i)
	anchor = 0.0
	for u in units:
		u.x = anchor - u.order * FORMATION_GAP


func _add_runner(r: Dictionary, order: int) -> Unit:
	var s := UnitDB.runner_stats(r)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = RUNNER
	u.kind = r.cls
	u.name = r.name
	u.seed = int(r.get("seed", 0))
	u.runner_id = str(r.get("id", ""))
	u.max_hp = s.hp
	u.hp = s.hp
	u.armor = s.armor
	u.dmg = s.dmg
	u.interval = s.interval
	u.range = s.range
	u.melee = s.melee
	u.speed = WALK_SPEED
	u.crit = s.crit
	u.lvl_mul = 1.0 + UnitDB.LEVEL_SCALE * (int(r.get("level", 1)) - 1)
	u.skill = s.skill
	u.skill_cd = s.skill_cd
	u.skill_timer = s.skill_cd * rng.randf_range(0.3, 0.6)
	u.atk_timer = rng.randf_range(0.1, 0.5) * u.interval
	u.order = order
	u.lane = [2.0, -3.0, 5.0, -1.0][order % 4]
	units.append(u)
	_by_id[u.id] = u
	return u


func _add_enemy(kind: String, x: float, enc: int) -> Unit:
	var e := UnitDB.enemy_stats(kind, threat)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = ENEMY
	u.kind = kind
	u.name = e.name
	u.seed = rng.randi() % 1000
	u.boss = e.get("boss", false)
	var hp_mul := ENEMY_HP_MUL * (BOSS_HP_MUL if u.boss else 1.0)
	var dmg_mul := ENEMY_DMG_MUL * (BOSS_DMG_MUL if u.boss else 1.0)
	u.max_hp = round(e.hp * hp_mul)
	u.hp = u.max_hp
	u.armor = e.armor
	u.dmg = e.dmg * dmg_mul
	u.interval = e.interval
	u.range = e.range
	u.melee = e.melee
	u.speed = e.speed
	u.flying = e.get("flying", false)
	u.bounty = int(e.bounty)
	u.x = x
	u.encounter = enc
	u.lane = rng.randf_range(-3.0, 6.0)
	u.stop_jitter = rng.randf_range(0.0, 14.0) if u.melee else rng.randf_range(-30.0, 0.0)
	u.atk_timer = rng.randf_range(0.2, 0.8) * u.interval
	if e.has("cast"):
		u.cast_def = e.duplicate()
		if e.has("cast_damage"):
			u.cast_def.cast_damage = e.cast_damage * dmg_mul
		if e.has("cast_dot"):
			u.cast_def.cast_dot = e.cast_dot * ENEMY_DMG_MUL
		u.cast_cd_timer = (BOSS_FIRST_CAST if u.boss else NETRUNNER_FIRST_CAST + rng.randf_range(0.0, 2.0))
	units.append(u)
	_by_id[u.id] = u
	return u


# --- queries -------------------------------------------------------------

func get_unit(id: int) -> Unit:
	return _by_id.get(id, null)


func runners(alive_only := true) -> Array:
	return units.filter(func(u): return u.team == RUNNER and (u.alive or not alive_only))


func enemies(alive_only := true) -> Array:
	return units.filter(func(u): return u.team == ENEMY and (u.alive or not alive_only))


func front_x() -> float:
	var best := -INF
	for u in units:
		if u.team == RUNNER and u.alive:
			best = maxf(best, u.x)
	return best if best > -INF else anchor


func in_combat() -> bool:
	for u in units:
		if u.team == ENEMY and u.alive:
			return true
	return false


func can_extract() -> bool:
	return outcome == "" and not in_combat()


func total_encounters() -> int:
	return encounters.size()


func downed_ids() -> Array:
	var out := []
	for u in units:
		if u.team == RUNNER and not u.alive:
			out.append(u.runner_id)
	return out


func result() -> Dictionary:
	return {
		"outcome": outcome if outcome != "" else "wiped", "bag": bag, "kills": kills,
		"encounters_cleared": encounters_cleared, "downed": downed_ids(), "duration": time,
	}


func pop_events() -> Array:
	var e := events
	events = []
	return e


func _emit(ev: Dictionary) -> void:
	events.append(ev)


# --- soft ----------------------------------------------------------------

func slot_def(slot: int) -> Dictionary:
	if slot < 0 or slot >= slots.size():
		return {}
	return slots[slot].def


func needs_target(slot: int) -> bool:
	return slot_def(slot).get("target", "none") != "none"


## "" when castable now, otherwise "ram" / "cd" / "charges" / "over" / "target".
func block_reason(slot: int) -> String:
	if outcome != "" or slot < 0 or slot >= slots.size():
		return "over"
	var s: Dictionary = slots[slot]
	var d: Dictionary = s.def
	if int(d.get("charges", 0)) > 0 and s.charges <= 0:
		return "charges"
	if s.cd_t > 0.0:
		return "cd"
	if ram + 0.0001 < float(d.ram):
		return "ram"
	if not _has_any_target(slot):
		return "target"
	return ""


func can_cast(slot: int) -> bool:
	return block_reason(slot) == ""


func _has_any_target(slot: int) -> bool:
	var d := slot_def(slot)
	match d.get("target", "none"):
		"none":
			# Untargeted enemy debuffs need enemies; firewall works any time.
			return d.has("shield") or in_combat()
		_:
			for u in units:
				if is_valid_target(slot, u.id):
					return true
	return false


func is_valid_target(slot: int, id: int) -> bool:
	var d := slot_def(slot)
	var u := get_unit(id)
	if u == null or not u.alive or d.is_empty():
		return false
	match d.get("target", "none"):
		"enemy":
			if u.team != ENEMY:
				return false
			if d.get("no_boss", false) and u.boss:
				return false
			return true
		"ally":
			return u.team == RUNNER
	return false


func cast(slot: int, target_id := -1) -> bool:
	if not can_cast(slot):
		return false
	var s: Dictionary = slots[slot]
	var d: Dictionary = s.def
	var tgt: Unit = null
	if d.target != "none":
		if not is_valid_target(slot, target_id):
			return false
		tgt = get_unit(target_id)
	ram -= float(d.ram)
	s.cd_t = float(d.cd)
	if int(d.get("charges", 0)) > 0:
		s.charges -= 1
	casts_made += 1
	_emit({"type": "cast", "slot": slot, "soft": s.id, "target": target_id, "color": d.color})
	_apply_soft(s.id, d, tgt)
	return true


func _hack_mul() -> float:
	return 1.0 + float(fixer.get("hack_pct", 0.0))


func _apply_soft(id: String, d: Dictionary, t: Unit) -> void:
	var col: Color = d.color
	match id:
		"short_circuit":
			_deal(t, d.damage * _hack_mul(), null, true, "hack", false, col)
			_stun(t, d.stun)
		"nano_patch":
			_heal(t, d.heal, false)
			t.hots.append({"hps": d.hot, "t": d.duration})
		"overclock":
			t.haste = d.haste
			t.haste_t = d.duration
			_emit({"type": "status", "unit": t.id, "text": "OVERCLOCK", "color": col})
		"weapon_glitch":
			t.weaken = d.weaken
			t.weaken_t = d.duration
			_emit({"type": "status", "unit": t.id, "text": "GLITCHED", "color": col})
		"contagion":
			for e in enemies():
				if e == t or absf(e.x - t.x) <= d.radius:
					e.dots.append({"dps": d.dot * _hack_mul(), "t": d.duration, "color": col})
					_emit({"type": "status", "unit": e.id, "text": "INFECTED", "color": col})
		"firewall":
			for r in runners():
				r.shield = d.shield
				r.shield_t = d.duration
		"synapse_burnout":
			var dmg: float = d.damage * _hack_mul()
			if t.hp_pct() < d.execute_pct:
				dmg *= 2.0
			_deal(t, dmg, null, true, "hack", dmg > d.damage * _hack_mul(), col)
		"optics_jam":
			for e in enemies():
				e.miss = d.miss
				e.miss_t = d.duration
				_emit({"type": "status", "unit": e.id, "text": "JAMMED", "color": col})
		"smart_link":
			t.crit_t = d.duration
			_emit({"type": "status", "unit": t.id, "text": "SMART LINK", "color": col})
		"cyberpsychosis":
			t.psycho_t = d.duration
			t.target = -1
			_cancel_cast(t, false)
			_emit({"type": "status", "unit": t.id, "text": "PSYCHO!", "color": col})
		"system_collapse":
			if t.boss:
				_deal(t, d.boss_damage * _hack_mul(), null, true, "hack", true, col)
			else:
				_deal(t, t.hp + t.shield + 1.0, null, true, "hack", true, col)


## A sensible target for autopilot / bots; -1 when none (or untargeted soft).
func suggest_target(slot: int) -> int:
	var d := slot_def(slot)
	var best: Unit = null
	match d.get("target", "none"):
		"enemy":
			# Interrupt casters first, then focus the weakest.
			for e in enemies():
				if not is_valid_target(slot, e.id):
					continue
				if e.is_casting() and d.has("stun"):
					return e.id
				if best == null or e.hp < best.hp:
					best = e
		"ally":
			for r in runners():
				if d.has("heal"):
					if best == null or r.hp_pct() < best.hp_pct():
						best = r
				else:
					if best == null or r.dmg / r.interval > best.dmg / best.interval:
						best = r
	return best.id if best else -1


# --- simulation ------------------------------------------------------------

func step(dt: float) -> void:
	while dt > 0.0 and outcome == "":
		var h := minf(dt, MAX_STEP)
		_tick(h)
		dt -= h


func extract() -> bool:
	if not can_extract():
		return false
	_finish("extracted")
	return true


func _finish(o: String) -> void:
	if outcome != "":
		return
	outcome = o
	_emit({"type": "outcome", "outcome": o})


func _tick(h: float) -> void:
	time += h
	ram = minf(max_ram, ram + ram_regen * h)
	for s in slots:
		s.cd_t = maxf(0.0, s.cd_t - h)
	for u in units:
		if u.alive:
			_tick_status(u, h)
	_check_spawn()
	_move(h)
	for u in units:
		if u.alive:
			_think(u, h)
	_tick_ice(h)
	_tick_autopilot()
	_check_progress()


func _tick_status(u: Unit, h: float) -> void:
	u.stun = maxf(0.0, u.stun - h)
	u.taunt_t = maxf(0.0, u.taunt_t - h)
	u.haste_t = maxf(0.0, u.haste_t - h)
	u.weaken_t = maxf(0.0, u.weaken_t - h)
	u.miss_t = maxf(0.0, u.miss_t - h)
	u.crit_t = maxf(0.0, u.crit_t - h)
	u.psycho_t = maxf(0.0, u.psycho_t - h)
	u.target_lock = maxf(0.0, u.target_lock - h)
	if u.shield_t > 0.0:
		u.shield_t -= h
		if u.shield_t <= 0.0:
			u.shield = 0.0
	# DoTs tick every DOT_TICK.
	if not u.dots.is_empty():
		u.dot_tick -= h
		if u.dot_tick <= 0.0:
			u.dot_tick += DOT_TICK
			var total := 0.0
			var col := Color.WHITE
			for d in u.dots:
				var span := minf(DOT_TICK, d.t)
				total += d.dps * span
				d.t -= DOT_TICK
				col = d.color
			u.dots = u.dots.filter(func(d): return d.t > 0.0)
			if total > 0.0:
				_deal(u, total, null, true, "dot", false, col)
				if not u.alive:
					return
	else:
		u.dot_tick = DOT_TICK
	# HoTs + passive regen tick every HEAL_TICK.
	var regen := float(fixer.get("regen", 0.0)) if u.team == RUNNER else 0.0
	if not u.hots.is_empty() or regen > 0.0:
		u.heal_tick -= h
		if u.heal_tick <= 0.0:
			u.heal_tick += HEAL_TICK
			var amount := regen * HEAL_TICK
			var from_hot := false
			for o in u.hots:
				amount += o.hps * minf(HEAL_TICK, o.t)
				o.t -= HEAL_TICK
				from_hot = true
			u.hots = u.hots.filter(func(o): return o.t > 0.0)
			if amount > 0.0 and u.hp < u.max_hp:
				_heal(u, amount, not from_hot)
	# Telegraphed cast progress.
	if u.is_casting():
		u.cast_t -= h
		if u.cast_t <= 0.0:
			_fire_cast(u)


func _check_spawn() -> void:
	if active_encounter >= 0 or next_encounter >= encounters.size() or outcome != "":
		return
	if anchor < next_spawn_x:
		return
	var idx := next_encounter
	next_encounter += 1
	active_encounter = idx
	var group: Array = encounters[idx]
	var base := front_x() + spawn_ahead
	var boss := false
	var i := 0
	# Boss walks in last, guards first.
	var ordered := group.duplicate()
	ordered.sort_custom(func(a, b): return int(a == "cyberpsycho") < int(b == "cyberpsycho"))
	for kind in ordered:
		var e := _add_enemy(kind, base + i * 20.0 + rng.randf_range(0.0, 10.0), idx)
		boss = boss or e.boss
		i += 1
	_emit({"type": "encounter_start", "index": idx, "boss": boss})


func _check_progress() -> void:
	if outcome != "":
		return
	if runners().is_empty():
		_finish("wiped")
		return
	if active_encounter >= 0:
		for u in units:
			if u.team == ENEMY and u.alive and u.encounter == active_encounter:
				return
		var was_boss := active_encounter == encounters.size() - 1
		_emit({"type": "encounter_cleared", "index": active_encounter, "boss": was_boss})
		encounters_cleared += 1
		active_encounter = -1
		# Regroup: anchor jumps to the front so the squad re-forms while walking on.
		var top := -INF
		for r in runners():
			top = maxf(top, r.x + _formation_offset(r))
		anchor = maxf(anchor, top)
		next_spawn_x = anchor + ENCOUNTER_GAP
		if was_boss:
			_finish("success")


func _formation_offset(r: Unit) -> float:
	var idx := 0
	for o in runners():
		if o.order < r.order:
			idx += 1
	return idx * FORMATION_GAP


func _move(h: float) -> void:
	var foes := enemies()
	var fx := front_x()
	var nearest_foe := INF
	for e in foes:
		nearest_foe = minf(nearest_foe, e.x - fx)
	var advancing := foes.is_empty() or nearest_foe > ENGAGE_DIST
	if advancing:
		anchor += WALK_SPEED * h
	for r in runners():
		r.moving = false
		if r.stun > 0.0:
			continue
		var want := anchor - _formation_offset(r)
		if not advancing:
			var t := get_unit(r.target)
			if t != null and t.alive:
				var dist: float = t.x - r.x
				if dist > r.range:
					want = t.x - r.range + 2.0
				else:
					want = r.x
			else:
				want = r.x
		var dx: float = want - r.x
		if absf(dx) > 0.5:
			var sp := WALK_SPEED * (1.6 if advancing else 1.0)
			r.x += clampf(dx, -sp * h, sp * h)
			r.moving = true
	for e in foes:
		e.moving = false
		if e.stun > 0.0 or e.is_casting():
			continue
		var t := get_unit(e.target)
		if t == null or not t.alive:
			# Walk in until someone is acquired.
			e.x -= e.speed * h
			e.moving = true
			continue
		var stop: float = e.range - 2.0 + e.stop_jitter
		var dist: float = e.x - t.x
		if absf(dist) > stop:
			e.x -= signf(dist) * e.speed * h
			e.moving = true


func _think(u: Unit, h: float) -> void:
	_pick_target(u)
	if u.stun > 0.0 or u.is_casting():
		return
	var t := get_unit(u.target)
	var in_range := t != null and t.alive and absf(t.x - u.x) <= u.range + 4.0
	u.engaged = in_range
	# Enemy telegraphed cast.
	if u.team == ENEMY and not u.cast_def.is_empty() and u.psycho_t <= 0.0:
		if in_range:
			u.cast_cd_timer -= h
		if u.cast_cd_timer <= 0.0 and in_range:
			_start_cast(u)
			return
	# Boss enrage.
	if u.boss and not u.enraged and u.hp_pct() < float(u.cast_def.get("enrage_pct", 0.5)):
		u.enraged = true
		_emit({"type": "enrage", "unit": u.id})
	# Runner innate skill.
	if u.team == RUNNER:
		u.skill_timer -= h
		if u.skill_timer <= 0.0 and _try_skill(u, t, in_range):
			u.skill_timer = u.skill_cd
		if u.burst_left > 0:
			u.burst_timer -= h
			if u.burst_timer <= 0.0:
				u.burst_timer = BURST_GAP
				u.burst_left -= 1
				if in_range:
					_attack(u, t)
	# Auto attack.
	if in_range:
		u.atk_timer -= h
		if u.atk_timer <= 0.0:
			u.atk_timer += u.attack_interval()
			_attack(u, t)
	else:
		u.atk_timer = maxf(u.atk_timer - h, 0.0)


func _pick_target(u: Unit) -> void:
	if u.team == RUNNER:
		var best: Unit = null
		var best_d := INF
		for e in units:
			if e.team != ENEMY or not e.alive:
				continue
			var d := absf(e.x - u.x) + (400.0 if e.psycho_t > 0.0 else 0.0)
			if d < best_d:
				best_d = d
				best = e
		u.target = best.id if best else -1
		return
	# Enemy under Cyberpsychosis attacks its friends.
	if u.psycho_t > 0.0:
		var best: Unit = null
		for e in units:
			if e.team == ENEMY and e.alive and e != u and e.psycho_t <= 0.0:
				if best == null or absf(e.x - u.x) < absf(best.x - u.x):
					best = e
		u.target = best.id if best else -1
		return
	var cur := get_unit(u.target)
	var cur_ok := cur != null and cur.alive and (cur.team == RUNNER or cur.psycho_t > 0.0)
	# Taunt overrides everything.
	if u.taunt_t > 0.0:
		var tb := get_unit(u.taunt_by)
		if tb != null and tb.alive:
			u.target = tb.id
			return
	# Hit back at a psycho'd ally if it is the closest threat.
	for e in units:
		if e.team == ENEMY and e.alive and e != u and e.psycho_t > 0.0 and absf(e.x - u.x) < 60.0:
			u.target = e.id
			return
	var rs := runners()
	if rs.is_empty():
		u.target = -1
		return
	if u.melee:
		var front: Unit = rs[0]
		for r in rs:
			if r.x > front.x:
				front = r
		u.target = front.id
	else:
		if cur_ok and cur.team == RUNNER and u.target_lock > 0.0:
			return
		u.target = rs[rng.randi() % rs.size()].id
		u.target_lock = RANGED_LOCK


func _attack(a: Unit, t: Unit) -> void:
	var ranged := not a.melee
	if a.miss_t > 0.0 and rng.randf() < a.miss:
		_emit({"type": "attack", "src": a.id, "target": t.id, "ranged": ranged, "missed": true})
		_emit({"type": "miss", "target": t.id})
		return
	var crit_chance := a.crit + (BASE_CRIT if a.team == RUNNER else 0.0)
	if a.crit_t > 0.0:
		crit_chance = 1.0
	var crit := rng.randf() < crit_chance
	var amount := a.dmg
	if a.team == RUNNER:
		amount *= 1.0 + float(fixer.get("dmg_pct", 0.0))
	if a.weaken_t > 0.0:
		amount *= 1.0 - a.weaken
	if crit:
		amount *= CRIT_MULT
	_emit({"type": "attack", "src": a.id, "target": t.id, "ranged": ranged, "missed": false})
	_deal(t, amount, a, false, "ranged" if ranged else "melee", crit, Color.WHITE)


func _deal(t: Unit, amount: float, src: Unit, pierce: bool, kind: String, crit: bool, col: Color) -> void:
	if t == null or not t.alive:
		return
	if not pierce:
		amount *= 10.0 / (10.0 + t.armor)
	var absorbed := 0.0
	if t.shield > 0.0:
		absorbed = minf(t.shield, amount)
		t.shield -= absorbed
	var rest := amount - absorbed
	t.hp -= rest
	_emit({"type": "damage", "target": t.id, "amount": amount, "absorbed": absorbed, "crit": crit,
		"kind": kind, "src": src.id if src else -1, "color": col})
	if t.hp <= 0.0:
		_die(t)


func _heal(t: Unit, amount: float, quiet: bool) -> void:
	if not t.alive:
		return
	var real := minf(amount, t.max_hp - t.hp)
	t.hp += real
	if real > 0.0:
		_emit({"type": "heal", "target": t.id, "amount": real, "quiet": quiet})


func _stun(t: Unit, dur: float) -> void:
	if not t.alive:
		return
	t.stun = maxf(t.stun, dur)
	_emit({"type": "status", "unit": t.id, "text": "STUNNED", "color": UITheme.CYAN})
	if t.is_casting():
		_cancel_cast(t, true)


func _die(t: Unit) -> void:
	t.alive = false
	t.hp = 0.0
	t.death_time = time
	t.cast_name = ""
	t.dots = []
	t.hots = []
	t.shield = 0.0
	_emit({"type": "death", "unit": t.id})
	if t.team == ENEMY:
		kills += 1
		var loot := int(round(t.bounty * (1.0 + float(fixer.get("bounty_pct", 0.0)))))
		bag += loot
		ram = minf(max_ram, ram + float(fixer.get("ram_on_kill", 0.0)))
		_emit({"type": "loot", "unit": t.id, "amount": loot})


# --- runner skills ---------------------------------------------------------

func _try_skill(u: Unit, t: Unit, in_range: bool) -> bool:
	match u.skill:
		"gorilla_slam":
			var hit := []
			for e in enemies():
				if absf(e.x - u.x) <= 48.0:
					hit.append(e)
			if hit.is_empty():
				return false
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": u.x, "radius": 48.0, "target": -1})
			for e in hit:
				e.taunt_by = u.id
				e.taunt_t = 4.0
				_deal(e, 30.0 * u.lvl_mul * (1.0 + float(fixer.get("dmg_pct", 0.0))), u, false, "skill", false, UITheme.MAGENTA)
			return true
		"burst_fire":
			if not in_range:
				return false
			u.burst_left = 4
			u.burst_timer = 0.0
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": u.x, "radius": 0.0, "target": t.id})
			return true
		"trauma_kit":
			var low: Unit = null
			for r in runners():
				if r.hp_pct() < 0.85 and (low == null or r.hp_pct() < low.hp_pct()):
					low = r
			if low == null:
				return false
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": low.x, "radius": 0.0, "target": low.id})
			_heal(low, 35.0 * u.lvl_mul, false)
			return true
		"shock_grenade":
			if not in_range:
				return false
			var cx := t.x
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": cx, "radius": 50.0, "target": t.id})
			for e in enemies():
				if absf(e.x - cx) <= 50.0:
					_deal(e, 25.0 * u.lvl_mul * (1.0 + float(fixer.get("dmg_pct", 0.0))), u, false, "skill", false, UITheme.CYAN)
					_stun(e, 1.0)
			return true
	return false


# --- enemy casts -----------------------------------------------------------

func _start_cast(u: Unit) -> void:
	var rs := runners()
	if rs.is_empty():
		return
	var tgt: Unit = rs[rng.randi() % rs.size()]
	if u.cast_def.cast == "berserk_charge":
		tgt = rs[0]
		for r in rs:
			if r.x > tgt.x:
				tgt = r
	u.cast_name = u.cast_def.cast
	u.cast_total = float(u.cast_def.cast_time)
	u.cast_t = u.cast_total
	u.cast_target = tgt.id
	_emit({"type": "telegraph", "unit": u.id, "name": u.cast_name, "duration": u.cast_total, "target": tgt.id})


func _cancel_cast(u: Unit, interrupted: bool) -> void:
	if not u.is_casting():
		return
	u.cast_name = ""
	u.cast_cd_timer = float(u.cast_def.get("cast_cd", 8.0))
	if interrupted:
		interrupts += 1
		_emit({"type": "interrupt", "unit": u.id})


func _fire_cast(u: Unit) -> void:
	var name := u.cast_name
	u.cast_name = ""
	u.cast_cd_timer = float(u.cast_def.get("cast_cd", 8.0))
	var t := get_unit(u.cast_target)
	if t == null or not t.alive:
		var rs := runners()
		if rs.is_empty():
			return
		t = rs[0]
	_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": name})
	match name:
		"overheat":
			t.dots.append({"dps": float(u.cast_def.cast_dot), "t": float(u.cast_def.cast_duration), "color": UITheme.PURPLE})
			_emit({"type": "status", "unit": t.id, "text": "OVERHEAT", "color": UITheme.PURPLE})
		"berserk_charge":
			u.x = t.x + 18.0
			_deal(t, float(u.cast_def.cast_damage), u, true, "charge", true, UITheme.RED)


# --- passives ----------------------------------------------------------------

func _tick_ice(h: float) -> void:
	if not fixer.get("ice_sentry", false):
		return
	ice_timer -= h
	if ice_timer > 0.0:
		return
	var foes := enemies()
	if foes.is_empty():
		ice_timer = 0.0
		return
	var d := SoftDB.get_def("ice_sentry")
	ice_timer = float(d.get("interval", 4.0))
	var t: Unit = foes[rng.randi() % foes.size()]
	_emit({"type": "ice", "target": t.id})
	_deal(t, float(d.get("damage", 12.0)) * _hack_mul(), null, true, "hack", false, d.color)


func _tick_autopilot() -> void:
	if not fixer.get("autopilot", false) or ram < max_ram - 0.001 or not in_combat():
		return
	for i in slots.size():
		if not can_cast(i):
			continue
		if needs_target(i):
			var t := suggest_target(i)
			if t >= 0 and cast(i, t):
				return
		elif cast(i, -1):
			return
