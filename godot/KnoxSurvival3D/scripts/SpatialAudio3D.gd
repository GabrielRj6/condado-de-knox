extends Node3D
class_name SpatialAudio3D

## Motor de Audio Espacial 3D (Godot 4) com sintese PCM procedural em tempo de carregamento.
## - Tiros direcionais (esquerda/direita/frente/tras) com filtro acustico traseiro,
##   atenuacao ate 500m, atraso fisico da velocidade do som e estalo supersonico de bala.
## - Motores continuos 3D (Carro, Moto Trail 450, Moto Street 600), drift, ignicao e buzinas.
## - Vozes guturais 3D de zumbis (idle, alert, chase, attack, hurt, death) com limite de vozes.

const SAMPLE_RATE: int = 22050
const SPEED_OF_SOUND: float = 343.0

var clip_rifle: AudioStreamWAV
var clip_pistol: AudioStreamWAV
var clip_sniper: AudioStreamWAV
var clip_suppressed: AudioStreamWAV
var clip_whiz: AudioStreamWAV
var clip_explosion: AudioStreamWAV
var clip_horn_car: AudioStreamWAV
var clip_horn_moto: AudioStreamWAV
var clip_start_car: AudioStreamWAV
var clip_start_moto: AudioStreamWAV
var clip_engine_car: AudioStreamWAV
var clip_engine_trail: AudioStreamWAV
var clip_engine_street: AudioStreamWAV
var clip_drift_loop: AudioStreamWAV
var clip_zombie_idle: AudioStreamWAV
var clip_zombie_alert: AudioStreamWAV
var clip_zombie_attack: AudioStreamWAV
var clip_zombie_death: AudioStreamWAV

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_idx: int = 0
var _active_zombie_voices: int = 0
var _last_zombie_voice_ms: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_generate_all_clips()
	for i in range(32):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 520.0
		p.unit_size = 18.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.35
		add_child(p)
		_pool.append(p)


func _next_voice() -> AudioStreamPlayer3D:
	if _pool.is_empty():
		return null
	var p: AudioStreamPlayer3D = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	return p


func play_gunshot_3d(profile: String, muzzle_pos: Vector3, end_pos: Vector3, is_local: bool) -> void:
	if _pool.is_empty():
		return
	var clip: AudioStreamWAV = clip_rifle
	match profile:
		"pistol": clip = clip_pistol
		"sniper": clip = clip_sniper
		"suppressed": clip = clip_suppressed
		_: clip = clip_rifle

	if is_local:
		var v := _next_voice()
		if v == null:
			return
		v.global_position = muzzle_pos
		v.stream = clip
		v.unit_size = 24.0
		v.max_distance = 120.0
		v.volume_db = -6.0 if profile == "suppressed" else 0.0
		v.pitch_scale = randf_range(0.96, 1.04)
		v.attenuation_filter_cutoff_hz = 16000.0
		v.attenuation_filter_db = -2.0
		v.play()
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_src: Vector3 = muzzle_pos - cam.global_position
	var dist: float = to_src.length()
	var max_d: float = 135.0 if profile == "suppressed" else (520.0 if profile == "sniper" else 460.0)
	if dist >= max_d:
		return

	var dir: Vector3 = to_src / maxf(0.001, dist)
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var front_dot: float = dir.dot(cam_fwd) # +1 frente, -1 tras

	# Atraso fisico da velocidade do som (perto = instantaneo, 260m = ~0.75s)
	var delay: float = minf(dist / SPEED_OF_SOUND, 1.4)
	# Filtro pinna traseiro + distancia: tiros atras ficam mais graves/abafados que tiros a frente!
	var dist_norm: float = clampf(dist / max_d, 0.0, 1.0)
	var base_cutoff: float = lerpf(14500.0, 900.0, pow(dist_norm, 0.72))
	var rear_mult: float = lerpf(1.0, 0.38, clampf(-front_dot, 0.0, 1.0))
	var cutoff_hz: float = clampf(base_cutoff * rear_mult, 680.0, 16000.0)
	var rear_db: float = lerpf(0.0, -3.2, clampf(-front_dot, 0.0, 1.0))
	var dist_db: float = lerpf(1.0, -28.0, pow(dist_norm, 0.65))

	_schedule_3d(clip, muzzle_pos, dist_db + rear_db, cutoff_hz, randf_range(0.94, 1.05), max_d, delay)

	# Estalo supersonico direcional quando a bala passa perto da camera!
	if profile != "suppressed" and dist > 10.0:
		var ab: Vector3 = end_pos - muzzle_pos
		var len2: float = ab.length_squared()
		if len2 > 4.0:
			var t: float = clampf((cam.global_position - muzzle_pos).dot(ab) / len2, 0.0, 1.0)
			if t > 0.05:
				var closest: Vector3 = muzzle_pos + ab * t
				var pass_d: float = cam.global_position.distance_to(closest)
				if pass_d < 12.5:
					var w_db: float = lerpf(-2.0, -18.0, pass_d / 12.5)
					_schedule_3d(clip_whiz, closest, w_db, 11000.0, randf_range(0.92, 1.12), 40.0, 0.01)


func play_zombie_vocal_3d(vocal_type: String, world_pos: Vector3, pitch_var: float = 1.0) -> void:
	if _pool.is_empty():
		return
	var urgent: bool = vocal_type in ["alert", "attack", "hurt", "death"]
	if _active_zombie_voices >= (6 if urgent else 4):
		return
	var now_ms: int = Time.get_ticks_msec()
	if not urgent and (now_ms - _last_zombie_voice_ms) < 280:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var max_d: float = 54.0 if vocal_type in ["alert", "death"] else 38.0
	var dist: float = cam.global_position.distance_to(world_pos)
	if dist > max_d:
		return

	var clip: AudioStreamWAV = clip_zombie_idle
	match vocal_type:
		"alert": clip = clip_zombie_alert
		"attack": clip = clip_zombie_attack
		"death": clip = clip_zombie_death
		_: clip = clip_zombie_idle

	_active_zombie_voices += 1
	_last_zombie_voice_ms = now_ms

	var dir: Vector3 = (world_pos - cam.global_position) / maxf(0.001, dist)
	var front_dot: float = dir.dot(-cam.global_transform.basis.z.normalized())
	var cutoff_hz: float = lerpf(8500.0, 1800.0, clampf(-front_dot, 0.0, 1.0))
	var vol_db: float = lerpf(-2.0 if urgent else -7.5, -26.0, clampf(dist / max_d, 0.0, 1.0))

	var v := _next_voice()
	if v != null:
		v.global_position = world_pos + Vector3(0.0, 1.4, 0.0)
		v.stream = clip
		v.unit_size = 9.0
		v.max_distance = max_d
		v.volume_db = vol_db
		v.pitch_scale = clampf(pitch_var * randf_range(0.93, 1.07), 0.72, 1.32)
		v.attenuation_filter_cutoff_hz = cutoff_hz
		v.attenuation_filter_db = -14.0
		v.play()

	var release_t := get_tree().create_timer(0.65)
	release_t.timeout.connect(func() -> void:
		_active_zombie_voices = maxi(0, _active_zombie_voices - 1)
	)


func play_horn_3d(is_moto: bool, world_pos: Vector3) -> void:
	if _pool.is_empty():
		return
	var clip: AudioStreamWAV = clip_horn_moto if is_moto else clip_horn_car
	_schedule_3d(clip, world_pos + Vector3(0.0, 1.1, 0.0), -2.5, 9500.0, 1.0, 150.0, 0.0)


func play_engine_start_3d(is_moto: bool, world_pos: Vector3) -> void:
	if _pool.is_empty():
		return
	var clip: AudioStreamWAV = clip_start_moto if is_moto else clip_start_car
	_schedule_3d(clip, world_pos + Vector3(0.0, 0.8, 0.0), -4.0, 7500.0, 1.0, 55.0, 0.0)


func get_engine_clip(is_moto: bool, moto_style: String) -> AudioStreamWAV:
	if not is_moto:
		return clip_engine_car
	if moto_style == "street":
		return clip_engine_street
	return clip_engine_trail


func _schedule_3d(clip: AudioStreamWAV, pos: Vector3, vol_db: float, cutoff_hz: float, pitch: float, max_d: float, delay: float) -> void:
	var fire := func() -> void:
		if not is_inside_tree():
			return
		var v := _next_voice()
		if v == null:
			return
		v.global_position = pos
		v.stream = clip
		v.unit_size = max_d * 0.25
		v.max_distance = max_d
		v.volume_db = vol_db
		v.pitch_scale = pitch
		v.attenuation_filter_cutoff_hz = cutoff_hz
		v.attenuation_filter_db = -16.0
		v.play()

	if delay > 0.006:
		var t := get_tree().create_timer(delay)
		t.timeout.connect(fire)
	else:
		fire.call()


# ==============================================================================
# GERADORES PCM 16-BIT MONO (som imediato sem precisar baixar arquivos .wav!)
# ==============================================================================
func _generate_all_clips() -> void:
	clip_pistol = _make_gunshot_wav(175.0, 0.34, 0.78)
	clip_rifle = _make_gunshot_wav(140.0, 0.52, 0.92)
	clip_sniper = _make_gunshot_wav(84.0, 0.85, 1.0)
	clip_suppressed = _make_gunshot_wav(320.0, 0.14, 0.48)
	clip_whiz = _make_whiz_wav()
	clip_explosion = _make_explosion_wav()
	clip_horn_car = _make_dual_tone_wav(392.0, 493.88, 0.42, 0.45)
	clip_horn_moto = _make_dual_tone_wav(587.0, 660.0, 0.28, 0.42)
	clip_start_car = _make_starter_wav(false)
	clip_start_moto = _make_starter_wav(true)
	clip_engine_car = _make_engine_loop_wav(54.0, 108.0, 0.26, 8.0)
	clip_engine_trail = _make_engine_loop_wav(72.0, 144.0, 0.36, 14.0)
	clip_engine_street = _make_engine_loop_wav(128.0, 256.0, 0.22, 26.0)
	clip_drift_loop = _make_drift_loop_wav()
	clip_zombie_idle = _make_zombie_wav(86.0, 64.0, 0.65)
	clip_zombie_alert = _make_zombie_wav(152.0, 94.0, 0.58)
	clip_zombie_attack = _make_zombie_wav(184.0, 78.0, 0.32)
	clip_zombie_death = _make_zombie_wav(116.0, 44.0, 0.82)


func _build_wav(samples: PackedByteArray, looping: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = samples
	if looping:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size() / 2
	return w


func _make_gunshot_wav(base_hz: float, dur: float, punch: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_hz * 100.0)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var f: float = lerpf(base_hz, 26.0, minf(1.0, t / 0.14))
		phase += TAU * f / float(SAMPLE_RATE)
		var thump: float = sin(phase) * exp(-t * 16.0) * punch
		var noise: float = rng.randf_range(-1.0, 1.0)
		var crack: float = noise * exp(-t * 28.0) * 0.9
		lp = lerpf(lp, noise, 0.09)
		var tail: float = lp * exp(-t * (2.6 / maxf(0.2, dur))) * 0.42
		var s: float = clampf(thump + crack + tail, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_whiz_wav() -> AudioStreamWAV:
	var dur: float = 0.16
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var f: float = lerpf(2500.0, 420.0, t / dur)
		phase += TAU * f / float(SAMPLE_RATE)
		var env: float = sin(PI * (t / dur))
		var s: float = clampf((sin(phase) * 0.65 + rng.randf_range(-1.0, 1.0) * 0.3) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_explosion_wav() -> AudioStreamWAV:
	var dur: float = 1.25
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var f: float = lerpf(78.0, 18.0, minf(1.0, t / 0.8))
		phase += TAU * f / float(SAMPLE_RATE)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05)
		var s: float = clampf(sin(phase) * exp(-t * 2.5) * 0.9 + lp * exp(-t * 2.1) * 1.1, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_dual_tone_wav(f1: float, f2: float, dur: float, vol: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = minf(1.0, t / 0.02) * clampf((dur - t) / 0.05, 0.0, 1.0)
		var s1: float = 1.0 if sin(TAU * f1 * t) >= 0.0 else -1.0
		var s2: float = 1.0 if sin(TAU * f2 * t) >= 0.0 else -1.0
		var s: float = (s1 + s2) * 0.25 * vol * env
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_starter_wav(is_moto: bool) -> AudioStreamWAV:
	var dur: float = 0.34 if is_moto else 0.45
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var f: float = lerpf(82.0, 220.0, t / dur) if is_moto else lerpf(42.0, 118.0, t / dur)
		phase += TAU * f / float(SAMPLE_RATE)
		var crank: float = 0.55 + 0.45 * sin(TAU * (18.0 if is_moto else 11.0) * t)
		var env: float = sin(PI * (t / dur))
		var s: float = clampf(sin(phase) * crank * env * 0.65, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_engine_loop_wav(f1: float, f2: float, rasp_amt: float, pulse_hz: float) -> AudioStreamWAV:
	var n: int = SAMPLE_RATE # 1.0s exato -> loop continuo sem clique!
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f1 * 17.0)
	var lp: float = 0.0
	var rf1: float = roundf(f1)
	var rf2: float = roundf(f2)
	var rf3: float = roundf(f1 * 3.0)
	var rp: float = roundf(pulse_hz)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var wave: float = sin(TAU * rf1 * t) + sin(TAU * rf2 * t) * 0.45 + sin(TAU * rf3 * t) * 0.20
		var pulse: float = 0.78 + 0.22 * sin(TAU * rp * t)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.10)
		var s: float = clampf((wave * 0.42 + lp * rasp_amt) * pulse, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, true)


func _make_drift_loop_wav() -> AudioStreamWAV:
	var n: int = SAMPLE_RATE
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var lp: float = 0.0
	var prev: float = 0.0
	for i in range(n):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.24)
		var hp: float = lp - prev * 0.85
		prev = lp
		bytes.encode_s16(i * 2, int(clampf(hp * 0.75, -1.0, 1.0) * 32767.0))
	return _build_wav(bytes, true)


func _make_zombie_wav(f_start: float, f_end: float, dur: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f_start * 31.0)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var f: float = lerpf(f_start, f_end, u) + sin(TAU * 22.0 * t) * 9.0
		phase += TAU * f / float(SAMPLE_RATE)
		var saw: float = fmod(phase / PI, 2.0) - 1.0
		lp = lerpf(lp, saw * 0.65 + rng.randf_range(-1.0, 1.0) * 0.35, 0.16)
		var env: float = minf(1.0, u / 0.18) * clampf((1.0 - u) / 0.25, 0.0, 1.0)
		bytes.encode_s16(i * 2, int(clampf(lp * env * 0.9, -1.0, 1.0) * 32767.0))
	return _build_wav(bytes, false)
