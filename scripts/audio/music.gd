class_name MusicGen
extends RefCounted
## Procedural synthwave loop sequencer. Pre-renders a whole loop (bass, pad, arp, drums,
## optional lead) into one looping AudioStreamWAV. Rendering is split into small jobs so
## it can be spread across frames (no threads: the web export may not have them).
##
##   var g := MusicGen.create("hub")      # "hub" | "mission" | "boss"
##   while not g.step(4000): await get_tree().process_frame
##   player.stream = g.stream
##
## "boss" is the mission loop plus a lead line; pass the finished mission MusicGen to
## create("boss", mission_gen) to reuse its buffer (same length, so playback can switch
## at the same position).

const RATE := SfxSynth.RATE
const PAD_SPLIT := 8  # pad render jobs per bar
const MUFFLE_HZ := 520.0
const MUFFLE_GAIN := 1.25

const CHORDS := {
	"Am": [57, 60, 64], "F": [57, 60, 65], "C": [55, 60, 64], "G": [55, 59, 62],
	"Dm": [57, 62, 65], "Em": [55, 59, 64], "E": [56, 59, 64],
}
const ROOTS := {"Am": 45, "F": 41, "C": 48, "G": 43, "Dm": 38, "Em": 40, "E": 40}

const TRACKS := {
	"hub": {"bpm": 88.0, "prog": ["Am", "Am", "F", "F", "Dm", "Dm", "E", "E"], "seed": 7},
	"mission": {"bpm": 112.0, "prog": ["Am", "F", "C", "G", "Am", "F", "C", "E"], "seed": 11},
}
## Boss lead: [bar, beat, length in beats, midi] (A minor pentatonic-ish hook).
const BOSS_LEAD := [
	[0, 0.0, 1.5, 76], [0, 1.5, 0.5, 74], [0, 2.0, 2.0, 72],
	[1, 0.0, 1.0, 69], [1, 1.0, 1.0, 72], [1, 2.0, 2.0, 77],
	[2, 0.0, 1.5, 76], [2, 1.5, 0.5, 79], [2, 2.0, 2.0, 84],
	[3, 0.0, 1.0, 83], [3, 1.0, 1.0, 79], [3, 2.0, 2.0, 74],
	[4, 0.0, 1.5, 76], [4, 1.5, 0.5, 74], [4, 2.0, 2.0, 72],
	[5, 0.0, 1.0, 69], [5, 1.0, 1.0, 72], [5, 2.0, 2.0, 77],
	[6, 0.0, 1.0, 79], [6, 1.0, 1.0, 76], [6, 2.0, 2.0, 84],
	[7, 0.0, 2.0, 83], [7, 2.0, 1.0, 80], [7, 3.0, 1.0, 76],
]

var track := ""
var stream: AudioStreamWAV
## Same loop, low-passed: played in sync and crossfaded in during the active pause.
## (A pre-rendered copy instead of a bus effect: web Sample playback has no bus effects.)
var muffled: AudioStreamWAV
var done := false
var last_job := ""  # name of the last job run (profiling)

var _bpm := 100.0
var _beat := 0.0      # samples per beat
var _bar := 0         # samples per bar
var _n := 0           # loop length in samples
var _main := PackedFloat32Array()   # drums + dry parts
var _pump := PackedFloat32Array()   # bass + pad (sidechain-ducked by the kick)
var _send := PackedFloat32Array()   # arp / lead (through the delay)
var _jobs: Array[Callable] = []
var _kick: PackedFloat32Array
var _snare: PackedFloat32Array
var _hat: PackedFloat32Array
var _ohat: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _peak := 0.0
var _bytes := PackedByteArray()
var _mbytes := PackedByteArray()
var _mlp1 := 0.0
var _mlp2 := 0.0
var _pad_cache := {}  # chord -> one bar of rendered pad
var _note_cache := {}  # note key -> rendered note (unit gain)


static func create(name: String, base: MusicGen = null) -> MusicGen:
	var g := MusicGen.new()
	g.track = name
	if name == "boss":
		g._plan_boss(base)
	else:
		g._plan(TRACKS.get(name, TRACKS.mission))
	return g


## Runs jobs for up to budget_usec microseconds. Returns true when the loop is ready.
func step(budget_usec := 4000) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _jobs.is_empty():
		var j: Callable = _jobs.pop_front()
		last_job = j.get_method()
		j.call()
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	return done


func render_all() -> void:
	while not step(1000000):
		pass


## Mixed float buffer (valid once done); used by the boss variation and the preview tool.
func buffer() -> PackedFloat32Array:
	return _main


func loop_seconds() -> float:
	return float(_n) / RATE


# --- planning -----------------------------------------------------------------------

func _setup(bpm: float, bars: int) -> void:
	_bpm = bpm
	_beat = 60.0 / bpm * RATE
	_bar = int(_beat * 4.0)
	_n = _bar * bars
	_main.resize(_n)
	_pump.resize(_n)
	_send.resize(_n)


func _plan(t: Dictionary) -> void:
	var prog: Array = t.prog
	_rng.seed = int(t.seed)
	_setup(float(t.bpm), prog.size())
	var hub := track == "hub"
	_jobs.append(_make_drums)
	var planned := {}
	for b in prog.size():
		var ch: String = prog[b]
		if not planned.has(ch):
			planned[ch] = true
			for q in PAD_SPLIT:
				_jobs.append(_pad_range.bind(ch, q, 0.32 if hub else 0.22))
		_jobs.append(_pad_copy.bind(b, ch))
		_jobs.append(_bass_bar.bind(b, ch, hub))
		_arp_bar(b, ch, hub)  # queues one job per note
		_jobs.append(_drum_bar.bind(b, hub))
	_add_finish_jobs(not hub, 0.75, 0.42 if hub else 0.32)


func _plan_boss(base: MusicGen) -> void:
	if base == null or not base.done:
		base = MusicGen.create("mission")
		base.render_all()
	_bpm = base._bpm
	_beat = base._beat
	_bar = base._bar
	_n = base._n
	_main = base._main.duplicate()
	_send.resize(_n)
	_pump = PackedFloat32Array()
	for i in BOSS_LEAD.size():
		_jobs.append(_lead_note.bind(BOSS_LEAD[i]))
	_jobs.append(_boss_hits)
	_add_finish_jobs(false, 0.75, 0.3, 0.6)


func _add_finish_jobs(pump: bool, delay_beats: float, fb: float, send_gain := 1.0) -> void:
	var chunk := _bar
	var s := 0
	while s < _n:
		_jobs.append(_delay_range.bind(s, mini(s + chunk, _n), delay_beats, fb))
		s += chunk
	s = 0
	while s < _n:
		_jobs.append(_mix_range.bind(s, mini(s + chunk, _n), pump, send_gain))
		s += chunk
	_add_output_jobs()


func _add_output_jobs() -> void:
	var chunk := _bar
	var s := 0
	_bytes.resize(_n * 2)
	_mbytes.resize(_n * 2)
	while s < _n:
		_jobs.append(_pcm_range.bind(s, mini(s + chunk, _n)))
		s += chunk
	_jobs.append(_finalize)


# --- instruments ---------------------------------------------------------------------

func _make_drums() -> void:
	_kick = SfxSynth.render({"peak": 1.0, "layers": [
		{"wave": "sine", "freq": 160.0, "freq_end": 42.0, "slide_t": 0.12, "attack": 0.001, "sustain": 0.04, "decay": 0.28},
		{"wave": "noise", "freq": 3000.0, "attack": 0.001, "sustain": 0.0, "decay": 0.012, "lpf": 4000.0, "gain": 0.4},
	]})
	_snare = SfxSynth.render({"peak": 0.75, "layers": [
		{"wave": "noise", "freq": 6000.0, "attack": 0.001, "sustain": 0.02, "decay": 0.22, "lpf": 7000.0, "lpf_end": 2500.0, "hpf": 500.0},
		{"wave": "tri", "freq": 200.0, "freq_end": 150.0, "attack": 0.001, "sustain": 0.01, "decay": 0.09, "gain": 0.7},
	]})
	_hat = SfxSynth.render({"peak": 0.3, "wave": "noise", "freq": 9000.0, "attack": 0.001, "sustain": 0.0, "decay": 0.035, "hpf": 5000.0})
	_ohat = SfxSynth.render({"peak": 0.25, "wave": "noise", "freq": 9000.0, "attack": 0.002, "sustain": 0.02, "decay": 0.14, "hpf": 5000.0})


func _drum_bar(b: int, hub: bool) -> void:
	var s0 := b * _bar
	var e := _beat
	if hub:
		# Half-time: kick on 1 and the "and" of 3, snare on 3, soft 8th hats.
		_mix_in(_main, _kick, s0, 0.8)
		_mix_in(_main, _kick, s0 + int(e * 2.5), 0.55)
		_mix_in(_main, _snare, s0 + int(e * 2.0), 0.5)
		for k in 8:
			_mix_in(_main, _hat, s0 + int(e * 0.5 * k), 0.35 if k % 2 == 1 else 0.18)
		if b % 2 == 1:
			_mix_in(_main, _ohat, s0 + int(e * 3.5), 0.5)
	else:
		# Four on the floor, snare on 2 and 4, 16th hats with off-beat open hats.
		for k in 4:
			_mix_in(_main, _kick, s0 + int(e * k), 0.9)
		_mix_in(_main, _snare, s0 + int(e), 0.7)
		_mix_in(_main, _snare, s0 + int(e * 3.0), 0.7)
		for k in 16:
			if k % 4 == 2:
				_mix_in(_main, _ohat, s0 + int(e * 0.25 * k), 0.55)
			else:
				_mix_in(_main, _hat, s0 + int(e * 0.25 * k), 0.4 if k % 2 == 0 else 0.22)
		if b == 7:  # small fill into the loop point
			_mix_in(_main, _snare, s0 + int(e * 3.5), 0.45)
			_mix_in(_main, _snare, s0 + int(e * 3.75), 0.55)


## Pad: 2 detuned saws per chord tone (3 tones, unrolled), low-passed. Renders one
## slice of a bar-long chord into a per-chord cache (bars with the same chord reuse it).
## Stateless (phase from the sample index) so slices can be rendered independently.
func _pad_range(ch: String, q: int, gain: float) -> void:
	if not _pad_cache.has(ch):
		var c := PackedFloat32Array()
		c.resize(_bar)
		_pad_cache[ch] = c
	var buf: PackedFloat32Array = _pad_cache[ch]
	var notes: Array = CHORDS[ch]
	var f0 := SfxPresets.midi(float(notes[0])) / RATE
	var f1 := SfxPresets.midi(float(notes[1])) / RATE
	var f2 := SfxPresets.midi(float(notes[2])) / RATE
	var a0 := f0 * 0.996
	var b0 := f0 * 1.004
	var a1 := f1 * 0.996
	var b1 := f1 * 1.004
	var a2 := f2 * 0.996
	var b2 := f2 * 1.004
	var slice := int(float(_bar) / PAD_SPLIT)
	var i0 := q * slice
	var i1 := i0 + slice if q < PAD_SPLIT - 1 else _bar
	var att := 0.25 * RATE
	var rel := 0.15 * RATE
	var a := 1.0 - exp(-TAU * (900.0 if track == "hub" else 1300.0) / RATE)
	var lp := 0.0
	var g := gain / 6.0
	# Warm the filter up a little before the slice to avoid a step at slice borders.
	var warm := mini(48, i0)
	for i in range(i0 - warm, i1):
		var p0 := a0 * i
		var p1 := b0 * i
		var p2 := a1 * i
		var p3 := b1 * i
		var p4 := a2 * i
		var p5 := b2 * i
		# Sum of saws 2*frac(p)-1, folded together.
		var s := 2.0 * (p0 + p1 + p2 + p3 + p4 + p5 - floorf(p0) - floorf(p1) - floorf(p2) - floorf(p3) - floorf(p4) - floorf(p5)) - 6.0
		lp += a * (s - lp)
		if i < i0:
			continue
		var env := minf(1.0, i / att)
		var tail := _bar - i
		if tail < rel:
			env *= tail / rel
		buf[i] = lp * g * env


func _pad_copy(b: int, ch: String) -> void:
	var buf: PackedFloat32Array = _pad_cache[ch]
	var s0 := b * _bar
	for i in _bar:
		_pump[s0 + i] += buf[i]


func _bass_bar(b: int, ch: String, hub: bool) -> void:
	var root: int = ROOTS[ch]
	var s0 := b * _bar
	if hub:
		# Slow pulsing 8ths with a ghost octave.
		for k in 8:
			var m := root + (12 if k == 7 else 0)
			_bass_note(s0 + int(_beat * 0.5 * k), int(_beat * 0.45), m, 0.55 if k % 2 == 0 else 0.35, 900.0)
	else:
		# Driving 16ths: root, root, octave, root.
		var pat := [0, 0, 12, 0]
		for k in 16:
			_bass_note(s0 + int(_beat * 0.25 * k), int(_beat * 0.22), root + pat[k % 4], 0.6 if k % 4 == 0 else 0.42, 1500.0)


## Bass/pluck notes repeat a lot, so each distinct note is rendered once and mixed in.
func _bass_note(start: int, length: int, m: int, gain: float, cutoff: float) -> void:
	var key := "b%d_%d_%d" % [m, length, int(cutoff)]
	if not _note_cache.has(key):
		_note_cache[key] = _render_bass(length, m, cutoff)
	_mix_in(_pump, _note_cache[key], start, gain)


func _render_bass(length: int, m: int, cutoff: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(length)
	var inc := SfxPresets.midi(float(m)) / RATE
	var ph := 0.0
	var ph2 := 0.25
	var lp := 0.0
	var a := 1.0
	var dec := float(length)
	for i in length:
		ph += inc
		ph -= floorf(ph)
		ph2 += inc * 0.5
		ph2 -= floorf(ph2)
		var s := (2.0 * ph - 1.0) * 0.7 + (1.0 if ph2 < 0.5 else -1.0) * 0.35
		var tt := float(i) / dec
		if i & 15 == 0:
			a = 1.0 - exp(-TAU * (cutoff * (1.0 - 0.7 * tt) + 120.0) / RATE)
		lp += a * (s - lp)
		var env := minf(1.0, i / 40.0) * (1.0 - tt * 0.6)
		if i > length - 60:
			env *= (length - i) / 60.0
		out[i] = lp * env
	return out


func _arp_bar(b: int, ch: String, hub: bool) -> void:
	var notes: Array = CHORDS[ch]
	var s0 := b * _bar
	if hub:
		# Sparse up-arp of plucks, an octave up, fed into the delay.
		var seq := [0, 1, 2, 1]
		for k in 4:
			var m: int = notes[seq[k]] + 12
			_jobs.append(_pluck.bind(s0 + int(_beat * k + _beat * 0.5), int(_beat * 0.9), m, 0.26, "tri"))
	elif b >= 4:
		# Second half: 16th up/down square arp for momentum.
		var seq := [0, 1, 2, 3, 2, 1]
		for k in 16:
			var idx: int = seq[k % seq.size()]
			var m: int = (notes[idx] if idx < 3 else notes[0] + 12) + 12
			_jobs.append(_pluck.bind(s0 + int(_beat * 0.25 * k), int(_beat * 0.24), m, 0.16, "square"))
	else:
		# First half: offbeat stabs.
		for k in 4:
			for m in notes:
				_jobs.append(_pluck.bind(s0 + int(_beat * k + _beat * 0.5), int(_beat * 0.3), int(m) + 12, 0.07, "saw"))


func _pluck(start: int, length: int, m: int, gain: float, wave: String) -> void:
	var key := "p%d_%d_%s" % [m, length, wave]
	if not _note_cache.has(key):
		_note_cache[key] = _render_pluck(length, m, wave)
	_mix_in(_send, _note_cache[key], start, gain)


func _render_pluck(length: int, m: int, wave: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(length)
	var inc := SfxPresets.midi(float(m)) / RATE
	var ph := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 3000.0 / RATE)
	var w := 0 if wave == "square" else (1 if wave == "saw" else 2)
	for i in length:
		ph += inc
		ph -= floorf(ph)
		var s := 0.0
		if w == 0:
			s = 1.0 if ph < 0.3 else -1.0
		elif w == 1:
			s = 2.0 * ph - 1.0
		else:
			s = 4.0 * absf(ph - 0.5) - 1.0
		lp += a * (s - lp)
		var tt := 1.0 - float(i) / length
		out[i] = lp * minf(1.0, i / 30.0) * tt * tt
	return out


func _lead_note(note: Array) -> void:
	var start := int(int(note[0]) * _bar + float(note[1]) * _beat)
	var length := int(float(note[2]) * _beat)
	var f := SfxPresets.midi(float(note[3]))
	var ph := 0.0
	var ph2 := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 2400.0 / RATE)
	var vib := TAU * 5.5 / RATE
	for i in length:
		var v := 1.0 + (0.006 * sin(vib * i) if i > 4000 else 0.0)
		ph += f * v / RATE
		ph -= floorf(ph)
		ph2 += f * v * 1.007 / RATE
		ph2 -= floorf(ph2)
		var s := (2.0 * ph - 1.0) + (2.0 * ph2 - 1.0)
		lp += a * (s - lp)
		var env := minf(1.0, i / 300.0)
		var tail := length - i
		if tail < 1200:
			env *= tail / 1200.0
		var idx := start + i
		if idx >= _n:
			idx -= _n
		_send[idx] += lp * env * 0.16


func _boss_hits() -> void:
	# Extra low "impact" every 2 bars to make the boss loop heavier.
	var hit := SfxSynth.render({"peak": 0.6, "layers": [
		{"wave": "sine", "freq": 90.0, "freq_end": 30.0, "attack": 0.002, "sustain": 0.05, "decay": 0.5},
		{"wave": "noise", "freq": 900.0, "freq_end": 100.0, "attack": 0.002, "sustain": 0.02, "decay": 0.4, "lpf": 1500.0, "lpf_end": 200.0, "gain": 0.5},
	]})
	for b in range(0, int(float(_n) / _bar), 2):
		_mix_in(_main, hit, b * _bar, 0.5)


# --- mixing ------------------------------------------------------------------------

func _mix_in(dst: PackedFloat32Array, src: PackedFloat32Array, start: int, gain: float) -> void:
	var n := _n
	for i in src.size():
		var idx := start + i
		if idx >= n:
			idx -= n
		dst[idx] += src[i] * gain


## Feedback delay on the send buffer (wraps around so the echo tail loops seamlessly).
func _delay_range(i0: int, i1: int, beats: float, fb: float) -> void:
	var d := int(_beat * beats)
	var n := _n
	for i in range(i0, i1):
		var j := i - d
		if j < 0:
			j += n
		_send[i] += _send[j] * fb


func _mix_range(i0: int, i1: int, pump: bool, send_gain: float) -> void:
	var has_pump := _pump.size() == _n
	var beat := _beat
	for i in range(i0, i1):
		var s := _main[i] + _send[i] * send_gain
		if has_pump:
			var p := _pump[i]
			if pump:
				var t := fmod(float(i), beat) / beat
				p *= 0.45 + 0.55 * minf(1.0, t * 3.0)
			s += p
		_main[i] = s
		var av := absf(s)
		if av > _peak:
			_peak = av


## Normalizes a range to 16-bit PCM and also writes the "muffled" copy (2-pole low-pass)
## that plays in sync during the active pause. Ranges must run in order (filter state).
func _pcm_range(i0: int, i1: int) -> void:
	var k := 0.6 / _peak if _peak > 0.0001 else 1.0
	var a := 1.0 - exp(-TAU * MUFFLE_HZ / RATE)
	var l1 := _mlp1
	var l2 := _mlp2
	if i0 == 0:
		# Warm the filter on the loop tail so the muffled loop wraps without a click.
		for i in range(maxi(0, _n - 2048), _n):
			l1 += a * (_main[i] * k - l1)
			l2 += a * (l1 - l2)
	for i in range(i0, i1):
		var v := _main[i] * k
		_main[i] = v
		_bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
		l1 += a * (v - l1)
		l2 += a * (l1 - l2)
		_mbytes.encode_s16(i * 2, int(clampf(l2 * MUFFLE_GAIN, -1.0, 1.0) * 32767.0))
	_mlp1 = l1
	_mlp2 = l2


func _finalize() -> void:
	stream = _make_stream(_bytes)
	muffled = _make_stream(_mbytes)
	_bytes = PackedByteArray()
	_mbytes = PackedByteArray()
	_send = PackedFloat32Array()
	_pump = PackedFloat32Array()
	done = true
	_pad_cache = {}
	_note_cache = {}


func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = _n
	return w


## Frees the float mix buffer once the stream is all that's needed.
func release() -> void:
	_main = PackedFloat32Array()


## Drops pending jobs (they hold Callables bound to this object, i.e. a reference cycle).
func cancel() -> void:
	_jobs.clear()
