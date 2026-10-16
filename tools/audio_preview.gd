extends SceneTree
## Dev tool: renders every procedural SFX and the music loops to WAV files and prints
## waveform stats (duration, peak, RMS, clipped samples) plus generation timings.
##   godot --headless --path . --script res://tools/audio_preview.gd -- [out_dir]
## Default out_dir: /private/tmp/claude-501/audio

var _out := "/private/tmp/claude-501/audio"
var _problems := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var presets := SfxPresets.all()
	var total_us := 0
	print("%-16s %7s %6s %6s %5s %6s %7s" % ["sfx", "dur_s", "peak", "rms", "clip", "bright", "gen_ms"])
	for name in presets:
		var t0 := Time.get_ticks_usec()
		var buf := SfxSynth.render(presets[name])
		var wav := SfxSynth.to_wav(buf)
		var us := Time.get_ticks_usec() - t0
		total_us += us
		_report(name, buf, us)
		wav.save_to_wav("%s/sfx_%s.wav" % [_out, name])
	print("SFX total generation: %.1f ms for %d sounds" % [total_us / 1000.0, presets.size()])

	var mission: MusicGen = null
	for track in ["hub", "mission", "boss"]:
		var t0 := Time.get_ticks_usec()
		var g := MusicGen.create(track, mission)
		var jobs := 0
		var worst := 0
		var worst_name := ""
		var prof := {}
		while not g.done:
			var j0 := Time.get_ticks_usec()
			g.step(0)  # one job at a time, to measure the worst single job
			var dj := Time.get_ticks_usec() - j0
			prof[g.last_job] = prof.get(g.last_job, 0) + dj
			if dj > worst:
				worst = dj
				worst_name = g.last_job
			jobs += 1
		var us := Time.get_ticks_usec() - t0
		if track == "mission":
			mission = g
		_report("music_" + track, g.buffer(), us)
		print("    loop %.2f s, %d jobs, worst job %.1f ms (%s)" % [g.loop_seconds(), jobs, worst / 1000.0, worst_name])
		for k in prof:
			print("      %-14s %6.1f ms" % [k, prof[k] / 1000.0])
		g.stream.save_to_wav("%s/music_%s.wav" % [_out, track])
		g.muffled.save_to_wav("%s/music_%s_muffled.wav" % [_out, track])
	print("wrote WAVs to ", _out)
	print("PROBLEMS: %d" % _problems)
	quit(1 if _problems > 0 else 0)


func _report(name: String, buf: PackedFloat32Array, us: int) -> void:
	var peak := 0.0
	var sum := 0.0
	var clip := 0
	var dsum := 0.0
	var mean := 0.0
	var prev := buf[buf.size() - 1] if name.begins_with("music") else 0.0
	for v in buf:
		var a := absf(v)
		peak = maxf(peak, a)
		sum += v * v
		dsum += (v - prev) * (v - prev)
		prev = v
		mean += v
		if a >= 0.999:
			clip += 1
	var rms := sqrt(sum / maxi(1, buf.size()))
	mean /= maxi(1, buf.size())
	# Brightness proxy: RMS of the first difference over RMS (a sine at 1 kHz ~0.28, 4 kHz ~1.1).
	var bright := sqrt(dsum / maxi(1, buf.size())) / maxf(rms, 0.00001)
	var dur := float(buf.size()) / SfxSynth.RATE
	var flag := ""
	if peak < 0.05 or rms < 0.005:
		flag = "  <-- SILENT?"
		_problems += 1
	elif clip > 0:
		flag = "  <-- CLIPS"
		_problems += 1
	elif dur > 3.0 and not name.begins_with("music"):
		flag = "  <-- LONG"
	elif bright > 1.0:
		flag = "  <-- HARSH?"
	elif absf(mean) > 0.02:
		flag = "  <-- DC OFFSET"
	print("%-16s %7.3f %6.3f %6.3f %5d %6.2f %7.1f%s" % [name, dur, peak, rms, clip, bright, us / 1000.0, flag])
