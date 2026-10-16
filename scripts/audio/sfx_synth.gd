class_name SfxSynth
extends RefCounted
## sfxr-style procedural sound generator. Renders parameter presets into 16-bit mono
## AudioStreamWAV at 22050 Hz. No audio assets are shipped: every sound is built here.
##
## A preset is a Dictionary. It is either one layer, or {"layers": [layer, ...]} plus
## optional "peak" (normalization target, default 0.7) and "seed". Layer keys (all optional):
##   wave      "square" | "saw" | "tri" | "sine" | "noise"
##   freq      start frequency, Hz                 freq_end   end frequency (exponential slide)
##   slide_t   slide duration, s (default: whole layer)
##   duty      square duty 0..1                    duty_end   duty at the end
##   attack / sustain / decay   envelope times, s  punch      extra level at sustain start
##   vib_depth vibrato depth (fraction of freq)    vib_rate   vibrato Hz
##   arp_t / arp_mul   frequency jump (multiplier) at time arp_t
##   jumps / jump_dt   list of frequency multipliers stepped every jump_dt s (glitch chirps)
##   trem_rate / trem_depth   amplitude gate/tremolo (alarms)
##   lpf / lpf_end     one-pole low-pass cutoff Hz (0 = off), swept linearly
##   hpf       one-pole high-pass cutoff Hz (0 = off)
##   crush     bit depth (0 = off)                 hold       sample-and-hold factor (downsample)
##   gain      layer gain                          delay      layer start offset, s
##   detune    second oscillator at freq * detune mixed in (0 = off)

const RATE := 22050


static func make(p: Dictionary) -> AudioStreamWAV:
	return to_wav(render(p))


## Renders a preset into float samples (-1..1), normalized to the preset's peak.
static func render(p: Dictionary) -> PackedFloat32Array:
	var st := begin(p)
	for i in layer_count(st):
		step_layer(st, i)
	return finish(st)


## Incremental rendering (one layer per call) so generation can be spread over frames:
##   var st := SfxSynth.begin(preset)
##   for i in SfxSynth.layer_count(st): SfxSynth.step_layer(st, i)
##   var buf := SfxSynth.finish(st)
static func begin(p: Dictionary) -> Dictionary:
	var layers: Array = p.get("layers", [p])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 1234))
	var total := 0.0
	for l in layers:
		total = maxf(total, float(l.get("delay", 0.0)) + _len(l))
	var out := PackedFloat32Array()
	out.resize(int(total * RATE) + 1)
	return {"p": p, "layers": layers, "rng": rng, "out": out}


static func layer_count(st: Dictionary) -> int:
	return (st.layers as Array).size()


static func step_layer(st: Dictionary, i: int) -> void:
	var l: Dictionary = st.layers[i]
	render_layer(st.out, l, int(float(l.get("delay", 0.0)) * RATE), st.rng)


static func finish(st: Dictionary) -> PackedFloat32Array:
	var out: PackedFloat32Array = st.out
	var n := out.size()
	# DC blocker (~25 Hz high-pass): pulse waves with duty != 0.5 carry an offset.
	var x1 := 0.0
	var y1 := 0.0
	for i in n:
		var x := out[i]
		y1 = x - x1 + 0.993 * y1
		x1 = x
		out[i] = y1
	normalize(out, float(st.p.get("peak", 0.7)))
	# Tiny fade-out so nothing clicks at the end.
	var fade := mini(64, n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return out


static func _len(l: Dictionary) -> float:
	return float(l.get("attack", 0.005)) + float(l.get("sustain", 0.05)) + float(l.get("decay", 0.15))


## Adds one layer into `out` starting at sample `offset`.
static func render_layer(out: PackedFloat32Array, l: Dictionary, offset: int, rng: RandomNumberGenerator) -> void:
	var wave: String = l.get("wave", "square")
	var w := 0
	match wave:
		"square": w = 0
		"saw": w = 1
		"tri": w = 2
		"sine": w = 3
		"noise": w = 4
	var att := maxf(0.0005, float(l.get("attack", 0.005)))
	var sus := float(l.get("sustain", 0.05))
	var dec := maxf(0.001, float(l.get("decay", 0.15)))
	var punch := float(l.get("punch", 0.0))
	var length := att + sus + dec
	var n := mini(int(length * RATE), out.size() - offset)
	if n <= 0:
		return
	var freq := float(l.get("freq", 440.0))
	var f_end := float(l.get("freq_end", freq))
	var slide_n := maxi(1, int(float(l.get("slide_t", length)) * RATE))
	var slide_k := pow(f_end / freq, 1.0 / slide_n) if freq > 0.0 and f_end > 0.0 else 1.0
	var duty := float(l.get("duty", 0.5))
	var duty_d := (float(l.get("duty_end", duty)) - duty) / n
	var vib_d := float(l.get("vib_depth", 0.0))
	var vib_r := float(l.get("vib_rate", 6.0)) * TAU / RATE
	var arp_i := int(float(l.get("arp_t", -1.0)) * RATE)
	var arp_m := float(l.get("arp_mul", 1.0))
	var jumps: Array = l.get("jumps", [])
	var jump_n := maxi(1, int(float(l.get("jump_dt", 0.05)) * RATE))
	var trem_r := float(l.get("trem_rate", 0.0)) * TAU / RATE
	var trem_d := float(l.get("trem_depth", 0.0))
	var lpf := float(l.get("lpf", 0.0))
	var lpf_end := float(l.get("lpf_end", lpf))
	var hpf := float(l.get("hpf", 0.0))
	var hp_a := 1.0 - exp(-TAU * hpf / RATE) if hpf > 0.0 else 0.0
	var crush := int(l.get("crush", 0))
	var steps := float(1 << (crush - 1)) if crush > 0 else 0.0
	var hold := maxi(1, int(l.get("hold", 1)))
	var gain := float(l.get("gain", 1.0))
	var detune := float(l.get("detune", 0.0))
	var att_n := att * RATE
	var sus_n := sus * RATE
	var dec_n := dec * RATE

	var ph := 0.0
	var ph2 := 0.0
	var noise_v := rng.randf_range(-1.0, 1.0)
	var lp := 0.0
	var lp_a := 1.0
	var hp_lp := 0.0
	var held := 0.0
	var f := freq
	var has_jumps := not jumps.is_empty()
	var jn := jumps.size()
	var env_sus := att_n + sus_n
	for i in n:
		# Frequency: slide, arpeggio, glitch jumps, vibrato.
		if i < slide_n:
			f *= slide_k
		var ff := f
		if arp_i >= 0 and i >= arp_i:
			ff *= arp_m
		if has_jumps:
			ff *= float(jumps[int(float(i) / jump_n) % jn])
		if vib_d > 0.0:
			ff *= 1.0 + vib_d * sin(vib_r * i)
		var inc := ff / RATE
		# Oscillator (inlined: function calls are expensive in GDScript).
		var s := 0.0
		if w == 4:
			ph += inc * 16.0
			if ph >= 1.0:
				ph -= floorf(ph)
				noise_v = rng.randf_range(-1.0, 1.0)
			s = noise_v
		else:
			ph += inc
			if ph >= 1.0:
				ph -= floorf(ph)
			if w == 0:
				s = 1.0 if ph < duty else -1.0
			elif w == 1:
				s = 2.0 * ph - 1.0
			elif w == 2:
				s = 4.0 * absf(ph - 0.5) - 1.0
			else:
				s = sin(TAU * ph)
			if detune > 0.0:
				ph2 += inc * detune
				if ph2 >= 1.0:
					ph2 -= floorf(ph2)
				var s2 := 0.0
				if w == 0:
					s2 = 1.0 if ph2 < duty else -1.0
				elif w == 1:
					s2 = 2.0 * ph2 - 1.0
				elif w == 2:
					s2 = 4.0 * absf(ph2 - 0.5) - 1.0
				else:
					s2 = sin(TAU * ph2)
				s = (s + s2) * 0.5
			duty += duty_d
		# Envelope.
		var env := 0.0
		if i < att_n:
			env = i / att_n
		elif i < env_sus:
			env = 1.0 + punch * (1.0 - (i - att_n) / sus_n)
		else:
			var t := 1.0 - (i - env_sus) / dec_n
			env = t * t if t > 0.0 else 0.0
		if trem_d > 0.0:
			env *= 1.0 - trem_d * (0.5 + 0.5 * sin(trem_r * i))
		s *= env
		# Filters (low-pass coefficient refreshed every 16 samples).
		if lpf > 0.0:
			if i & 15 == 0:
				var fc := lpf + (lpf_end - lpf) * (float(i) / n)
				lp_a = 1.0 - exp(-TAU * fc / RATE)
			lp += lp_a * (s - lp)
			s = lp
		if hp_a > 0.0:
			hp_lp += hp_a * (s - hp_lp)
			s -= hp_lp
		# Lo-fi.
		if hold > 1:
			if i % hold == 0:
				held = s
			s = held
		if steps > 0.0:
			s = roundf(s * steps) / steps
		out[offset + i] += s * gain


static func normalize(buf: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	if m < 0.00001:
		return
	var k := peak / m
	for i in buf.size():
		buf[i] *= k


## Converts float samples to a 16-bit mono AudioStreamWAV. loop_end = 0 means no loop.
static func to_wav(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = to_pcm16(buf)
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


static func to_pcm16(buf: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return bytes
