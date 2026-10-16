extends SceneTree
## Headless balance harness for CombatSim.
## Usage: godot --headless --path . --script res://tools/sim_mission.gd -- [runs_per_cell] [squad_filter]
## Prints win rate, durations and deaths per squad / policy / threat.
## Columns: win% | boss% (reached the boss) | avg_dur (all runs) | win_dur | enc_dur (avg
## regular encounter, spawn->clear) | boss_d (boss fight when won) | deaths | intr (interrupts).
## Policies: none = never casts, auto = Autopilot daemon only, bot = scripted "decent play".

const DT := 1.0 / 30.0
const MAX_TIME := 900.0

var game: Node

const SQUADS := [
	{"name": "L1 Solo+Gunner, starter", "classes": ["solo", "gunner"], "level": 1,
		"active": ["short_circuit", "nano_patch", "overclock"], "passive": ["ram_expansion"]},
	{"name": "L3 S+G+Medtech", "classes": ["solo", "gunner", "medtech"], "level": 3,
		"active": ["short_circuit", "nano_patch", "overclock", "weapon_glitch"], "passive": ["ram_expansion", "biomonitor"]},
	{"name": "L5 S+G+Techie", "classes": ["solo", "gunner", "techie"], "level": 5,
		"active": ["short_circuit", "nano_patch", "synapse_burnout", "firewall"], "passive": ["ram_expansion", "targeting_uplink"]},
	{"name": "L7 S+G+Med, good deck", "classes": ["solo", "gunner", "medtech"], "level": 7,
		"active": ["short_circuit", "nano_patch", "synapse_burnout", "firewall", "weapon_glitch"], "passive": ["ram_expansion", "targeting_uplink", "kiroshi_link"]},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 30
	var only := int(args[1]) if args.size() > 1 else -1
	game = load("res://scripts/game.gd").new()
	game.rng.seed = 12345
	print("CombatSim balance harness — %d runs per cell, 1x speed (sim seconds)" % runs)
	print("%-26s %-6s %-3s %6s %6s %8s %8s %8s %7s %7s %6s" % ["squad", "policy", "T", "win%", "boss%", "avg_dur", "win_dur", "enc_dur", "boss_d", "deaths", "intr"])
	for si in SQUADS.size():
		if only >= 0 and si != only:
			continue
		var sq: Dictionary = SQUADS[si]
		for policy in ["none", "auto", "bot"]:
			for threat in range(1, 6):
				if sq.level == 1 and threat > 3:
					continue
				if sq.level >= 5 and threat < 2:
					continue
				_run_cell(sq, policy, threat, runs)
		print("")
	game.free()
	quit()


func _run_cell(sq: Dictionary, policy: String, threat: int, runs: int) -> void:
	var wins := 0
	var dur := 0.0
	var win_dur := 0.0
	var enc_time := 0.0
	var enc_n := 0
	var boss_time := 0.0
	var boss_n := 0
	var deaths := 0
	var intr := 0
	var reached := 0
	for n in runs:
		var contract: Dictionary = game.make_contract(threat)
		var runners := []
		for c in sq.classes:
			var r := UnitDB.make_runner(c, game.rng, false)
			r.level = sq.level
			runners.append(r)
		game.roster = runners
		game.squad = runners.map(func(r): return r.id)
		game.deck_passive = sq.passive
		var fixer: Dictionary = game.fixer_stats()
		if policy == "auto":
			fixer.autopilot = true
		var sim := CombatSim.new()
		sim.setup(contract, runners, sq.active, fixer, 1000 + n * 7 + threat * 131)
		var enc_start := 0.0
		var think := 0.0
		while sim.outcome == "" and sim.time < MAX_TIME:
			sim.step(DT)
			if policy == "bot":
				think -= DT
				if think <= 0.0:
					think = 0.25
					_bot(sim)
			for ev in sim.pop_events():
				if ev.type == "encounter_start":
					enc_start = sim.time
					if ev.boss:
						reached += 1
				elif ev.type == "encounter_cleared":
					if ev.boss:
						boss_time += sim.time - enc_start
						boss_n += 1
					else:
						enc_time += sim.time - enc_start
						enc_n += 1
		if sim.outcome == "success":
			wins += 1
			win_dur += sim.time
		dur += sim.time
		deaths += sim.downed_ids().size()
		intr += sim.interrupts
	print("%-26s %-6s %-3d %5.0f%% %5.0f%% %7.0fs %7.0fs %7.1fs %6.0fs %7.2f %6.1f" % [
		sq.name.substr(0, 26), policy, threat, 100.0 * wins / runs, 100.0 * reached / runs, dur / runs,
		win_dur / maxi(1, wins), enc_time / maxi(1, enc_n), boss_time / maxi(1, boss_n),
		float(deaths) / runs, float(intr) / runs])


## "Decent play" bot: interrupts, heals, then spends spare RAM on damage/buffs.
func _bot(sim: CombatSim) -> void:
	if not sim.in_combat():
		return
	var slot_of := {}
	for i in sim.slots.size():
		slot_of[sim.slots[i].id] = i
	var foes := sim.enemies()
	var allies := sim.runners()
	# 1. Interrupt telegraphs (after a human-ish reaction delay).
	if slot_of.has("short_circuit"):
		var s: int = slot_of.short_circuit
		for e in foes:
			if e.is_casting() and e.cast_total - e.cast_t > 0.3 and sim.can_cast(s):
				sim.cast(s, e.id)
				return
	# 2. Heal.
	var low: CombatSim.Unit = null
	for r in allies:
		if low == null or r.hp_pct() < low.hp_pct():
			low = r
	if low and low.hp_pct() < 0.5 and slot_of.has("nano_patch") and sim.can_cast(slot_of.nano_patch):
		sim.cast(slot_of.nano_patch, low.id)
		return
	var hurt := allies.filter(func(r): return r.hp_pct() < 0.7).size()
	var boss: CombatSim.Unit = null
	var caster_alive := false
	for e in foes:
		if e.boss:
			boss = e
		if not e.cast_def.is_empty():
			caster_alive = true
	if slot_of.has("firewall") and sim.can_cast(slot_of.firewall) and (hurt >= 2 or (boss and boss.is_casting())):
		sim.cast(slot_of.firewall, -1)
		return
	# Keep RAM for the next interrupt when casters are around.
	var reserve := 0.0
	if caster_alive and slot_of.has("short_circuit"):
		var sc: Dictionary = sim.slots[slot_of.short_circuit]
		if sc.cd_t < 4.0:
			reserve = 4.0
	var spare := sim.ram - reserve
	if slot_of.has("optics_jam") and sim.can_cast(slot_of.optics_jam) and spare >= 4 and (foes.size() >= 3 or boss):
		sim.cast(slot_of.optics_jam, -1)
		return
	if slot_of.has("weapon_glitch") and sim.can_cast(slot_of.weapon_glitch) and spare >= 3:
		for e in foes:
			if (e.boss or e.kind == "heavy") and e.weaken_t <= 0.0:
				sim.cast(slot_of.weapon_glitch, e.id)
				return
	if slot_of.has("system_collapse") and sim.can_cast(slot_of.system_collapse):
		if boss and boss.hp_pct() < 0.6:
			sim.cast(slot_of.system_collapse, boss.id)
			return
	if slot_of.has("synapse_burnout") and sim.can_cast(slot_of.synapse_burnout) and spare >= 7:
		var t: CombatSim.Unit = boss
		for e in foes:
			if e.hp_pct() < 0.4 and e.hp > 50:
				t = e
		if t == null:
			t = foes[0]
		sim.cast(slot_of.synapse_burnout, t.id)
		return
	if slot_of.has("overclock") and sim.can_cast(slot_of.overclock) and spare >= 3:
		var best: CombatSim.Unit = null
		for r in allies:
			if r.haste_t <= 0.0 and (best == null or r.dmg / r.interval > best.dmg / best.interval):
				best = r
		if best:
			sim.cast(slot_of.overclock, best.id)
			return
	if slot_of.has("nano_patch") and low and low.hp_pct() < 0.75 and spare >= 3 and sim.can_cast(slot_of.nano_patch):
		sim.cast(slot_of.nano_patch, low.id)
		return
	if slot_of.has("short_circuit") and not caster_alive and spare >= 7 and sim.can_cast(slot_of.short_circuit):
		sim.cast(slot_of.short_circuit, foes[0].id)
