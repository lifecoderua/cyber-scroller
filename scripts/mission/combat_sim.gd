class_name CombatSim
extends RefCounted
## Pure combat simulation for one fight node (no nodes, no rendering).
##
## World is 1D: every unit has an x along the street (the crew stands on the left in
## formation, enemies arrive from the right in waves). Flying units only differ visually.
## The fixer never fights: all player influence goes through `deck` (DeckEngine), which
## listens to sim events (kills, hits, telegraphs...) and fires payloads back into the sim.
##
## Usage:
##   var sim := CombatSim.new()
##   sim.setup(fight, crew_dicts, threads, fixer_stats, seed)
##   sim.step(dt)                         # dt in sim seconds
##   sim.deck.execute(thread, target_id)  # manual threads (target -1 = thread's own selector)
##
## Events (pop_events) are dictionaries with a "type" key:
##   attack {src, target, ranged, missed}     damage {target, amount, crit, kind, src, color, absorbed}
##   heal {target, amount, quiet}              miss {target} dodge {unit}
##   death {unit, src}                         loot {unit, amount}
##   skill {unit, skill, x, radius, targets}   telegraph {unit, name, duration, target}
##   interrupt {unit, thread}                  cast_fire {unit, target, name, blocked}
##   enrage {unit}  status {unit, text, color} psycho {unit}  spawn {unit}
##   wave_start {index, total, boss}           wave_cleared {index}
##   payload {thread, slot, chip, targets, color}   thread_run {thread}   thread_fail {thread, reason}
##   overheat {}  trace {amount, reason}       outcome {outcome}

const WALK_SPEED := 40.0
const FORMATION_GAP := 26.0
const WAVE_WALK := 70.0          # crew walks this far between waves
const FIRST_WAVE_DELAY := 0.8
const WAVE_DELAY := 1.4
const DEFAULT_SPAWN_AHEAD := 240.0
const ENGAGE_DIST := 200.0       # crew halts when an enemy gets this close to the front merc
const BACKLINE_STAND := 175.0    # backline enemies stop this far from the front merc
const BASE_CRIT := 0.05
const CRIT_MULT := 1.75
const MAX_STEP := 0.05
const DOT_TICK := 0.5
const HEAL_TICK := 1.0
const RANGED_LOCK := 3.0
const REVIVE_PCT := 0.3
const PSYCHO_TIME := 5.0
const STRESS_PER_CHROME := 6.0
const MARK_TIME := 6.0
const MARK_VULN := 0.3
const CHAIN_RANGE := 90.0
const FORK_RANGE := 120.0
const TRACE_LIMIT := 100.0

const MERC := 0
const ENEMY := 1


class Unit:
	extends RefCounted
	var id := 0
	var team := 0
	var kind := ""
	var name := ""
	var seed := 0
	var merc_id := ""
	var row := 0
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
	var machine := false
	var static_unit := false
	var rusher := false
	var backline := false
	var bounty := 0
	var crit := 0.0
	var x := 0.0
	var lane := 0.0
	var alive := true
	var wave := -1
	var order := 0
	var target := -1
	var target_lock := 0.0
	var atk_timer := 0.0
	var attacks := 0
	var skill := ""
	var skill_cd := 0.0
	var skill_timer := 0.0
	var stun := 0.0
	var taunt_by := -1
	var taunt_t := 0.0
	var shield := 0.0
	var shield_t := 0.0
	var firewall := false        # blocks the next enemy quickhack
	var front_shield := 0.0      # Shieldbearer: fraction of gunfire blocked
	var breach_t := 0.0
	var vuln := 0.0
	var mark_t := 0.0
	var mark_ready := false
	var infect_t := 0.0
	var infect_blast := 0.0
	var infect_radius := 0.0
	var dots: Array = []  # {dps, t, color, key}
	var hots: Array = []  # {hps, t}
	var dot_tick := DOT_TICK
	var heal_tick := HEAL_TICK
	var haste := 0.0
	var haste_t := 0.0
	var dr := 0.0
	var dr_t := 0.0
	var psycho_t := 0.0
	var stress := 0.0
	var hijack_t := 0.0
	var life_t := -1.0           # summoned turret lifetime
	var owner := -1
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
	var body := 0.0
	var death_time := 0.0
	var affix := ""
	var stats := {}              # merc rule stats (UnitDB.merc_stats)
	var dodge_timer := 0.0
	var emergency_used := false
	var killed_by := ""

	func hp_pct() -> float:
		return clampf(hp / max_hp, 0.0, 1.0)

	func is_casting() -> bool:
		return cast_name != ""

	## Which side the unit fights for right now (hijacked machines switch sides).
	func side() -> int:
		if team == ENEMY and hijack_t > 0.0:
			return MERC
		return team

	func attack_interval() -> float:
		var h := 1.0 + (haste if haste_t > 0.0 else 0.0)
		if enraged:
			h += float(cast_def.get("enrage_haste", 0.0))
		if psycho_t > 0.0:
			h += 0.5
		return interval / h

	func ports() -> Array:
		var out := []
		if stats.get("dodge_cd", 0.0) > 0.0:
			out.append("dodge")
		if int(stats.get("knock_every", 0)) > 0:
			out.append("knock")
		if int(stats.get("blast_every", 0)) > 0:
			out.append("blast")
		return out


var rng := RandomNumberGenerator.new()
var fight := {}
var fixer := {}
var threat := 1
var units: Array = []
var _by_id := {}
var _next_id := 1
var deck: DeckEngine
var time := 0.0
var anchor := 0.0
var spawn_ahead := DEFAULT_SPAWN_AHEAD
var waves: Array = []
var wave := -1             # index of the active wave, -1 between waves
var next_wave := 0
var wave_timer := FIRST_WAVE_DELAY
var walk_target := 0.0
var kills := 0
var fried_kills := 0
var killed_kinds: Array = []
var bag := 0
var outcome := ""
var events: Array = []
var interrupts := 0
var revives_left := 0
var trace := 0.0           # run Trace, live (starts at the run's value)
var trace_start := 0.0


func setup(p_fight: Dictionary, crew: Array, threads: Array, p_fixer: Dictionary, seed := 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	fight = p_fight
	fixer = p_fixer
	threat = int(fight.get("threat", 1))
	waves = fight.get("waves", [])
	trace = float(fixer.get("trace", 0.0))
	trace_start = trace
	revives_left = int(fixer.get("revive", 0))
	var sorted := crew.duplicate()
	sorted.sort_custom(func(a, b): return int(UnitDB.CLASSES[a.cls].row) < int(UnitDB.CLASSES[b.cls].row))
	for i in sorted.size():
		_add_merc(sorted[i], i)
	anchor = 0.0
	walk_target = 0.0
	for u in units:
		u.x = anchor - u.order * FORMATION_GAP
	deck = DeckEngine.new()
	deck.setup(self, threads, fixer)


func _add_merc(m: Dictionary, order: int) -> Unit:
	var s := UnitDB.merc_stats(m, fixer)
	s["chrome_load"] = UnitDB.chrome_load(m)
	s["chrome_over"] = maxi(0, UnitDB.chrome_load(m) - UnitDB.chrome_cap(m))
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = MERC
	u.kind = m.cls
	u.name = m.name
	u.seed = int(m.get("seed", 0))
	u.merc_id = str(m.get("id", ""))
	u.row = int(UnitDB.CLASSES[m.cls].row)
	u.stats = s
	u.max_hp = s.hp
	u.hp = maxf(1.0, s.hp * clampf(float(m.get("hp_pct", 1.0)), 0.0, 1.0))
	u.armor = s.armor
	u.dmg = s.dmg
	u.interval = s.interval
	u.range = s.range
	u.melee = s.melee
	u.speed = WALK_SPEED
	u.crit = s.crit
	u.dr = s.dr
	u.skill = s.skill
	u.skill_cd = s.skill_cd
	u.skill_timer = s.skill_cd * rng.randf_range(0.35, 0.6)
	u.atk_timer = rng.randf_range(0.1, 0.5) * u.interval
	u.order = order
	u.lane = [2.0, -3.0, 5.0, -1.0][order % 4]
	units.append(u)
	_by_id[u.id] = u
	return u


func _add_enemy(spec: String, x: float, w: int) -> Unit:
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
	u.boss = e.get("boss", false)
	u.machine = e.get("machine", false)
	u.static_unit = e.get("static", false)
	u.rusher = e.get("rusher", false)
	u.backline = e.get("backline", false)
	u.front_shield = float(e.get("front_shield", 0.0))
	var hp_mul := 1.0 - clampf(float(fixer.get("enemy_hp_pct", 0.0)), 0.0, 0.5)
	u.affix = parts[1] if parts.size() > 1 else ""
	if u.affix == "chromed":
		hp_mul *= 1.4
	u.max_hp = round(e.hp * hp_mul)
	u.hp = u.max_hp
	u.armor = e.armor
	u.dmg = e.dmg
	u.interval = e.interval
	u.range = e.range
	u.melee = e.melee
	u.speed = e.speed
	u.flying = e.get("flying", false)
	u.bounty = int(e.bounty)
	u.x = x
	u.wave = w
	u.lane = rng.randf_range(-3.0, 6.0)
	u.body = 22.0 if u.boss else 0.0
	if u.melee:
		u.range += rng.randf_range(0.0, 14.0)
	else:
		u.stop_jitter = rng.randf_range(-24.0, 0.0)
	u.atk_timer = rng.randf_range(0.2, 0.8) * u.interval
	if e.has("cast"):
		u.cast_def = e.duplicate()
		u.cast_cd_timer = float(e.get("first_cast", 3.0)) + rng.randf_range(0.0, 1.5)
	if u.affix == "shielded":
		u.shield = 60.0 * (1.0 + 0.15 * (threat - 1))
		u.shield_t = 999.0
	elif u.affix == "overclocked":
		u.interval *= 0.7
		if not u.cast_def.is_empty():
			u.cast_def.cast_time = float(u.cast_def.cast_time) * 0.7
			u.cast_def.cast_cd = float(u.cast_def.cast_cd) * 0.7
	units.append(u)
	_by_id[u.id] = u
	_emit({"type": "spawn", "unit": u.id})
	return u


## Techie's Deploy: a chrome ally the deck can target.
func _add_turret(owner: Unit) -> Unit:
	var t := UnitDB.TURRET
	var mul := 1.6 if owner.stats.get("perk", "") == "twin_turret" else 1.0
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = MERC
	u.kind = "turret_ally"
	u.name = "Turret"
	u.machine = true
	u.static_unit = true
	u.max_hp = t.hp * mul
	u.hp = u.max_hp
	u.armor = t.armor
	u.dmg = t.dmg * mul * (1.0 + float(fixer.get("dmg_pct", 0.0)))
	u.interval = t.interval
	u.range = t.range
	u.melee = false
	u.speed = 0.0
	u.life_t = t.life
	u.owner = owner.id
	u.order = 99
	u.row = 1
	u.x = front_x() - 12.0
	u.lane = 7.0
	units.append(u)
	_by_id[u.id] = u
	_emit({"type": "spawn", "unit": u.id})
	return u


# --- queries -------------------------------------------------------------------

func get_unit(id: int) -> Unit:
	return _by_id.get(id, null)


## Living crew mercs (no summons).
func mercs(alive_only := true) -> Array:
	return units.filter(func(u): return u.team == MERC and u.merc_id != "" and (u.alive or not alive_only))


## Everyone fighting for the crew right now (mercs, turrets, hijacked machines).
func allies() -> Array:
	return units.filter(func(u): return u.alive and u.side() == MERC)


## Living hostile enemies (hijacked machines excluded).
func enemies() -> Array:
	return units.filter(func(u): return u.alive and u.side() == ENEMY)


func front_x() -> float:
	var best := -INF
	for u in units:
		if u.team == MERC and u.merc_id != "" and u.alive:
			best = maxf(best, u.x)
	return best if best > -INF else anchor


func in_combat() -> bool:
	for u in units:
		if u.alive and u.side() == ENEMY:
			return true
	return false


func total_waves() -> int:
	return waves.size()


func crew_ports() -> Array:
	var out := []
	for u in mercs():
		for p in u.ports():
			if not p in out:
				out.append(p)
	return out


func result() -> Dictionary:
	var crew := []
	for u in mercs(false):
		crew.append({"id": u.merc_id, "hp_pct": u.hp_pct() if u.alive else 0.0, "down": not u.alive})
	return {
		"outcome": outcome if outcome != "" else "wiped", "bag": bag, "kills": kills,
		"fried": fried_kills, "killed_kinds": killed_kinds, "waves_cleared": maxi(0, next_wave - (1 if wave >= 0 else 0)),
		"crew": crew, "duration": time, "trace": trace, "trace_gain": trace - trace_start,
		"interrupts": interrupts,
	}


func pop_events() -> Array:
	var e := events
	events = []
	return e


func _emit(ev: Dictionary) -> void:
	events.append(ev)


# --- deck hooks ------------------------------------------------------------------

## Picks a target for a selector. ctx: {merc, enemy, x}. -1 when nothing fits.
func select(pick: String, ctx: Dictionary) -> int:
	var foes := enemies()
	var fx := front_x()
	match pick:
		"front":
			var best: Unit = null
			for e in foes:
				if best == null or e.x < best.x:
					best = e
			return best.id if best else -1
		"weakest":
			var best: Unit = null
			for e in foes:
				if best == null or e.hp_pct() < best.hp_pct():
					best = e
			return best.id if best else -1
		"telegraph":
			var best: Unit = null
			for e in foes:
				if e.is_casting() and (best == null or e.cast_t < best.cast_t):
					best = e
			return best.id if best else -1
		"back":
			var best: Unit = null
			for e in foes:
				if best == null or absf(e.x - fx) > absf(best.x - fx):
					best = e
			return best.id if best else -1
		"machine":
			var best: Unit = null
			for e in foes:
				if e.machine and not e.boss and (best == null or e.x < best.x):
					best = e
			return best.id if best else -1
		"self":
			var m := get_unit(int(ctx.get("merc", -1)))
			return m.id if m != null and m.alive else -1
		"ally_low":
			var best: Unit = null
			for a in allies():
				if a.psycho_t > 0.0:
					continue
				if best == null or a.hp_pct() < best.hp_pct():
					best = a
			return best.id if best else -1
	return -1


## Valid target for a payload of `team` ("enemy" | "ally").
func is_payload_target(team: String, id: int, machine_only := false) -> bool:
	var u := get_unit(id)
	if u == null or not u.alive:
		return false
	if team == "enemy":
		return u.side() == ENEMY and (not machine_only or (u.machine and not u.boss))
	return u.side() == MERC and u.psycho_t <= 0.0


## Nearest other units of the same side around `u` (for Fork / Chain).
func neighbours(u: Unit, exclude: Array, max_dist: float, n: int) -> Array:
	var pool := units.filter(func(o): return o.alive and o.side() == u.side() and not o.id in exclude and absf(o.x - u.x) <= max_dist)
	pool.sort_custom(func(a, b): return absf(a.x - u.x) < absf(b.x - u.x))
	return pool.slice(0, n)


func add_trace(amount: float, reason: String) -> void:
	if amount <= 0.0 or outcome != "":
		return
	amount *= 1.0 - clampf(float(fixer.get("trace_pct", 0.0)), 0.0, 0.8)
	trace += amount
	_emit({"type": "trace", "amount": amount, "reason": reason})
	if trace >= TRACE_LIMIT:
		_finish("traced")


# --- payload effects (called by DeckEngine) --------------------------------------------

func hack_damage(t: Unit, amount: float, col: Color) -> void:
	if t.mark_t > 0.0:
		amount *= 1.0 + MARK_VULN
	_deal(t, amount, null, true, "hack", false, col)


func apply_stun(t: Unit, dur: float, thread := -1) -> void:
	if not t.alive:
		return
	t.stun = maxf(t.stun, dur)
	_emit({"type": "status", "unit": t.id, "text": "STUNNED", "color": UITheme.CYAN})
	if t.is_casting():
		_cancel_cast(t, true, thread)


func interrupt(t: Unit, thread := -1) -> void:
	if t.is_casting():
		_cancel_cast(t, true, thread)


func knockback(t: Unit, dist: float) -> void:
	if t.static_unit or t.boss:
		return
	t.x += dist if t.side() == ENEMY else -dist


func add_dot(t: Unit, dps: float, dur: float, col: Color, key := "") -> void:
	if key != "":
		for d in t.dots:
			if d.get("key", "") == key:
				d.dps = maxf(d.dps, dps)
				d.t = maxf(d.t, dur)
				return
	t.dots.append({"dps": dps, "t": dur, "color": col, "key": key})


func apply_breach(t: Unit, vuln: float, dur: float) -> void:
	t.breach_t = maxf(t.breach_t, dur)
	t.vuln = maxf(t.vuln, vuln)
	if t.shield > 0.0 and t.team == ENEMY:
		t.shield = 0.0
	_emit({"type": "status", "unit": t.id, "text": "BREACHED", "color": Color("ffe066")})


func apply_infect(t: Unit, dur: float, blast: float, radius: float) -> void:
	t.infect_t = maxf(t.infect_t, dur)
	t.infect_blast = maxf(t.infect_blast, blast)
	t.infect_radius = radius
	_emit({"type": "status", "unit": t.id, "text": "INFECTED", "color": Color("9bff3d")})


func apply_hijack(t: Unit, dur: float) -> void:
	t.hijack_t = maxf(t.hijack_t, dur)
	t.target = -1
	_cancel_cast(t, false)
	_emit({"type": "status", "unit": t.id, "text": "HIJACKED", "color": Color("ff6ad5")})


func heal(t: Unit, amount: float, quiet := false) -> void:
	_heal(t, amount, quiet)


func apply_shield(t: Unit, amount: float, dur: float, firewall_block: bool) -> void:
	t.shield = maxf(t.shield, amount)
	t.shield_t = maxf(t.shield_t, dur)
	if firewall_block:
		t.firewall = true


func apply_haste(t: Unit, amount: float, dur: float) -> void:
	t.haste = maxf(t.haste if t.haste_t > 0.0 else 0.0, amount)
	t.haste_t = maxf(t.haste_t, dur)
	_emit({"type": "status", "unit": t.id, "text": "OVERDRIVE", "color": UITheme.YELLOW})


# --- simulation --------------------------------------------------------------------------

func step(dt: float) -> void:
	while dt > 0.0 and outcome == "":
		var h := minf(dt, MAX_STEP)
		_tick(h)
		dt -= h


func _finish(o: String) -> void:
	if outcome != "":
		return
	outcome = o
	_emit({"type": "outcome", "outcome": o})


func _tick(h: float) -> void:
	time += h
	for u in units:
		if u.alive:
			_tick_status(u, h)
	_check_waves(h)
	_move(h)
	for u in units:
		if u.alive:
			_think(u, h)
	deck.tick(h)
	_check_progress()


func _tick_status(u: Unit, h: float) -> void:
	u.stun = maxf(0.0, u.stun - h)
	u.taunt_t = maxf(0.0, u.taunt_t - h)
	u.haste_t = maxf(0.0, u.haste_t - h)
	u.dr_t = maxf(0.0, u.dr_t - h)
	u.mark_t = maxf(0.0, u.mark_t - h)
	u.infect_t = maxf(0.0, u.infect_t - h)
	u.target_lock = maxf(0.0, u.target_lock - h)
	u.dodge_timer = maxf(0.0, u.dodge_timer - h)
	if u.psycho_t > 0.0:
		u.psycho_t -= h
		if u.psycho_t <= 0.0:
			u.target = -1
	if u.breach_t > 0.0:
		u.breach_t -= h
		if u.breach_t <= 0.0:
			u.vuln = 0.0
	if u.hijack_t > 0.0:
		u.hijack_t -= h
		if u.hijack_t <= 0.0:
			u.target = -1
			_emit({"type": "status", "unit": u.id, "text": "LINK LOST", "color": UITheme.TEXT_DIM})
	if u.life_t > 0.0:
		u.life_t -= h
		if u.life_t <= 0.0:
			_die(u, null)
			return
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
				total += d.dps * minf(DOT_TICK, d.t)
				d.t -= DOT_TICK
				col = d.color
			u.dots = u.dots.filter(func(d): return d.t > 0.0)
			if total > 0.0:
				_deal(u, total, null, true, "dot", false, col)
				if not u.alive:
					return
	else:
		u.dot_tick = DOT_TICK
	# HoTs + regen tick every HEAL_TICK.
	var regen := float(u.stats.get("regen", 0.0))
	if u.team == MERC and wave < 0 and outcome == "":
		regen += u.max_hp * 0.02
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
	if u.is_casting():
		u.cast_t -= h
		if u.cast_t <= 0.0:
			_fire_cast(u)


func _check_waves(h: float) -> void:
	if wave >= 0 or next_wave >= waves.size() or outcome != "":
		return
	wave_timer -= h
	if wave_timer > 0.0:
		return
	wave = next_wave
	next_wave += 1
	var group: Array = waves[wave]
	var base := front_x() + spawn_ahead
	var boss := false
	var ordered := group.duplicate()
	ordered.sort_custom(func(a, b): return int(String(a).begins_with("cyberpsycho")) < int(String(b).begins_with("cyberpsycho")))
	var i := 0
	for spec in ordered:
		var kind := String(spec).split(":")[0]
		var x := base + i * 18.0 + rng.randf_range(0.0, 10.0)
		if UnitDB.ENEMIES[kind].get("static", false):
			x = front_x() + 190.0 + rng.randf_range(-8.0, 8.0)
		var e := _add_enemy(String(spec), x, wave)
		boss = boss or e.boss
		i += 1
	for m in mercs():
		var ws := float(m.stats.get("wave_shield", 0.0))
		if ws > 0.0:
			apply_shield(m, ws, 12.0, false)
	_emit({"type": "wave_start", "index": wave, "total": waves.size(), "boss": boss})
	deck.on_event("on_wave", {})


func _check_progress() -> void:
	if outcome != "":
		return
	if mercs().is_empty():
		_finish("wiped")
		return
	if wave >= 0 and not in_combat():
		# Hijacked machines burn out when their side has nobody left.
		for u in units:
			if u.alive and u.team == ENEMY:
				_die(u, null)
		_emit({"type": "wave_cleared", "index": wave})
		wave = -1
		wave_timer = WAVE_DELAY
		walk_target = anchor + WAVE_WALK
		if next_wave >= waves.size():
			_finish("won")


func _formation_offset(r: Unit) -> float:
	var idx := 0
	for o in mercs():
		if o.order < r.order:
			idx += 1
	return idx * FORMATION_GAP


func _move(h: float) -> void:
	var foes := enemies()
	var fx := front_x()
	var nearest := INF
	for e in foes:
		nearest = minf(nearest, e.x - fx)
	var advancing := foes.is_empty() or nearest > ENGAGE_DIST
	if advancing and anchor < walk_target:
		anchor = minf(walk_target, anchor + WALK_SPEED * h)
	for r in units:
		if not r.alive or r.side() != MERC or r.team != MERC or r.static_unit:
			continue
		r.moving = false
		if r.stun > 0.0:
			continue
		var want := anchor - _formation_offset(r)
		if not advancing or r.psycho_t > 0.0:
			var t := get_unit(r.target)
			if t != null and t.alive and r.melee:
				var dist: float = absf(t.x - r.x) - t.body - r.body
				if dist > r.range:
					want = t.x - signf(t.x - r.x) * (t.body + r.body + r.range - 2.0)
				else:
					want = r.x
			else:
				want = r.x if not advancing else want
		var dx: float = want - r.x
		if absf(dx) > 0.5:
			var sp := WALK_SPEED * (1.6 if advancing else 1.0)
			r.x += clampf(dx, -sp * h, sp * h)
			r.moving = true
	for e in units:
		if not e.alive or e.team != ENEMY:
			continue
		e.moving = false
		if e.stun > 0.0 or e.is_casting() or e.static_unit:
			continue
		var t := get_unit(e.target)
		if t == null or not t.alive:
			if e.side() == ENEMY:
				e.x -= e.speed * h
				e.moving = true
			continue
		var stop: float = e.range - 2.0 + e.stop_jitter
		var dist: float = e.x - t.x
		var close_enough: bool = absf(dist) - t.body - e.body <= stop
		if e.backline and e.side() == ENEMY and e.x - fx <= BACKLINE_STAND:
			close_enough = true
		if not close_enough:
			e.x -= signf(dist) * e.speed * h
			e.moving = true


func _think(u: Unit, h: float) -> void:
	_pick_target(u)
	if u.stun > 0.0 or u.is_casting():
		return
	var t := get_unit(u.target)
	var in_range := t != null and t.alive and absf(t.x - u.x) - t.body - u.body <= u.range + 4.0
	u.engaged = in_range
	if u.team == ENEMY and u.side() == ENEMY and not u.cast_def.is_empty() and u.psycho_t <= 0.0:
		u.cast_cd_timer -= h
		if u.cast_cd_timer <= 0.0 and (in_range or u.backline):
			_start_cast(u)
			return
	if u.boss and not u.enraged and u.hp_pct() < float(u.cast_def.get("enrage_pct", 0.5)):
		u.enraged = true
		_emit({"type": "enrage", "unit": u.id})
	if u.team == MERC and u.merc_id != "" and u.psycho_t <= 0.0:
		u.skill_timer -= h
		if u.skill_timer <= 0.0 and _try_skill(u, t, in_range):
			u.skill_timer = u.skill_cd
	if in_range:
		u.atk_timer -= h
		if u.atk_timer <= 0.0:
			u.atk_timer += u.attack_interval()
			_attack(u, t)
	else:
		u.atk_timer = maxf(u.atk_timer - h, 0.0)


func _nearest(u: Unit, pool: Array) -> Unit:
	var best: Unit = null
	for o in pool:
		if o == u:
			continue
		if best == null or absf(o.x - u.x) < absf(best.x - u.x):
			best = o
	return best


func _pick_target(u: Unit) -> void:
	# Cyberpsycho mercs attack the nearest unit on either side.
	if u.psycho_t > 0.0:
		var all := units.filter(func(o): return o.alive and o != u)
		var n := _nearest(u, all)
		u.target = n.id if n else -1
		return
	if u.side() == MERC:
		var foes := enemies()
		var best := _nearest(u, foes)
		# Snipers prefer backline threats and casters.
		if u.kind == "sniper":
			for e in foes:
				if e.is_casting() or e.backline:
					best = e
					break
		u.target = best.id if best else -1
		return
	var cur := get_unit(u.target)
	var cur_ok := cur != null and cur.alive and cur.side() == MERC
	if u.taunt_t > 0.0:
		var tb := get_unit(u.taunt_by)
		if tb != null and tb.alive:
			u.target = tb.id
			return
	# Hit back at a psycho merc if it is close.
	for o in units:
		if o.alive and o.psycho_t > 0.0 and o.team == MERC and absf(o.x - u.x) < 50.0:
			u.target = o.id
			return
	var rs := allies()
	if rs.is_empty():
		u.target = -1
		return
	if u.rusher:
		var back: Unit = rs[0]
		for r in rs:
			if r.x < back.x:
				back = r
		u.target = back.id
	elif u.melee:
		var front: Unit = rs[0]
		for r in rs:
			if r.x > front.x:
				front = r
		u.target = front.id
	else:
		if cur_ok and u.target_lock > 0.0:
			return
		u.target = rs[rng.randi() % rs.size()].id
		u.target_lock = RANGED_LOCK


func _attack(a: Unit, t: Unit) -> void:
	var ranged := not a.melee
	if t.team == MERC and t.dodge_timer <= 0.0 and float(t.stats.get("dodge_cd", 0.0)) > 0.0 and t.alive:
		t.dodge_timer = float(t.stats.dodge_cd)
		_emit({"type": "attack", "src": a.id, "target": t.id, "ranged": ranged, "missed": true})
		_emit({"type": "dodge", "unit": t.id})
		deck.on_event("on_dodge", {"merc": t.id, "enemy": a.id})
		return
	a.attacks += 1
	var crit_chance := a.crit + (BASE_CRIT if a.team == MERC else 0.0)
	var amount := a.dmg
	var pierce_shield: bool = a.stats.get("pierce", false)
	if a.mark_ready:
		a.mark_ready = false
		crit_chance = 1.0
		amount *= 2.5 / CRIT_MULT
		pierce_shield = true
		t.mark_t = MARK_TIME
		_emit({"type": "status", "unit": t.id, "text": "MARKED", "color": UITheme.YELLOW})
	if a.psycho_t > 0.0:
		amount *= 2.0
	if a.team == MERC and a.hp_pct() < 0.5:
		amount *= 1.0 + float(a.stats.get("low_dmg", 0.0))
	var crit := rng.randf() < crit_chance
	if crit:
		amount *= CRIT_MULT
	# Frontal shield: blocks gunfire coming from the front (crew side).
	if ranged and t.front_shield > 0.0 and t.breach_t <= 0.0 and not pierce_shield and a.side() != t.side():
		amount *= 1.0 - t.front_shield
		_emit({"type": "status", "unit": t.id, "text": "BLOCKED", "color": UITheme.TEXT_DIM})
	_emit({"type": "attack", "src": a.id, "target": t.id, "ranged": ranged, "missed": false})
	_deal(t, amount, a, false, "ranged" if ranged else "melee", crit, Color.WHITE)
	if a.team == MERC and a.merc_id != "":
		var cleave := int(a.stats.get("cleave", 0))
		if cleave > 0:
			for o in neighbours(t, [t.id], 26.0, cleave):
				_deal(o, amount * 0.6, a, false, "melee", false, Color.WHITE)
		var bh := float(a.stats.get("burn_on_hit", 0.0))
		if bh > 0.0 and t.alive:
			add_dot(t, bh, 3.0, Color("ff9f1c"), "katana")
		var ke := int(a.stats.get("knock_every", 0))
		if ke > 0 and a.attacks % ke == 0 and t.alive:
			knockback(t, 20.0)
			_emit({"type": "status", "unit": t.id, "text": "KNOCKBACK", "color": UITheme.MAGENTA})
			deck.on_event("on_knock", {"merc": a.id, "enemy": t.id})
		var be := int(a.stats.get("blast_every", 0))
		if be > 0 and a.attacks % be == 0:
			var cx := t.x
			_emit({"type": "skill", "unit": a.id, "skill": "blast", "x": cx, "radius": 40.0, "targets": [t.id]})
			for e in enemies():
				if absf(e.x - cx) <= 40.0:
					_deal(e, 25.0 * (1.0 + float(fixer.get("dmg_pct", 0.0))), a, false, "skill", false, Color("ff9f1c"))
			deck.on_event("on_blast", {"merc": a.id, "enemy": t.id})


func _deal(t: Unit, amount: float, src: Unit, pierce: bool, kind: String, crit: bool, col: Color) -> void:
	if t == null or not t.alive:
		return
	if not pierce:
		var arm := 0.0 if t.breach_t > 0.0 else t.armor
		amount *= 10.0 / (10.0 + arm)
	amount *= 1.0 + t.vuln
	if t.team == MERC:
		var red := t.dr + (0.5 if t.dr_t > 0.0 else 0.0)
		amount *= 1.0 - clampf(red, 0.0, 0.8)
	var absorbed := 0.0
	if t.shield > 0.0:
		absorbed = minf(t.shield, amount)
		t.shield -= absorbed
	var rest := amount - absorbed
	t.hp -= rest
	_emit({"type": "damage", "target": t.id, "amount": amount, "absorbed": absorbed, "crit": crit,
		"kind": kind, "src": src.id if src else -1, "color": col})
	if t.team == MERC and t.merc_id != "" and src != null and kind != "dot":
		_add_stress(t)
	if t.hp <= 0.0:
		t.killed_by = kind
		_die(t, src)
		return
	if t.team == MERC and t.merc_id != "":
		if not t.emergency_used and float(t.stats.get("emergency_heal", 0.0)) > 0.0 and t.hp_pct() < 0.35:
			t.emergency_used = true
			_heal(t, float(t.stats.emergency_heal), false)
			_emit({"type": "status", "unit": t.id, "text": "BIOMONITOR", "color": UITheme.GREEN})
		if kind != "dot" and src != null:
			deck.on_event("on_hit", {"merc": t.id, "enemy": src.id})
		deck.on_hp(t)


func _add_stress(t: Unit) -> void:
	if t.stats.get("loyal", false) or t.psycho_t > 0.0:
		return
	var over := float(t.stats.get("chrome_over", 0.0))
	if over <= 0.0:
		return
	t.stress += over * STRESS_PER_CHROME * float(t.stats.get("stress_mul", 1.0))
	if t.stress >= UnitDB.STRESS_MAX:
		t.stress = 0.0
		t.psycho_t = PSYCHO_TIME
		t.target = -1
		_emit({"type": "psycho", "unit": t.id})
		_emit({"type": "status", "unit": t.id, "text": "CYBERPSYCHOSIS!", "color": UITheme.RED})


func _heal(t: Unit, amount: float, quiet: bool) -> void:
	if not t.alive:
		return
	var real := minf(amount, t.max_hp - t.hp)
	t.hp += real
	if real > 0.0:
		_emit({"type": "heal", "target": t.id, "amount": real, "quiet": quiet})
		if t.team == MERC:
			deck.on_hp(t)


func _die(t: Unit, src: Unit) -> void:
	if t.team == MERC and t.merc_id != "" and revives_left > 0:
		revives_left -= 1
		t.hp = 0.0
		t.dots = []
		t.stun = 0.0
		_heal(t, t.max_hp * REVIVE_PCT, false)
		_emit({"type": "status", "unit": t.id, "text": "TRAUMA TEAM!", "color": UITheme.GREEN})
		return
	var was_hostile := t.side() == ENEMY
	t.alive = false
	t.hp = 0.0
	t.death_time = time
	t.cast_name = ""
	t.dots = []
	t.hots = []
	t.shield = 0.0
	_emit({"type": "death", "unit": t.id, "src": src.id if src else -1})
	if t.team != ENEMY:
		return
	kills += 1
	if t.killed_by == "dot":
		fried_kills += 1
	killed_kinds.append(t.kind)
	var loot := int(round(t.bounty * (1.0 + float(fixer.get("bounty_pct", 0.0)))))
	bag += loot
	_emit({"type": "loot", "unit": t.id, "amount": loot})
	if src != null and src.team == MERC:
		deck.add_ram(float(src.stats.get("ram_on_kill", 0.0)))
	deck.add_ram(float(fixer.get("ram_on_kill", 0.0)))
	if t.infect_t > 0.0:
		_burst_infection(t)
	if was_hostile:
		deck.on_event("on_kill", {"merc": src.id if src != null and src.team == MERC else -1, "x": t.x, "enemy": t.id})


## Contagion: the corpse bursts and passes its burn / breach to enemies nearby.
func _burst_infection(t: Unit) -> void:
	var col := Color("9bff3d")
	_emit({"type": "skill", "unit": t.id, "skill": "contagion", "x": t.x, "radius": t.infect_radius, "targets": []})
	for e in enemies():
		if absf(e.x - t.x) > t.infect_radius:
			continue
		_deal(e, t.infect_blast, null, true, "hack", false, col)
		if not e.alive:
			continue
		add_dot(e, 6.0, 4.0, Color("ff9f1c"), "contagion")
		if t.breach_t > 0.0:
			apply_breach(e, t.vuln, 4.0)


# --- merc signatures -------------------------------------------------------------------

func _sig_mul(u: Unit) -> float:
	var m := 1.0 + float(fixer.get("dmg_pct", 0.0))
	var so := float(u.stats.get("show_off", 0.0))
	if so > 0.0:
		for e in enemies():
			if e.is_casting():
				return m * (1.0 + so)
	return m


func _try_skill(u: Unit, t: Unit, in_range: bool) -> bool:
	var perk := String(u.stats.get("perk", ""))
	match u.skill:
		"sandevistan":
			var foes := enemies()
			if foes.is_empty() or t == null:
				return false
			foes.sort_custom(func(a, b): return absf(a.x - u.x) < absf(b.x - u.x))
			var n := 5 if perk == "blade_dance" else 3
			var hit := foes.slice(0, n)
			var ids := []
			var far := u.x
			for e in hit:
				ids.append(e.id)
				far = maxf(far, e.x)
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": far, "radius": 0.0, "targets": ids})
			for e in hit:
				# The dash goes behind shields.
				_deal(e, u.dmg * 2.0 * _sig_mul(u), u, false, "skill", false, UITheme.MAGENTA)
			deck.on_event("on_sig", {"merc": u.id})
			return true
		"bulwark":
			var near := enemies().filter(func(e): return absf(e.x - u.x) <= 90.0)
			if near.is_empty():
				return false
			var dur := 7.0 if perk == "iron_wall" else 4.0
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": u.x, "radius": 90.0, "targets": []})
			for e in near:
				e.taunt_by = u.id
				e.taunt_t = dur
			u.dr_t = dur
			_emit({"type": "status", "unit": u.id, "text": "BULWARK", "color": Color("ff9f1c")})
			deck.on_event("on_sig", {"merc": u.id})
			return true
		"stim":
			var hurt := allies().filter(func(a): return a.hp_pct() < 0.9 and a.psycho_t <= 0.0)
			if hurt.is_empty():
				return false
			hurt.sort_custom(func(a, b): return a.hp_pct() < b.hp_pct())
			var amount := 40.0 * (1.6 if perk == "field_surgeon" else 1.0) * (1.0 + float(fixer.get("hack_pct", 0.0)) * 0.5)
			var who := hurt.slice(0, 2 if perk == "triage" else 1)
			var ids := []
			for a in who:
				ids.append(a.id)
				_heal(a, amount, false)
				apply_haste(a, 0.3, 3.0)
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": who[0].x, "radius": 0.0, "targets": ids})
			deck.on_event("on_sig", {"merc": u.id})
			return true
		"deploy":
			if not in_combat():
				return false
			for o in units:
				if o.alive and o.kind == "turret_ally" and o.owner == u.id:
					return false
			var tur := _add_turret(u)
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": tur.x, "radius": 0.0, "targets": [tur.id]})
			deck.on_event("on_sig", {"merc": u.id})
			return true
		"mark":
			if not in_range or u.mark_ready:
				return false
			u.mark_ready = true
			_emit({"type": "skill", "unit": u.id, "skill": u.skill, "x": t.x, "radius": 0.0, "targets": [t.id]})
			deck.on_event("on_sig", {"merc": u.id})
			return true
	return false


# --- enemy telegraphs ----------------------------------------------------------------------

func _start_cast(u: Unit) -> void:
	var rs := allies()
	if rs.is_empty():
		return
	var tgt: Unit = rs[rng.randi() % rs.size()]
	match u.cast_def.cast:
		"berserk_charge":
			for r in rs:
				if r.x > tgt.x:
					tgt = r
		"upload":
			# The most chromed non-analog merc: chrome is an interface, both ways.
			var best: Unit = null
			var best_c := -1.0
			for r in mercs():
				if r.stats.get("analog", false):
					continue
				var c := float(r.stats.get("chrome_load", 0.0)) + rng.randf() * 0.5
				if c > best_c:
					best_c = c
					best = r
			if best == null:
				u.cast_cd_timer = float(u.cast_def.cast_cd)
				return
			tgt = best
		"grenade":
			# Aim where the crew is clustered.
			var best_n := -1
			for r in rs:
				var n := 0
				for o in rs:
					if absf(o.x - r.x) <= float(u.cast_def.get("radius", 40.0)):
						n += 1
				if n > best_n:
					best_n = n
					tgt = r
	u.cast_name = u.cast_def.cast
	u.cast_total = float(u.cast_def.cast_time)
	u.cast_t = u.cast_total
	u.cast_target = tgt.id
	_emit({"type": "telegraph", "unit": u.id, "name": u.cast_name, "duration": u.cast_total, "target": tgt.id})
	deck.on_event("on_tele", {"enemy": u.id, "merc": tgt.id})


func _cancel_cast(u: Unit, interrupted: bool, thread := -1) -> void:
	if not u.is_casting():
		return
	u.cast_name = ""
	u.cast_cd_timer = float(u.cast_def.get("cast_cd", 8.0))
	if interrupted:
		interrupts += 1
		_emit({"type": "interrupt", "unit": u.id, "thread": thread})


func _fire_cast(u: Unit) -> void:
	var nm := u.cast_name
	u.cast_name = ""
	u.cast_cd_timer = float(u.cast_def.get("cast_cd", 8.0))
	var t := get_unit(u.cast_target)
	if t == null or not t.alive:
		var rs := allies()
		if rs.is_empty():
			return
		t = rs[0]
	match nm:
		"aim":
			_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": nm, "blocked": false})
			_deal(t, float(u.cast_def.cast_damage), u, true, "snipe", true, UITheme.RED)
		"grenade":
			_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": nm, "blocked": false})
			var cx := t.x
			for r in allies():
				if absf(r.x - cx) <= float(u.cast_def.get("radius", 40.0)):
					_deal(r, float(u.cast_def.cast_damage), u, false, "blast", false, Color("ff9f1c"))
		"upload":
			if t.firewall:
				t.firewall = false
				_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": nm, "blocked": true})
				_emit({"type": "status", "unit": t.id, "text": "FIREWALLED", "color": Color("3d8bff")})
				return
			_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": nm, "blocked": false})
			add_dot(t, float(u.cast_def.cast_dot), float(u.cast_def.cast_duration), UITheme.PURPLE)
			_emit({"type": "status", "unit": t.id, "text": "QUICKHACKED", "color": UITheme.PURPLE})
			add_trace(float(u.cast_def.get("cast_trace", 0.0)), "netrunner")
		"berserk_charge":
			_emit({"type": "cast_fire", "unit": u.id, "target": t.id, "name": nm, "blocked": false})
			u.x = t.x + 18.0 + u.body
			_deal(t, float(u.cast_def.cast_damage), u, true, "charge", true, UITheme.RED)
