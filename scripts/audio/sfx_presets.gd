class_name SfxPresets
extends RefCounted
## Parameter presets for SfxSynth: every game sound effect, by name.
## Also holds per-sound playback rules (voice limit, cooldown, pitch variation, volume).

## name -> [max_voices, cooldown_ms, pitch_var, volume_db]. Missing names use DEFAULT_RULE.
const RULES := {
	"shot": [3, 45, 0.08, -9.0],
	"pistol": [3, 45, 0.08, -9.0],
	"melee_slash": [3, 50, 0.1, -8.0],
	"hit": [4, 30, 0.12, -10.0],
	"crit": [2, 60, 0.06, -5.0],
	"heal": [2, 120, 0.04, -6.0],
	"shield": [1, 200, 0.03, -5.0],
	"zap": [2, 80, 0.08, -6.0],
	"hack_cast": [2, 60, 0.0, -4.0],
	"slam": [1, 150, 0.05, -3.0],
	"explosion": [2, 120, 0.06, -3.0],
	"enemy_death": [3, 60, 0.1, -6.0],
	"runner_down": [1, 300, 0.0, -2.0],
	"coin": [3, 70, 0.06, -10.0],
	"encounter_start": [1, 800, 0.0, -6.0],
	"boss_warning": [1, 2000, 0.0, -4.0],
	"telegraph": [2, 300, 0.0, -5.0],
	"interrupted": [1, 200, 0.0, -2.0],
	"enrage": [1, 1000, 0.0, -4.0],
	"pause_in": [1, 60, 0.0, -5.0],
	"pause_out": [1, 60, 0.0, -6.0],
	"ui_click": [2, 40, 0.05, -10.0],
	"ui_error": [1, 150, 0.0, -7.0],
	"purchase": [1, 150, 0.0, -5.0],
	"hire": [1, 200, 0.0, -5.0],
	"level_up": [1, 500, 0.0, -4.0],
	"mission_success": [1, 1000, 0.0, -3.0],
	"extract": [1, 1000, 0.0, -3.0],
	"flatlined": [1, 1000, 0.0, -3.0],
}
const DEFAULT_RULE := [2, 50, 0.05, -6.0]


static func midi(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Short tonal note layer, used for jingles.
static func _note(m: float, at: float, dur: float, wave := "square", gain := 1.0, extra := {}) -> Dictionary:
	var l := {"wave": wave, "freq": midi(m), "delay": at, "attack": 0.006, "sustain": dur * 0.35,
		"decay": dur * 0.65, "duty": 0.25, "lpf": 3200.0, "gain": gain}
	l.merge(extra, true)
	return l


static func all() -> Dictionary:
	return {
		# --- weapons --------------------------------------------------------
		"shot": {"peak": 0.6, "layers": [
			{"wave": "noise", "freq": 1800.0, "freq_end": 300.0, "attack": 0.001, "sustain": 0.015, "decay": 0.09, "lpf": 5000.0, "lpf_end": 900.0},
			{"wave": "square", "freq": 230.0, "freq_end": 70.0, "duty": 0.3, "attack": 0.001, "sustain": 0.01, "decay": 0.07, "lpf": 2200.0, "gain": 0.6},
		]},
		"pistol": {"peak": 0.6, "layers": [
			{"wave": "noise", "freq": 2600.0, "freq_end": 600.0, "attack": 0.001, "sustain": 0.01, "decay": 0.06, "lpf": 6000.0, "lpf_end": 1500.0},
			{"wave": "saw", "freq": 1300.0, "freq_end": 260.0, "attack": 0.001, "sustain": 0.0, "decay": 0.06, "lpf": 3500.0, "gain": 0.3},
			{"wave": "square", "freq": 420.0, "freq_end": 140.0, "duty": 0.35, "attack": 0.001, "sustain": 0.0, "decay": 0.05, "lpf": 2500.0, "gain": 0.5},
		]},
		"melee_slash": {"peak": 0.55, "layers": [
			{"wave": "noise", "freq": 300.0, "freq_end": 2600.0, "attack": 0.025, "sustain": 0.02, "decay": 0.1, "lpf": 1500.0, "lpf_end": 6000.0, "hpf": 400.0},
			{"wave": "saw", "freq": 1100.0, "freq_end": 650.0, "attack": 0.002, "sustain": 0.02, "decay": 0.08, "lpf": 4000.0, "gain": 0.18, "delay": 0.03},
		]},
		"hit": {"peak": 0.6, "layers": [
			{"wave": "square", "freq": 170.0, "freq_end": 55.0, "duty": 0.4, "attack": 0.001, "sustain": 0.0, "decay": 0.07, "lpf": 1800.0},
			{"wave": "noise", "freq": 900.0, "freq_end": 200.0, "attack": 0.001, "sustain": 0.0, "decay": 0.045, "lpf": 3000.0, "gain": 0.5},
		]},
		"crit": {"peak": 0.7, "layers": [
			{"wave": "square", "freq": 230.0, "freq_end": 45.0, "duty": 0.4, "attack": 0.001, "sustain": 0.01, "decay": 0.12, "lpf": 2000.0},
			{"wave": "noise", "freq": 1400.0, "freq_end": 250.0, "attack": 0.001, "sustain": 0.01, "decay": 0.08, "lpf": 4500.0, "gain": 0.6},
			{"wave": "sine", "freq": 1500.0, "freq_end": 1900.0, "attack": 0.002, "sustain": 0.02, "decay": 0.16, "gain": 0.35, "delay": 0.01},
		]},
		# --- support / soft -----------------------------------------------------
		"heal": {"peak": 0.5, "layers": [
			{"wave": "sine", "freq": midi(76), "arp_t": 0.07, "arp_mul": 1.335, "attack": 0.02, "sustain": 0.1, "decay": 0.25, "vib_depth": 0.01, "vib_rate": 9.0},
			{"wave": "tri", "freq": midi(88), "arp_t": 0.07, "arp_mul": 1.498, "attack": 0.02, "sustain": 0.08, "decay": 0.25, "gain": 0.4, "delay": 0.06},
		]},
		"shield": {"peak": 0.55, "layers": [
			{"wave": "saw", "freq": 110.0, "freq_end": 220.0, "detune": 1.012, "attack": 0.03, "sustain": 0.12, "decay": 0.28, "lpf": 700.0, "lpf_end": 2600.0},
			{"wave": "sine", "freq": 880.0, "freq_end": 1320.0, "attack": 0.02, "sustain": 0.05, "decay": 0.22, "gain": 0.3, "vib_depth": 0.02, "vib_rate": 14.0},
		]},
		"zap": {"peak": 0.5, "layers": [
			{"wave": "square", "freq": 900.0, "duty": 0.3, "jumps": [1.0, 1.6, 0.7, 2.1, 0.9, 1.3], "jump_dt": 0.014, "attack": 0.001, "sustain": 0.05, "decay": 0.13, "lpf": 4500.0, "crush": 5},
			{"wave": "noise", "freq": 5000.0, "attack": 0.001, "sustain": 0.04, "decay": 0.1, "hpf": 2000.0, "trem_rate": 40.0, "trem_depth": 0.8, "gain": 0.45},
		]},
		"hack_cast": {"peak": 0.5, "layers": [
			{"wave": "square", "freq": 700.0, "duty": 0.25, "jumps": [1.0, 1.5, 2.0, 1.335, 2.67, 1.0, 3.0], "jump_dt": 0.022, "attack": 0.002, "sustain": 0.1, "decay": 0.08, "hold": 2, "crush": 6, "lpf": 5000.0},
			{"wave": "sine", "freq": 1800.0, "freq_end": 2700.0, "attack": 0.005, "sustain": 0.03, "decay": 0.12, "gain": 0.35, "delay": 0.05},
			{"wave": "noise", "freq": 3000.0, "attack": 0.001, "sustain": 0.0, "decay": 0.03, "hpf": 1500.0, "gain": 0.3},
		]},
		# --- skills / big hits ------------------------------------------------------
		"slam": {"peak": 0.8, "layers": [
			{"wave": "sine", "freq": 120.0, "freq_end": 32.0, "attack": 0.002, "sustain": 0.05, "decay": 0.35, "punch": 0.5},
			{"wave": "noise", "freq": 600.0, "freq_end": 90.0, "attack": 0.002, "sustain": 0.03, "decay": 0.3, "lpf": 1400.0, "lpf_end": 250.0, "gain": 0.7},
			{"wave": "square", "freq": 72.0, "freq_end": 30.0, "attack": 0.002, "sustain": 0.02, "decay": 0.2, "lpf": 500.0, "gain": 0.35},
		]},
		"explosion": {"peak": 0.8, "layers": [
			{"wave": "noise", "freq": 1300.0, "freq_end": 70.0, "attack": 0.002, "sustain": 0.05, "decay": 0.5, "lpf": 3200.0, "lpf_end": 200.0},
			{"wave": "sine", "freq": 85.0, "freq_end": 28.0, "attack": 0.002, "sustain": 0.04, "decay": 0.4, "gain": 0.8, "punch": 0.4},
			{"wave": "noise", "freq": 6000.0, "attack": 0.01, "sustain": 0.08, "decay": 0.2, "hpf": 3000.0, "trem_rate": 35.0, "trem_depth": 0.9, "gain": 0.25, "delay": 0.04},
		]},
		"enemy_death": {"peak": 0.55, "layers": [
			{"wave": "square", "freq": 620.0, "freq_end": 70.0, "duty": 0.35, "jumps": [1.0, 0.8, 1.25, 0.6], "jump_dt": 0.03, "attack": 0.001, "sustain": 0.03, "decay": 0.25, "hold": 3, "crush": 5, "lpf": 3500.0},
			{"wave": "noise", "freq": 1100.0, "freq_end": 150.0, "attack": 0.001, "sustain": 0.02, "decay": 0.2, "lpf": 2500.0, "gain": 0.6},
		]},
		"runner_down": {"peak": 0.6, "layers": [
			{"wave": "saw", "freq": 220.0, "freq_end": 50.0, "detune": 1.01, "attack": 0.005, "sustain": 0.12, "decay": 0.5, "lpf": 1400.0, "lpf_end": 250.0, "vib_depth": 0.03, "vib_rate": 7.0},
			{"wave": "sine", "freq": 110.0, "freq_end": 38.0, "attack": 0.005, "sustain": 0.1, "decay": 0.5, "gain": 0.8},
		]},
		"coin": {"peak": 0.4, "layers": [
			{"wave": "square", "freq": midi(84), "duty": 0.25, "arp_t": 0.05, "arp_mul": 1.335, "attack": 0.001, "sustain": 0.05, "decay": 0.14, "lpf": 6500.0},
		]},
		# --- encounter / boss -----------------------------------------------------
		"encounter_start": {"peak": 0.5, "layers": [
			_note(81, 0.0, 0.11, "square", 1.0, {"sustain": 0.08, "decay": 0.03, "duty": 0.5, "lpf": 3500.0}),
			_note(76, 0.13, 0.11, "square", 1.0, {"sustain": 0.08, "decay": 0.03, "duty": 0.5, "lpf": 3500.0}),
			_note(81, 0.26, 0.11, "square", 1.0, {"sustain": 0.08, "decay": 0.03, "duty": 0.5, "lpf": 3500.0}),
			_note(76, 0.39, 0.16, "square", 1.0, {"sustain": 0.1, "decay": 0.06, "duty": 0.5, "lpf": 3500.0}),
		]},
		"boss_warning": {"peak": 0.6, "layers": [
			{"wave": "saw", "freq": 620.0, "detune": 1.006, "vib_depth": 0.22, "vib_rate": 2.2, "attack": 0.06, "sustain": 1.0, "decay": 0.3, "lpf": 2200.0},
			{"wave": "square", "freq": 55.0, "duty": 0.4, "attack": 0.05, "sustain": 1.0, "decay": 0.3, "lpf": 400.0, "trem_rate": 4.4, "trem_depth": 0.6, "gain": 0.6},
		]},
		"telegraph": {"peak": 0.5, "layers": [
			{"wave": "saw", "freq": 140.0, "freq_end": 1100.0, "attack": 0.55, "sustain": 0.08, "decay": 0.06, "lpf": 700.0, "lpf_end": 4200.0, "trem_rate": 20.0, "trem_depth": 0.5},
			{"wave": "sine", "freq": 70.0, "freq_end": 140.0, "attack": 0.5, "sustain": 0.1, "decay": 0.06, "gain": 0.5},
		]},
		"interrupted": {"peak": 0.7, "layers": [
			{"wave": "square", "freq": 1300.0, "freq_end": 180.0, "duty": 0.3, "jumps": [1.0, 0.5, 1.0, 0.5, 0.75], "jump_dt": 0.02, "attack": 0.001, "sustain": 0.03, "decay": 0.13, "crush": 4, "hold": 2, "lpf": 4500.0},
			{"wave": "sine", "freq": 210.0, "freq_end": 55.0, "attack": 0.001, "sustain": 0.03, "decay": 0.18, "gain": 0.8},
			{"wave": "noise", "freq": 2500.0, "freq_end": 400.0, "attack": 0.001, "sustain": 0.01, "decay": 0.08, "lpf": 5000.0, "gain": 0.45},
			_note(88, 0.12, 0.25, "tri", 0.45, {"lpf": 0.0}),
		]},
		"enrage": {"peak": 0.6, "layers": [
			{"wave": "saw", "freq": 85.0, "freq_end": 140.0, "detune": 1.03, "vib_depth": 0.12, "vib_rate": 28.0, "attack": 0.05, "sustain": 0.35, "decay": 0.25, "lpf": 900.0, "lpf_end": 1800.0},
			{"wave": "noise", "freq": 400.0, "attack": 0.05, "sustain": 0.3, "decay": 0.25, "lpf": 900.0, "gain": 0.5},
		]},
		# --- active pause -------------------------------------------------------------
		"pause_in": {"peak": 0.55, "layers": [
			{"wave": "noise", "freq": 3200.0, "freq_end": 160.0, "attack": 0.015, "sustain": 0.04, "decay": 0.28, "lpf": 6000.0, "lpf_end": 350.0},
			{"wave": "sine", "freq": 950.0, "freq_end": 110.0, "attack": 0.01, "sustain": 0.05, "decay": 0.27, "gain": 0.45},
			{"wave": "tri", "freq": 1900.0, "freq_end": 1500.0, "attack": 0.002, "sustain": 0.01, "decay": 0.12, "gain": 0.18, "crush": 5},
		]},
		"pause_out": {"peak": 0.5, "layers": [
			{"wave": "noise", "freq": 160.0, "freq_end": 3200.0, "attack": 0.2, "sustain": 0.02, "decay": 0.07, "lpf": 400.0, "lpf_end": 6500.0},
			{"wave": "sine", "freq": 120.0, "freq_end": 950.0, "attack": 0.19, "sustain": 0.02, "decay": 0.07, "gain": 0.45},
		]},
		# --- UI / hub -------------------------------------------------------------------
		"ui_click": {"peak": 0.35, "layers": [
			{"wave": "square", "freq": 1700.0, "freq_end": 1300.0, "duty": 0.5, "attack": 0.001, "sustain": 0.0, "decay": 0.03, "lpf": 5000.0},
			{"wave": "tri", "freq": 850.0, "attack": 0.001, "sustain": 0.0, "decay": 0.025, "gain": 0.5},
		]},
		"ui_error": {"peak": 0.45, "layers": [
			{"wave": "square", "freq": 185.0, "duty": 0.45, "attack": 0.002, "sustain": 0.06, "decay": 0.03, "lpf": 1600.0},
			{"wave": "square", "freq": 139.0, "duty": 0.45, "attack": 0.002, "sustain": 0.09, "decay": 0.06, "lpf": 1600.0, "delay": 0.11},
		]},
		"purchase": {"peak": 0.5, "layers": [
			_note(79, 0.0, 0.09, "square", 0.8),
			_note(84, 0.06, 0.09, "square", 0.8),
			_note(91, 0.12, 0.3, "square", 0.9, {"vib_depth": 0.008, "vib_rate": 10.0}),
			{"wave": "noise", "freq": 7000.0, "hpf": 4000.0, "attack": 0.002, "sustain": 0.02, "decay": 0.15, "gain": 0.25, "delay": 0.12},
		]},
		"hire": {"peak": 0.5, "layers": [
			_note(69, 0.0, 0.2, "tri", 1.0, {"lpf": 0.0}),
			_note(73, 0.07, 0.2, "tri", 1.0, {"lpf": 0.0}),
			_note(76, 0.14, 0.35, "tri", 1.0, {"lpf": 0.0}),
			{"wave": "saw", "freq": midi(45), "detune": 1.01, "attack": 0.01, "sustain": 0.2, "decay": 0.25, "lpf": 800.0, "gain": 0.5},
		]},
		"level_up": {"peak": 0.5, "layers": [
			_note(69, 0.0, 0.08), _note(72, 0.06, 0.08), _note(76, 0.12, 0.08), _note(79, 0.18, 0.08),
			_note(81, 0.24, 0.45, "square", 1.0, {"vib_depth": 0.012, "vib_rate": 9.0}),
			_note(88, 0.24, 0.45, "tri", 0.4, {"lpf": 0.0}),
		]},
		"mission_success": {"peak": 0.55, "layers": [
			_note(69, 0.0, 0.14, "saw", 0.8, {"lpf": 2500.0}),
			_note(72, 0.12, 0.14, "saw", 0.8, {"lpf": 2500.0}),
			_note(76, 0.24, 0.14, "saw", 0.8, {"lpf": 2500.0}),
			_note(81, 0.36, 0.9, "saw", 0.9, {"lpf": 2800.0, "detune": 1.008, "vib_depth": 0.006, "vib_rate": 6.0}),
			_note(64, 0.36, 0.9, "saw", 0.5, {"lpf": 1500.0, "detune": 1.008}),
			_note(57, 0.36, 0.9, "square", 0.5, {"lpf": 800.0}),
			_note(93, 0.48, 0.5, "tri", 0.25, {"lpf": 0.0}),
		]},
		"extract": {"peak": 0.55, "layers": [
			{"wave": "noise", "freq": 200.0, "freq_end": 2500.0, "attack": 0.25, "sustain": 0.05, "decay": 0.2, "lpf": 500.0, "lpf_end": 5000.0, "gain": 0.6},
			{"wave": "sine", "freq": midi(64), "freq_end": midi(76), "attack": 0.2, "sustain": 0.05, "decay": 0.1, "gain": 0.5},
			_note(76, 0.3, 0.15, "square", 0.6),
			_note(83, 0.42, 0.45, "square", 0.6, {"vib_depth": 0.008, "vib_rate": 7.0}),
		]},
		"flatlined": {"peak": 0.55, "layers": [
			_note(83, 0.0, 0.1, "sine", 0.8, {"lpf": 0.0, "sustain": 0.07, "decay": 0.03}),
			_note(83, 0.45, 0.1, "sine", 0.8, {"lpf": 0.0, "sustain": 0.07, "decay": 0.03}),
			{"wave": "sine", "freq": midi(83), "delay": 0.9, "attack": 0.005, "sustain": 1.1, "decay": 0.4, "gain": 0.7},
			{"wave": "saw", "freq": 220.0, "freq_end": 45.0, "detune": 1.015, "delay": 0.9, "attack": 0.01, "sustain": 0.3, "decay": 0.9, "lpf": 1200.0, "lpf_end": 200.0, "gain": 0.6},
		]},
	}
