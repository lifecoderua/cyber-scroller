class_name EventDB
extends RefCounted
## Event nodes: a short text and 2-3 choices with risk/reward. Effects are resolved by
## RunState.apply_effects(). Effect keys:
##   trace (+/-), eddies (+/-, a negative cost needs the money), heal_pct (whole crew),
##   hurt_pct (whole crew), scar (random merc), unscar (most scarred merc), item (random
##   item of a theme), chip (random chip, "rare" for rare only), upgrade_chip (random chip
##   +1 tier), fight ("ambush": a fight right here), gamble {p, win: {...}, lose: {...}}.

const EVENTS := [
	{"id": "rival", "title": "A RIVAL FIXER CALLS",
		"text": "Old competition. She knows corp security is sniffing for your deck, and she's selling.",
		"choices": [
			{"label": "Buy the intel", "hint": "-25 €$, -12 Trace", "fx": {"eddies": -25, "trace": -12}},
			{"label": "Sell her a decoy", "hint": "+40 €$, +10 Trace", "fx": {"eddies": 40, "trace": 10}},
			{"label": "Hang up", "hint": "Nothing happens", "fx": {}},
		]},
	{"id": "medvan", "title": "ABANDONED MED-VAN",
		"text": "A Trauma Team van, doors open, nobody home. The alarm light is still blinking.",
		"choices": [
			{"label": "Patch the crew", "hint": "Heal everyone 35%", "fx": {"heal_pct": 0.35}},
			{"label": "Strip the cyberware", "hint": "Random clinic implant, +6 Trace", "fx": {"item": "clinic", "trace": 6}},
		]},
	{"id": "dead_drop", "title": "CORP DEAD DROP",
		"text": "An unguarded Arasaka data drop on a public node. Too easy?",
		"choices": [
			{"label": "Jack in", "hint": "60%: rare chip. 40%: +15 Trace",
				"fx": {"gamble": {"p": 0.6, "win": {"chip": "rare"}, "lose": {"trace": 15}}}},
			{"label": "Walk away", "hint": "Nothing happens", "fx": {}},
		]},
	{"id": "toll", "title": "MAELSTROM TOLL",
		"text": "Chromed-up gangers block the overpass. 'Road tax, choom.'",
		"choices": [
			{"label": "Pay", "hint": "-30 €$", "fx": {"eddies": -30}},
			{"label": "Fight through", "hint": "An ambush fight, with loot", "fx": {"fight": "ambush"}},
			{"label": "Sneak around", "hint": "+8 Trace", "fx": {"trace": 8}},
		]},
	{"id": "honeypot", "title": "BLACK ICE HONEYPOT",
		"text": "Someone left a hot exploit in a trap. Your deck could compile it, if you survive the backlash.",
		"choices": [
			{"label": "Compile it", "hint": "Upgrade a random chip, +10 Trace", "fx": {"upgrade_chip": 1, "trace": 10}},
			{"label": "Leave it", "hint": "Nothing happens", "fx": {}},
		]},
	{"id": "apprentice", "title": "RIPPERDOC'S APPRENTICE",
		"text": "A kid with a scalpel and big dreams offers a free procedure on your most banged-up merc.",
		"choices": [
			{"label": "Let them try", "hint": "70%: remove a scar. 30%: add one",
				"fx": {"gamble": {"p": 0.7, "win": {"unscar": 1}, "lose": {"scar": 1}}}},
			{"label": "No thanks", "hint": "Nothing happens", "fx": {}},
		]},
	{"id": "street_kid", "title": "STREET KID WITH A BAG",
		"text": "'Found it on a dead solo. Twenty eddies and it's yours.'",
		"choices": [
			{"label": "Buy the bag", "hint": "-20 €$, random street item", "fx": {"eddies": -20, "item": "street"}},
			{"label": "Take it", "hint": "Random street item, a merc gets hurt 20%", "fx": {"item": "street", "hurt_pct": 0.2}},
			{"label": "Wave them off", "hint": "Nothing happens", "fx": {}},
		]},
]


static func pick(rng: RandomNumberGenerator, exclude: Array) -> Dictionary:
	var pool := EVENTS.filter(func(e): return not e.id in exclude)
	if pool.is_empty():
		pool = EVENTS
	return pool[rng.randi() % pool.size()]


static func get_event(id: String) -> Dictionary:
	for e in EVENTS:
		if e.id == id:
			return e
	return {}
