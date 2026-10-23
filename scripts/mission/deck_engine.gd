class_name DeckEngine
extends RefCounted
## Runs the fixer's cyberdeck inside a CombatSim. See docs/DESIGN.md "Cyberdeck".
##
## Every thread is [trigger, chip, chip, ...]. When the trigger fires and the thread is
## off cooldown, chips run left to right: selectors set the target, modifiers stack onto
## the NEXT payload, payloads fire and consume them. RAM is charged when the first payload
## fires; a selector that finds nothing before that aborts the run for free (gambit-style
## conditions: "[Timer] [Telegraphing] [Short Circuit]" waits for a telegraph).
##
## Resources: RAM (regenerates), Heat (+per payload, decays; at the cap the deck freezes
## for a few seconds and Trace rises), Trace (lives on the sim; 100 = connection burned).

const RETRY := 0.3          # cooldown after a run that found no target
const LOW_REARM := 0.15     # On Low re-arms once HP climbs this far above the threshold
const RUN_FLASH := 0.6      # sim seconds a fired chip stays lit in the HUD

var sim: CombatSim
var threads: Array = []     # {chips, defs, trig, stats, cd, warn, lit: Array[float], fired, waiting, armed}
var ram := 0.0
var max_ram := 12.0
var ram_regen := 1.0
var heat := 0.0
var heat_cap := 8.0
var heat_decay := 1.0
var frozen := 0.0
var power := 1.0            # payload multiplier (skill tree hack_pct)
var runs := 0
var overheats := 0
var _echoes: Array = []     # {t, thread, slot, def, mods, target}
var _wave_repeat := []      # {t, thread}


func setup(p_sim: CombatSim, chip_rows: Array, fx: Dictionary) -> void:
	sim = p_sim
	var ch: Dictionary = ChipDB.CHASSIS
	max_ram = float(ch.max_ram) + float(fx.get("max_ram", 0.0))
	ram_regen = float(ch.ram_regen) * (1.0 + float(fx.get("ram_regen_pct", 0.0)))
	heat_cap = float(ch.heat_cap) + float(fx.get("heat_cap", 0.0))
	heat_decay = float(ch.heat_decay) * (1.0 + float(fx.get("heat_decay_pct", 0.0)))
	power = 1.0 + float(fx.get("hack_pct", 0.0))
	ram = max_ram * (1.0 if fx.get("full_ram", false) else 0.5)
	for m in sim.mercs():
		ram_regen *= 1.0 + float(m.stats.get("ram_regen_pct", 0.0))
	for row in chip_rows:
		var chips: Array = row.duplicate()
		var defs := []
		for ref in chips:
			defs.append(ChipDB.get_def(ref))
		var trig: Dictionary = defs[0] if defs.size() > 0 else {}
		threads.append({
			"chips": chips, "defs": defs, "trig": trig, "stats": ChipDB.thread_stats(chips, fx),
			"cd": 0.5 if trig.get("id", "") == "timer" else 0.0,
			"warn": ChipDB.thread_warning(chips, sim.crew_ports()),
			"lit": defs.map(func(_d): return -10.0), "fired": 0, "waiting": false, "armed": {},
			"last": "",
		})


# --- queries (HUD) -----------------------------------------------------------------

func is_manual(i: int) -> bool:
	return i >= 0 and i < threads.size() and threads[i].trig.get("id", "") == "manual"


## Thread can't do anything: no trigger / payload, or its port merc is gone.
func is_dark(i: int) -> bool:
	var th: Dictionary = threads[i]
	if th.trig.is_empty() or th.trig.get("kind", "") != "trigger" or int(th.stats.payloads) == 0:
		return true
	if th.trig.has("port"):
		return not th.trig.port in sim.crew_ports()
	return false


## "" when a manual thread can run now, else "frozen" | "cd" | "ram" | "dark" | "over".
func block_reason(i: int) -> String:
	if sim.outcome != "" or i < 0 or i >= threads.size():
		return "over"
	if is_dark(i):
		return "dark"
	if frozen > 0.0 and threads[i].trig.get("id", "") != "on_overheat":
		return "frozen"
	if threads[i].cd > 0.0:
		return "cd"
	if ram + 0.001 < float(threads[i].stats.ram):
		return "ram"
	return ""


## Team of the first payload ("enemy" | "ally" | "").
func first_team(i: int) -> String:
	for d in threads[i].defs:
		if d.get("kind", "") == "payload":
			return String(d.team)
	return ""


## Valid manual target for thread i.
func is_valid_target(i: int, id: int) -> bool:
	var team := first_team(i)
	if team == "":
		return false
	var machine := false
	for d in threads[i].defs:
		if d.get("kind", "") == "payload":
			machine = d.get("machine_only", false)
			break
	return sim.is_payload_target(team, id, machine)


func lit(i: int, slot: int) -> float:
	var t: float = threads[i].lit[slot]
	return clampf(1.0 - (sim.time - t) / RUN_FLASH, 0.0, 1.0)


func add_ram(n: float) -> void:
	ram = minf(max_ram, ram + n)


# --- driving ---------------------------------------------------------------------------

func tick(h: float) -> void:
	ram = minf(max_ram, ram + ram_regen * h)
	if frozen > 0.0:
		frozen = maxf(0.0, frozen - h)
	else:
		heat = maxf(0.0, heat - heat_decay * h)
	for th in threads:
		th.cd = maxf(0.0, th.cd - h)
	var fighting := sim.in_combat()
	for i in threads.size():
		var th: Dictionary = threads[i]
		if th.trig.get("id", "") == "timer" and fighting and th.cd <= 0.0:
			_try(i, {})
		if th.trig.get("id", "") == "on_low":
			_rearm_low(i)
	for e in _echoes:
		e.t -= h
	var due := _echoes.filter(func(e): return e.t <= 0.0)
	_echoes = _echoes.filter(func(e): return e.t > 0.0)
	for e in due:
		_fire_payload(e.thread, e.slot, e.def, e.mods, e.target, {}, true)
	for w in _wave_repeat:
		w.t -= h
	var waves_due := _wave_repeat.filter(func(w): return w.t <= 0.0)
	_wave_repeat = _wave_repeat.filter(func(w): return w.t > 0.0)
	for w in waves_due:
		if fighting:
			_try(w.thread, {})


## Sim event -> every thread with that trigger.
func on_event(kind: String, ctx: Dictionary) -> void:
	for i in threads.size():
		var tid: String = threads[i].trig.get("id", "")
		if tid != kind:
			continue
		_try(i, ctx)
		if kind == "on_wave" and threads[i].trig.has("repeat"):
			_wave_repeat.append({"t": float(threads[i].trig.repeat), "thread": i})


## A merc's HP changed: edge-trigger On Low threads.
func on_hp(u: CombatSim.Unit) -> void:
	if not u.alive:
		return
	for i in threads.size():
		var th: Dictionary = threads[i]
		if th.trig.get("id", "") != "on_low":
			continue
		var armed: bool = th.armed.get(u.id, true)
		if armed and u.hp_pct() < float(th.trig.threshold):
			th.armed[u.id] = false
			if not _try(i, {"merc": u.id}):
				th.armed[u.id] = true  # couldn't run (RAM / cooldown): try again on the next hit


func _rearm_low(i: int) -> void:
	var th: Dictionary = threads[i]
	for id in th.armed.keys():
		var u := sim.get_unit(id)
		if u == null or not u.alive:
			th.armed.erase(id)
		elif not th.armed[id] and u.hp_pct() > float(th.trig.threshold) + LOW_REARM:
			th.armed[id] = true


## Manual execute. target_id -1 = use the thread's own selector.
func execute(i: int, target_id := -1) -> bool:
	if not is_manual(i) or block_reason(i) != "":
		return false
	return _run(i, {}, target_id)


func _try(i: int, ctx: Dictionary) -> bool:
	var reason := block_reason(i)
	if reason != "":
		if reason == "ram" and threads[i].trig.get("id", "") != "timer":
			sim._emit({"type": "thread_fail", "thread": i, "reason": "ram"})
		return false
	return _run(i, ctx, -1)


# --- execution -------------------------------------------------------------------------

func _run(i: int, ctx: Dictionary, forced: int) -> bool:
	var th: Dictionary = threads[i]
	var target := -1          # current selection (unit id)
	var mods: Array = []
	var charged := false
	var fired := false
	var forced_left := forced >= 0
	th.lit[0] = sim.time
	for slot in range(1, th.defs.size()):
		var d: Dictionary = th.defs[slot]
		if d.is_empty():
			continue
		match d.kind:
			"selector":
				if forced_left:
					target = forced
					forced_left = false
				else:
					target = sim.select(String(d.pick), ctx)
				if target < 0:
					if not fired:
						th.cd = RETRY
						th.waiting = true
						return false
					break
				th.lit[slot] = sim.time
			"modifier":
				mods.append(d)
				th.lit[slot] = sim.time
			"payload":
				if forced_left:
					target = forced
					forced_left = false
				if not charged:
					charged = true
					ram -= float(th.stats.ram)
				_fire_payload(i, slot, d, mods, target, ctx, false)
				mods = []
				fired = true
	if not fired:
		th.cd = RETRY
		return false
	th.waiting = false
	th.fired += 1
	th.cd = float(th.stats.cycle)
	runs += 1
	sim._emit({"type": "thread_run", "thread": i})
	return true


## Payload with stacked modifiers. `target` may be -1 or of the wrong team: then the
## payload's default applies (front enemy / event's enemy for attacks, event merc or the
## weakest ally for buffs).
func _fire_payload(i: int, slot: int, d: Dictionary, mods: Array, target: int, ctx: Dictionary, is_echo: bool) -> void:
	if sim.outcome != "":
		return
	var team := String(d.team)
	var machine: bool = d.get("machine_only", false)
	if not sim.is_payload_target(team, target, machine):
		target = _default_target(team, ctx, machine)
	var mul := power * float(d.power)
	var dur_mul := 1.0
	var extra := 0
	var hops := 0
	var falloff := 1.0
	var stealth := false
	var echo: Dictionary = {}
	var heat_add := float(d.get("heat", 1.0))
	var trace_add := float(d.get("trace", 0.0))
	for m in mods:
		match m.id:
			"amp", "compress", "overclock":
				mul *= float(m.get("mul", 1.0))
			"persist":
				dur_mul *= float(m.dur_mul)
			"fork":
				extra += int(m.extra)
			"chain":
				hops = int(m.hops)
				falloff = float(m.falloff)
			"stealth":
				stealth = true
			"echo":
				echo = m
		heat_add += float(m.get("heat", 0.0))
		trace_add += float(m.get("trace", 0.0))
	if stealth:
		trace_add = 0.0
	if is_echo:
		heat_add = 0.0
	if i >= 0 and i < threads.size():
		threads[i].lit[slot] = sim.time
	var primary := sim.get_unit(target)
	if primary == null:
		sim._emit({"type": "thread_fail", "thread": i, "reason": "fizzle"})
		return
	# Target list: primary, Fork extras around it, then Chain hops (with falloff).
	var hits := [[primary, 1.0]]
	var seen := [primary.id]
	if extra > 0:
		for o in sim.neighbours(primary, seen, CombatSim.FORK_RANGE, extra):
			if sim.is_payload_target(team, o.id, machine):
				hits.append([o, 1.0])
				seen.append(o.id)
	if hops > 0:
		var cur: CombatSim.Unit = primary
		var k := 1.0
		for n in hops:
			var nxt := sim.neighbours(cur, seen, CombatSim.CHAIN_RANGE, 1)
			if nxt.is_empty() or not sim.is_payload_target(team, nxt[0].id, machine):
				break
			k *= falloff
			hits.append([nxt[0], k])
			seen.append(nxt[0].id)
			cur = nxt[0]
	var ids := []
	for h in hits:
		ids.append(h[0].id)
		_apply(d, h[0], mul * float(h[1]), dur_mul, i)
	sim._emit({"type": "payload", "thread": i, "slot": slot, "chip": d.id, "targets": ids, "color": d.color, "echo": is_echo})
	if not echo.is_empty() and not is_echo:
		_echoes.append({"t": float(echo.delay), "thread": i, "slot": slot, "def": d,
			"mods": mods.filter(func(m): return m.id != "echo") + [{"id": "amp", "mul": float(echo.echo_mul)}],
			"target": target})
	if trace_add > 0.0:
		sim.add_trace(trace_add, String(d.name))
	_add_heat(heat_add)


func _default_target(team: String, ctx: Dictionary, machine: bool) -> int:
	if team == "enemy":
		var ev := int(ctx.get("enemy", -1))
		if sim.is_payload_target("enemy", ev, machine):
			return ev
		return sim.select("machine" if machine else "front", ctx)
	var m := int(ctx.get("merc", -1))
	if sim.is_payload_target("ally", m):
		return m
	return sim.select("ally_low", ctx)


func _apply(d: Dictionary, t: CombatSim.Unit, mul: float, dur_mul: float, thread: int) -> void:
	var col: Color = d.color
	match d.id:
		"ping":
			sim.hack_damage(t, float(d.damage) * mul, col)
		"shock":
			sim.hack_damage(t, float(d.damage) * mul, col)
			sim.apply_stun(t, float(d.stun) * float(d.power) * dur_mul, thread)
		"burn":
			sim.add_dot(t, float(d.dot) * mul, float(d.duration) * dur_mul, col)
			sim._emit({"type": "status", "unit": t.id, "text": "BURNING", "color": col})
		"breach":
			sim.apply_breach(t, float(d.vuln) * mul, float(d.duration) * dur_mul)
		"sonic":
			sim.interrupt(t, thread)
			sim.knockback(t, float(d.knock) * (1.4 if d.tier == 2 else 1.0))
			sim.hack_damage(t, float(d.damage) * mul, col)
		"contagion":
			sim.apply_infect(t, float(d.duration) * dur_mul, float(d.blast) * mul, float(d.radius))
		"hijack":
			sim.apply_hijack(t, float(d.duration) * dur_mul * (1.4 if d.tier == 2 else 1.0))
		"patch":
			sim.heal(t, float(d.heal) * mul)
		"firewall":
			sim.apply_shield(t, float(d.shield) * mul, float(d.duration) * dur_mul, true)
			sim._emit({"type": "status", "unit": t.id, "text": "FIREWALL", "color": col})
		"overdrive":
			sim.apply_haste(t, float(d.haste) * (1.4 if d.tier == 2 else 1.0) * minf(mul, 2.0), float(d.duration) * dur_mul)


func _add_heat(n: float) -> void:
	if n <= 0.0 or frozen > 0.0:
		return
	heat += n
	if heat >= heat_cap:
		frozen = float(ChipDB.CHASSIS.freeze)
		overheats += 1
		heat = 0.0
		sim._emit({"type": "overheat"})
		sim.add_trace(float(ChipDB.CHASSIS.overheat_trace), "overheat")
		on_event("on_overheat", {})
