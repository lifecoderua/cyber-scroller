class_name DiceBot
extends RefCounted
## Bot policies for DiceCombat (balance harness, flow checks, AUTO button).
##   "random": no rerolls, no hacks, every die on a random valid target.
##   "greedy": rerolls blanks, hits the weakest reachable enemy, shields / heals the weakest
##             merc, no hacks.
##   "smart":  rerolls weak faces, hacks the scariest intents, then repeatedly takes the best
##             (die, target) move by a threat-aware score.


static func play_turn(c: DiceCombat, policy: String) -> void:
	if c.outcome != "":
		return
	match policy:
		"random":
			c.finish_roll()
			for d in c.live_dice():
				var ts := c.valid_targets(d)
				if not ts.is_empty():
					c.use_die(d, ts[c.rng.randi() % ts.size()])
		"greedy":
			_reroll(c, 0.5)
			c.finish_roll()
			for d in c.live_dice():
				_use_greedy(c, d)
		_:
			_reroll(c, 2.5)
			c.finish_roll()
			_smart(c)
	if c.outcome == "":
		c.end_turn()


## Lock dice worth at least `keep`, reroll the rest while rerolls last.
static func _reroll(c: DiceCombat, keep: float) -> void:
	while c.phase == "roll" and c.rerolls > 0:
		var any := false
		for d in c.live_dice():
			d.locked = _face_value(d.face()) >= keep
			any = any or not d.locked
		if not any:
			break
		c.reroll()


static func _face_value(f: Dictionary) -> float:
	var v := float(f.v)
	match String(f.k):
		"blank": return 0.0
		"glitch": return -1.0
		"blast", "slice": return v * 1.8
		"cleave": return v * 1.4
		"taunt", "triage": return v * 1.2
		"dodge", "stun": return 3.0
		"focus": return v * 0.8
		"turret": return v * 1.6
	return v


static func _use_greedy(c: DiceCombat, d: DiceCombat.Die) -> void:
	var ts := c.valid_targets(d)
	if ts.is_empty():
		return
	var f := d.face()
	var best: int = ts[0]
	match DiceDB.target_kind(f):
		"melee", "enemy":
			for id in ts:
				if c.get_unit(id).hp < c.get_unit(best).hp:
					best = id
		"ally":
			for id in ts:
				if c.get_unit(id).hp_pct() < c.get_unit(best).hp_pct():
					best = id
	c.use_die(d, best)


# --- smart policy ---------------------------------------------------------------------

static func _intent_dmg(c: DiceCombat, e: DiceCombat.Unit) -> float:
	if e.intent.is_empty() or e.stunned or e.spoofed or e.hijacked:
		return 0.0
	var v := float(e.intent.v)
	match String(e.intent.k):
		"blast": return v * 2.0
		"rampage": return v * c.mercs().size()
		"upload": return v + 3.0
		"aim": return 4.0
		"summon": return 2.0
		"guard", "blank": return 0.0
	return v


## Would this merc die from what is coming (after its shield)?
static func _lethal(c: DiceCombat, u: DiceCombat.Unit) -> bool:
	return c.incoming(u) - u.shield >= u.hp and not u.dodge


static func _smart(c: DiceCombat) -> void:
	_smart_hacks(c)
	var guard := 0
	while c.outcome == "" and c.phase == "assign" and guard < 20:
		guard += 1
		var best_score := 0.2
		var best_die: DiceCombat.Die = null
		var best_t := -1
		for d in c.live_dice():
			if d.used:
				continue
			for t in c.valid_targets(d):
				var s := _score(c, d, t)
				if s > best_score:
					best_score = s
					best_die = d
					best_t = t
		if best_die == null:
			break
		c.use_die(best_die, best_t)
	_smart_hacks(c)


static func _smart_hacks(c: DiceCombat) -> void:
	for slot in c.hacks.size():
		if c.outcome != "" or c.hack_block(slot) != "":
			continue
		var id := ChipDB.base_id(c.hacks[slot])
		if c.heat + int(ChipDB.get_def(c.hacks[slot]).get("heat", 1)) >= c.heat_cap and c.trace > 60.0:
			continue
		match id:
			"short_circuit", "spoof":
				var worst: DiceCombat.Unit = null
				for e in c.enemies():
					if worst == null or _intent_dmg(c, e) > _intent_dmg(c, worst):
						worst = e
				if worst != null and _intent_dmg(c, worst) >= 3.5:
					c.hack(slot, worst.id)
			"hijack":
				for e in c.enemies():
					if e.machine and _intent_dmg(c, e) >= 3.0 and c.trace < 50.0:
						c.hack(slot, e.id)
						break
			"patch", "firewall":
				for u in c.mercs():
					if _lethal(c, u) or (id == "firewall" and c.incoming(u) >= 3) or (id == "patch" and u.max_hp - u.hp >= 4):
						c.hack(slot, u.id)
						break
			"ping":
				for e in c.enemies():
					if e.hp <= 2 + int(c.fixer.get("hack_power", 0)) and _intent_dmg(c, e) > 0.0:
						c.hack(slot, e.id)
						break
			"breach":
				for e in c.enemies():
					if (e.armor > 0 or e.front_shield or e.shield > 0) and e.hp >= 5:
						c.hack(slot, e.id)
						break
			"overclock":
				for d in c.live_dice():
					if not d.used and DiceDB.is_damage(d.face()) and c.phase == "assign":
						c.hack(slot, d.index)
						break
			"bandwidth":
				pass
			"echo":
				for d in c.live_dice():
					if d.used and DiceDB.is_damage(d.face()) and int(d.face().v) >= 4 and not c.enemies().is_empty():
						c.hack(slot, d.index)
						break


## Value of a damage hit on an enemy: kill bonus scaled by the threat it removes.
static func _hit_value(c: DiceCombat, e: DiceCombat.Unit, dmg: float, kind: String) -> float:
	var eff := dmg + e.vuln
	if kind == "shot" and e.front_shield and not e.breached:
		return 0.0
	if not kind in ["pierce", "slice"] and not e.breached:
		eff -= e.armor
		eff -= e.shield
	eff = maxf(0.0, eff)
	var threat := _intent_dmg(c, e) + 1.0 + (1.5 if e.backline else 0.0)
	if eff >= e.hp:
		return 6.0 + threat * 2.0 + (0.5 * e.hp)
	return (eff / float(e.hp)) * threat * 1.6 + eff * 0.3


static func _score(c: DiceCombat, d: DiceCombat.Die, t: int) -> float:
	var f := d.face()
	var v := float(f.v)
	var u := c.get_unit(t)
	var owner := c.get_unit(d.owner)
	match String(f.k):
		"atk", "shot", "pierce", "rage":
			return _hit_value(c, u, v, String(f.k)) - (1.0 if f.k == "rage" and owner.hp <= 2 else 0.0)
		"cleave":
			var foes := c.enemies()
			var i := foes.find(u)
			var s := _hit_value(c, u, v, "cleave")
			if i > 0:
				s += _hit_value(c, foes[i - 1], v, "cleave")
			if i >= 0 and i < foes.size() - 1:
				s += _hit_value(c, foes[i + 1], v, "cleave")
			return s
		"slice":
			var s := 0.0
			for e in c.enemies().slice(0, 3):
				s += _hit_value(c, e, v, "slice")
			return s
		"blast":
			var s := 0.0
			for e in c.enemies():
				s += _hit_value(c, e, v, "blast")
			return s
		"shield":
			var need := float(c.incoming(u) - u.shield)
			if need <= 0.0:
				return 0.3
			return minf(v, need) * 1.5 + (6.0 if _lethal(c, u) else 0.0)
		"heal":
			var miss := float(u.max_hp - u.hp)
			return minf(v, miss) * 1.1 + (5.0 if _lethal(c, u) and c.incoming(u) - u.shield < u.hp + v else 0.0)
		"triage":
			var s := 0.0
			for m in c.mercs():
				s += minf(v, float(m.max_hp - m.hp))
			return s
		"taunt":
			var pulled := 0.0
			for e in c.enemies():
				var who := String(UnitDB.INTENTS.get(String(e.intent.get("k", "blank")), {}).get("who", "none"))
				if who in ["front", "back", "random", "fixed"] and e.intent_target != owner.id and not e.stunned:
					var tu := c.get_unit(e.intent_target)
					if tu != null and tu.hp <= owner.hp:
						pulled += _intent_dmg(c, e)
			if owner.hp + owner.shield + v <= c.incoming(owner) + pulled:
				return 0.5
			return pulled * 1.0 + v * 0.4
		"dodge":
			var inc := float(c.incoming(owner))
			return 0.3 if inc <= 0.0 else inc * 1.3
		"mark":
			var dmg_left := 0
			for o in c.live_dice():
				if not o.used and o != d and DiceDB.is_damage(o.face()):
					dmg_left += 1
			return v * dmg_left * 0.9 * (1.0 if _intent_dmg(c, u) > 0.0 else 0.5)
		"stun":
			return _intent_dmg(c, u) * 1.6
		"ram":
			return v * 0.9
		"focus":
			return 1.2
		"turret":
			return v * 1.5
		"glitch":
			return 0.0
	return 0.0
