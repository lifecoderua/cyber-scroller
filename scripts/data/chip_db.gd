class_name ChipDB
extends RefCounted
## Cyberdeck chips. A thread is one Trigger followed by chips that run left to right:
## selectors pick targets, modifiers stack onto the NEXT payload, payloads fire and
## consume them. See docs/DESIGN.md "Cyberdeck".
##
## A chip reference is a String: "ping" (tier 1) or "ping+" (tier 2, recompiled).
## Fields: name, kind (trigger | selector | modifier | payload), tag (2-4 chars for the
## compact tile), ram, lat (s added to the thread cycle), heat, trace, rarity, desc,
## desc2 (tier 2 text), plus effect params. `power` scales payload numbers; tier 2 adds
## TIER2_POWER unless the chip overrides specific params in "t2".

const TIER2_POWER := 0.4
const RARITY_PRICE := {"common": 30, "uncommon": 50, "rare": 80}
const KIND_COLORS := {
	"trigger": Color("f9c80e"), "selector": Color("4cff8f"), "modifier": Color("3d8bff"),
	"payload": Color("ff3d81"),
}
const KIND_NAMES := {"trigger": "TRIGGER", "selector": "SELECTOR", "modifier": "MODIFIER", "payload": "PAYLOAD"}

## Chassis: the deck hardware. Threads x slots (slot 0 is the trigger).
const CHASSIS := {
	"name": "Street Mk.I", "threads": 3, "slots": 4, "latency": 0.6,
	"max_ram": 12.0, "ram_regen": 1.1, "heat_cap": 8.0, "heat_decay": 1.1,
	"freeze": 3.0, "overheat_trace": 6.0,
}

const DEFS := {
	# --- triggers: WHEN the thread runs -------------------------------------------
	"timer": {"name": "Timer", "kind": "trigger", "tag": "T", "ram": 0, "lat": 0.0, "rarity": "common",
		"interval": 3.5, "t2": {"interval": 2.5},
		"desc": "Runs every 3.5s.", "desc2": "Runs every 2.5s."},
	"manual": {"name": "Manual", "kind": "trigger", "tag": "MAN", "ram": 0, "lat": 0.0, "rarity": "common",
		"desc": "Runs when you tap EXEC. You pick the first target.", "desc2": "-1 RAM per run.", "t2": {"ram_disc": 1}},
	"on_kill": {"name": "On Kill", "kind": "trigger", "tag": "KIL", "ram": 0, "lat": 0.4, "rarity": "common",
		"desc": "Runs when an enemy dies. Self = the killer.", "desc2": "Cycle -0.4s.", "t2": {"lat": 0.0}},
	"on_hit": {"name": "Ally Hit", "kind": "trigger", "tag": "HIT", "ram": 0, "lat": 1.0, "rarity": "common",
		"desc": "Runs when a merc takes a hit. Self = that merc.", "desc2": "Cycle -0.5s.", "t2": {"lat": 0.5}},
	"on_low": {"name": "Ally Low", "kind": "trigger", "tag": "LOW", "ram": 0, "lat": 0.5, "rarity": "uncommon",
		"threshold": 0.4, "t2": {"threshold": 0.55},
		"desc": "Runs when a merc drops under 40% HP. Self = that merc.", "desc2": "Under 55% HP."},
	"on_tele": {"name": "Telegraph", "kind": "trigger", "tag": "TEL", "ram": 0, "lat": 0.3, "rarity": "uncommon",
		"desc": "Runs when an enemy starts a telegraphed attack.", "desc2": "Cycle -0.3s.", "t2": {"lat": 0.0}},
	"on_wave": {"name": "Wave Start", "kind": "trigger", "tag": "WAV", "ram": 0, "lat": 0.0, "rarity": "common",
		"desc": "Runs when a wave arrives.", "desc2": "Also runs 4s into the wave.", "t2": {"repeat": 4.0}},
	"on_sig": {"name": "Signature", "kind": "trigger", "tag": "SIG", "ram": 0, "lat": 0.4, "rarity": "uncommon",
		"desc": "Runs when a merc uses their signature. Self = that merc.", "desc2": "Cycle -0.4s.", "t2": {"lat": 0.0}},
	"on_overheat": {"name": "Overheat", "kind": "trigger", "tag": "OVH", "ram": 0, "lat": 0.0, "rarity": "rare",
		"desc": "Runs when the deck overheats, even while frozen.", "desc2": "Costs no RAM.", "t2": {"free": true}},
	# Port triggers: hook an implant's event. Dark while no live merc carries the implant.
	"on_dodge": {"name": "On Dodge", "kind": "trigger", "tag": "DDG", "ram": 0, "lat": 0.3, "rarity": "uncommon",
		"port": "dodge", "desc": "PORT: Kerenzikov. Runs when a merc dodges. Self = that merc.", "desc2": "Cycle -0.3s.", "t2": {"lat": 0.0}},
	"on_knock": {"name": "On Knockback", "kind": "trigger", "tag": "KNK", "ram": 0, "lat": 0.3, "rarity": "uncommon",
		"port": "knock", "desc": "PORT: Gorilla Arms. Runs on a knockback. Self = the merc.", "desc2": "Cycle -0.3s.", "t2": {"lat": 0.0}},
	"on_blast": {"name": "On Blast", "kind": "trigger", "tag": "BLS", "ram": 0, "lat": 0.3, "rarity": "uncommon",
		"port": "blast", "desc": "PORT: Projectile Launcher. Runs on its grenade. Self = the merc.", "desc2": "Cycle -0.3s.", "t2": {"lat": 0.0}},

	# --- selectors: WHO ---------------------------------------------------------------
	"sel_front": {"name": "Front Enemy", "kind": "selector", "tag": "FRT", "ram": 0, "lat": 0.0, "rarity": "common",
		"pick": "front", "desc": "The enemy closest to the crew."},
	"sel_weak": {"name": "Weakest", "kind": "selector", "tag": "WK", "ram": 0, "lat": 0.1, "rarity": "common",
		"pick": "weakest", "desc": "The enemy with the lowest HP %."},
	"sel_tele": {"name": "Telegraphing", "kind": "selector", "tag": "TLG", "ram": 0, "lat": 0.0, "rarity": "uncommon",
		"pick": "telegraph", "desc": "An enemy mid-telegraph. None = the thread waits."},
	"sel_back": {"name": "Backline", "kind": "selector", "tag": "BCK", "ram": 0, "lat": 0.1, "rarity": "uncommon",
		"pick": "back", "desc": "The enemy farthest from the crew (snipers, runners)."},
	"sel_machine": {"name": "Machine", "kind": "selector", "tag": "MCH", "ram": 0, "lat": 0.0, "rarity": "uncommon",
		"pick": "machine", "desc": "A drone or turret. None = the thread waits."},
	"sel_self": {"name": "Self-merc", "kind": "selector", "tag": "SLF", "ram": 0, "lat": 0.0, "rarity": "common",
		"pick": "self", "desc": "The merc who fired the event."},
	"sel_ally": {"name": "Lowest Ally", "kind": "selector", "tag": "ALY", "ram": 0, "lat": 0.0, "rarity": "common",
		"pick": "ally_low", "desc": "The merc with the lowest HP %."},

	# --- modifiers: HOW (stack onto the next payload) ------------------------------
	"amp": {"name": "Amplify", "kind": "modifier", "tag": "AMP", "ram": 1, "lat": 0.2, "rarity": "common",
		"mul": 1.5, "t2": {"mul": 1.8}, "desc": "Next payload x1.5.", "desc2": "Next payload x1.8."},
	"fork": {"name": "Fork", "kind": "modifier", "tag": "FRK", "ram": 2, "lat": 0.3, "rarity": "uncommon",
		"extra": 2, "t2": {"extra": 3}, "desc": "Next payload also hits 2 more targets.", "desc2": "3 more targets."},
	"chain": {"name": "Chain", "kind": "modifier", "tag": "CHN", "ram": 2, "lat": 0.3, "rarity": "uncommon",
		"hops": 2, "falloff": 0.75, "t2": {"hops": 3},
		"desc": "Next payload jumps 2x to nearby targets (75% each hop).", "desc2": "Jumps 3x."},
	"echo": {"name": "Echo", "kind": "modifier", "tag": "ECH", "ram": 2, "lat": 0.5, "rarity": "rare",
		"delay": 0.6, "echo_mul": 0.7, "t2": {"echo_mul": 1.0},
		"desc": "Next payload repeats once after 0.6s at 70%.", "desc2": "Repeats at 100%."},
	"compress": {"name": "Compress", "kind": "modifier", "tag": "CMP", "ram": 0, "lat": 0.0, "rarity": "common",
		"ram_mul": 0.5, "mul": 0.7, "t2": {"mul": 0.85},
		"desc": "Next payload costs half RAM, x0.7 effect.", "desc2": "x0.85 effect."},
	"stealth": {"name": "Stealth", "kind": "modifier", "tag": "STL", "ram": 1, "lat": 0.2, "rarity": "uncommon",
		"desc": "Next payload adds no Trace.", "desc2": "Also -1 Heat.", "t2": {"heat": -1}},
	"overclock": {"name": "Overclock", "kind": "modifier", "tag": "OVC", "ram": 1, "lat": 0.0, "rarity": "rare",
		"mul": 2.0, "heat": 2, "trace": 1.0,
		"desc": "Next payload x2. +2 Heat, +1 Trace.", "desc2": "+1 Heat instead.", "t2": {"heat": 1}},
	"persist": {"name": "Persist", "kind": "modifier", "tag": "PRS", "ram": 1, "lat": 0.1, "rarity": "common",
		"dur_mul": 2.0, "t2": {"dur_mul": 2.6}, "desc": "Next payload lasts twice as long.", "desc2": "x2.6 duration."},

	# --- payloads: WHAT -------------------------------------------------------------
	"ping": {"name": "Ping", "kind": "payload", "tag": "PNG", "ram": 2, "lat": 0.3, "heat": 1, "rarity": "common",
		"team": "enemy", "damage": 30.0, "color": Color("2de2e6"),
		"desc": "30 hack damage (ignores armor).", "desc2": "42 hack damage."},
	"shock": {"name": "Short Circuit", "kind": "payload", "tag": "SC", "ram": 4, "lat": 0.6, "heat": 1, "rarity": "common",
		"team": "enemy", "damage": 12.0, "stun": 1.3, "color": Color("7ae8ff"),
		"desc": "12 dmg + stun 1.3s. Interrupts telegraphs.", "desc2": "17 dmg + stun 1.8s."},
	"burn": {"name": "Overheat", "kind": "payload", "tag": "BRN", "ram": 3, "lat": 0.4, "heat": 1, "rarity": "common",
		"team": "enemy", "dot": 9.0, "duration": 5.0, "color": Color("ff9f1c"),
		"desc": "Burn: 9 dmg/s for 5s.", "desc2": "13 dmg/s for 5s."},
	"breach": {"name": "Breach", "kind": "payload", "tag": "BRC", "ram": 3, "lat": 0.4, "heat": 1, "rarity": "uncommon",
		"team": "enemy", "vuln": 0.3, "duration": 6.0, "color": Color("ffe066"),
		"desc": "Strips armor and shields, +30% damage taken for 6s.", "desc2": "+42% damage taken."},
	"sonic": {"name": "Sonic Shock", "kind": "payload", "tag": "SON", "ram": 3, "lat": 0.3, "heat": 1, "rarity": "uncommon",
		"team": "enemy", "damage": 6.0, "knock": 28.0, "color": Color("b388ff"),
		"desc": "Interrupts a telegraph and knocks back. 6 dmg.", "desc2": "Knocks back further."},
	"contagion": {"name": "Contagion", "kind": "payload", "tag": "CTG", "ram": 3, "lat": 0.4, "heat": 1, "rarity": "uncommon",
		"team": "enemy", "duration": 8.0, "radius": 64.0, "blast": 20.0, "color": Color("9bff3d"),
		"desc": "Infects for 8s: on death it bursts for 20 and spreads burn/breach nearby.",
		"desc2": "Bursts for 28."},
	"hijack": {"name": "Hijack", "kind": "payload", "tag": "HJK", "ram": 5, "lat": 0.8, "heat": 2, "trace": 12.0,
		"rarity": "rare", "team": "enemy", "machine_only": true, "duration": 10.0, "color": Color("ff6ad5"),
		"desc": "A drone or turret fights for you for 10s. +12 Trace.", "desc2": "14s."},
	"patch": {"name": "Patch", "kind": "payload", "tag": "PAT", "ram": 3, "lat": 0.4, "heat": 1, "rarity": "common",
		"team": "ally", "heal": 40.0, "color": Color("4cff8f"),
		"desc": "Heal a merc for 40.", "desc2": "Heal 56."},
	"firewall": {"name": "Firewall", "kind": "payload", "tag": "FW", "ram": 4, "lat": 0.5, "heat": 1, "rarity": "uncommon",
		"team": "ally", "shield": 35.0, "duration": 6.0, "color": Color("3d8bff"),
		"desc": "35 shield for 6s. Blocks the next enemy quickhack.", "desc2": "49 shield."},
	"overdrive": {"name": "Overdrive", "kind": "payload", "tag": "OVD", "ram": 3, "lat": 0.4, "heat": 1, "rarity": "common",
		"team": "ally", "haste": 0.5, "duration": 5.0, "color": Color("f9c80e"),
		"desc": "+50% attack speed for 5s.", "desc2": "+70% attack speed."},
}

## Starting deck: three readable programs that teach the three trigger families.
const STARTER_THREADS := [
	["timer", "sel_front", "ping", ""],
	["on_low", "sel_self", "patch", ""],
	["manual", "sel_tele", "shock", ""],
]
const STARTER_SPARE := ["amp", "sel_weak"]

static var _cache := {}


static func base_id(ref: String) -> String:
	return ref.trim_suffix("+")


static func tier(ref: String) -> int:
	return 2 if ref.ends_with("+") else 1


static func upgraded(ref: String) -> String:
	return base_id(ref) + "+"


## Resolved definition for a chip reference (tier 2 overrides applied). {} if unknown.
static func get_def(ref: String) -> Dictionary:
	if ref == "":
		return {}
	if _cache.has(ref):
		return _cache[ref]
	var base: Dictionary = DEFS.get(base_id(ref), {})
	if base.is_empty():
		return {}
	var d := base.duplicate()
	d["id"] = base_id(ref)
	d["tier"] = tier(ref)
	d["power"] = 1.0
	if d.tier == 2:
		if d.kind == "payload":
			d.power = 1.0 + TIER2_POWER
		for k in base.get("t2", {}):
			d[k] = base.t2[k]
	if not d.has("color"):
		d["color"] = KIND_COLORS[d.kind]
	_cache[ref] = d
	return d


static func kind(ref: String) -> String:
	return get_def(ref).get("kind", "")


static func color(ref: String) -> Color:
	return get_def(ref).get("color", UITheme.TEXT_DIM)


static func kind_color(k: String) -> Color:
	return KIND_COLORS.get(k, UITheme.TEXT_DIM)


static func display_name(ref: String) -> String:
	var d := get_def(ref)
	return String(d.get("name", ref)) + (" II" if d.get("tier", 1) == 2 else "")


static func desc(ref: String) -> String:
	var d := get_def(ref)
	return String(d.get("desc2", d.get("desc", ""))) if d.get("tier", 1) == 2 and d.has("desc2") else String(d.get("desc", ""))


static func price(ref: String) -> int:
	var p: int = RARITY_PRICE.get(get_def(ref).get("rarity", "common"), 30)
	return p * (2 if tier(ref) == 2 else 1)


static func all_ids() -> Array:
	return DEFS.keys()


static func ids_of(k: String) -> Array:
	return DEFS.keys().filter(func(id): return DEFS[id].kind == k)


## Compiled cost / cycle / heat / trace of a thread (Array of refs, "" = empty slot).
## `stats` carries skill tree bonuses (Game.fixer_stats()).
static func thread_stats(chips: Array, stats := {}) -> Dictionary:
	var ram := 0.0
	var lat := float(CHASSIS.latency)
	var heat := 0.0
	var trace := 0.0
	var ram_mul := 1.0
	var stealth := false
	var payloads := 0
	var trig := get_def(chips[0] if chips.size() > 0 else "")
	for ref in chips:
		var d := get_def(ref)
		if d.is_empty():
			continue
		lat += float(d.get("lat", 0.0))
		match d.kind:
			"modifier":
				ram += float(d.ram)
				ram_mul *= float(d.get("ram_mul", 1.0))
				heat += float(d.get("heat", 0.0))
				trace += float(d.get("trace", 0.0))
				if d.id == "stealth":
					stealth = true
			"payload":
				payloads += 1
				ram += float(d.ram) * ram_mul
				heat += float(d.get("heat", 1.0))
				if not stealth:
					trace += float(d.get("trace", 0.0)) * (1.0 - float(stats.get("trace_pct", 0.0)))
				ram_mul = 1.0
				stealth = false
			_:
				ram += float(d.get("ram", 0))
	ram = maxf(0.0, ram - float(trig.get("ram_disc", 0)))
	if trig.get("free", false):
		ram = 0.0
	var cycle := lat
	if trig.get("id", "") == "timer":
		cycle = maxf(cycle, float(trig.interval))
	return {"ram": ceilf(ram - 0.01), "cycle": cycle, "heat": maxf(0.0, heat), "trace": trace, "payloads": payloads}


## Problems with a thread for the editor ("" = fine).
static func thread_warning(chips: Array, crew_ports: Array) -> String:
	var trig := get_def(chips[0] if chips.size() > 0 else "")
	if trig.is_empty():
		var any := false
		for ref in chips:
			any = any or ref != ""
		return "No trigger: slot 1 needs a yellow chip" if any else ""
	if trig.kind != "trigger":
		return "Slot 1 must be a trigger"
	var has_payload := false
	for i in range(1, chips.size()):
		var d := get_def(chips[i])
		if d.get("kind", "") == "trigger":
			return "Only slot 1 can hold a trigger"
		has_payload = has_payload or d.get("kind", "") == "payload"
	if not has_payload:
		return "No payload: the thread does nothing"
	if trig.has("port") and not trig.port in crew_ports:
		return "Dark: no merc has the %s port" % String(trig.port).to_upper()
	var mods_dangling := false
	for i in range(1, chips.size()):
		var k := kind(chips[i])
		if k == "modifier":
			mods_dangling = true
		elif k == "payload":
			mods_dangling = false
	if mods_dangling:
		return "Last modifier has no payload after it"
	return ""


## Plain-language dry-run readout of a thread: what it does, what it costs.
static func readout(chips: Array, stats := {}) -> String:
	var trig := get_def(chips[0] if chips.size() > 0 else "")
	if trig.is_empty() or trig.kind != "trigger":
		return "Empty thread."
	var when := ""
	match trig.id:
		"timer": when = "Every %ss" % _num(float(trig.interval))
		"manual": when = "On EXEC"
		"on_kill": when = "On kill"
		"on_hit": when = "When a merc is hit"
		"on_low": when = "When a merc drops under %d%%" % int(round(float(trig.threshold) * 100.0))
		"on_tele": when = "On enemy telegraph"
		"on_wave": when = "On wave start"
		"on_sig": when = "On signature"
		"on_overheat": when = "On overheat"
		_: when = String(trig.name)
	var parts: Array[String] = []
	var who := ""
	var mods: Array[String] = []
	for i in range(1, chips.size()):
		var d := get_def(chips[i])
		if d.is_empty():
			continue
		match d.kind:
			"selector":
				who = String(d.name).to_lower()
			"modifier":
				mods.append(_mod_text(d))
			"payload":
				var verb := _payload_verb(d)
				var tgt := who
				if tgt == "":
					tgt = "front enemy" if d.team == "enemy" else ("self-merc" if trig.id in ["on_hit", "on_low", "on_sig", "on_kill", "on_dodge", "on_knock", "on_blast"] else "lowest ally")
				var s := "%s %s" % [verb, tgt]
				if not mods.is_empty():
					s += " (" + ", ".join(mods) + ")"
				parts.append(s)
				mods.clear()
	if parts.is_empty():
		return when + ": nothing (add a payload)."
	var st := thread_stats(chips, stats)
	var cost := "%d RAM, cycle %ss, Heat +%s" % [int(st.ram), _num(snappedf(st.cycle, 0.1)), _num(st.heat)]
	if st.trace > 0.0:
		cost += ", Trace +%s" % _num(snappedf(st.trace, 0.1))
	return "%s: %s. %s" % [when, "; then ".join(parts), cost]


static func _payload_verb(d: Dictionary) -> String:
	var p := float(d.power)
	match d.id:
		"ping": return "hit %d" % int(round(d.damage * p))
		"shock": return "stun %ss" % _num(snappedf(d.stun * (1.0 if d.tier == 1 else 1.4), 0.1))
		"burn": return "burn %d/s" % int(round(d.dot * p))
		"breach": return "breach"
		"sonic": return "interrupt"
		"contagion": return "infect"
		"hijack": return "hijack"
		"patch": return "heal %d" % int(round(d.heal * p))
		"firewall": return "shield %d" % int(round(d.shield * p))
		"overdrive": return "overdrive"
	return String(d.name).to_lower()


static func _mod_text(d: Dictionary) -> String:
	match d.id:
		"amp", "overclock": return "x%s" % _num(float(d.mul))
		"fork": return "+%d targets" % int(d.extra)
		"chain": return "%d jumps" % int(d.hops)
		"echo": return "echo"
		"compress": return "half RAM"
		"stealth": return "no Trace"
		"persist": return "x%s duration" % _num(float(d.dur_mul))
	return String(d.name).to_lower()


static func _num(f: float) -> String:
	if is_equal_approx(f, roundf(f)):
		return str(int(roundf(f)))
	return "%.1f" % f
