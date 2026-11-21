extends Node3D
class_name SpatialAudio3D

## Motor de Audio Espacial 3D (Godot 4):
## - Perfis balisticos individuais e realistas para CADA categoria de arma:
##   Pistola 9mm, Revolver .44 Magnum, SMG 9mm, Escopeta 12G (com pump), Fuzil 5.56, Rifle 7.62 AK, Sniper .50 BMG e Silenciador!
## - Armas brancas (Faca K-BAR e Katana) usam EXCLUSIVAMENTE sons reais de lamina (Weapon Whoosh / Knife Kills) — NUNCA tiro!
## - Som espacial 3D direcional (frente/tras/esquerda/direita), atraso fisico da velocidade do som e estalo supersonico.
## - Sons de estudio do Sound FX Starter Pack Vol. 1 para recarga, lamina, UI, sirene, tempestade e ambientes.

const SAMPLE_RATE: int = 22050
const SPEED_OF_SOUND: float = 343.0

var clip_pistol: AudioStream
var clip_revolver: AudioStream
var clip_smg: AudioStream
var clip_shotgun: AudioStream
var clip_rifle_556: AudioStream
var clip_rifle_762: AudioStream
var clip_sniper: AudioStream
var clip_suppressed: AudioStream
var clip_whiz: AudioStream
var clip_explosion: AudioStream
var clip_horn_car: AudioStream
var clip_horn_moto: AudioStream
var clip_start_car: AudioStream
var clip_start_moto: AudioStream
var clip_engine_car: AudioStream
var clip_engine_trail: AudioStream
var clip_engine_street: AudioStream
var clip_drift_loop: AudioStream
var clip_zombie_idle: AudioStream
var clip_zombie_alert: AudioStream
var clip_zombie_attack: AudioStream
var clip_zombie_hurt: AudioStream
var clip_zombie_death: AudioStream

# Clips de estudio do Sound FX Starter Pack Vol. 1
var clip_reload: AudioStream
var clip_melee_hit: AudioStream
var clip_melee_whoosh: AudioStream
var clip_hit: AudioStream
var clip_loot: AudioStream
var clip_equip: AudioStream
var clip_ui_map: AudioStream
var clip_ui_menu: AudioStream
var clip_ui_click: AudioStream
var clip_empty: AudioStream
var clip_siren: AudioStream
var clip_thunder: AudioStream
var clip_amb_day: AudioStream
var clip_amb_night: AudioStream
var clip_amb_rain: AudioStream

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_idx: int = 0
var _ui_player: AudioStreamPlayer
var _amb_player: AudioStreamPlayer
var _cur_amb_mode: String = ""
var _thunder_cd: float = 12.0
var _storm_active: bool = false
var _active_zombie_voices: int = 0
var _last_zombie_voice_ms: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_generate_all_clips()
	for i in range(36):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 520.0
		p.unit_size = 18.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.35
		add_child(p)
		_pool.append(p)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.volume_db = -7.0
	add_child(_ui_player)

	_amb_player = AudioStreamPlayer.new()
	_amb_player.volume_db = -18.0
	add_child(_amb_player)


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _storm_active and clip_thunder != null:
		_thunder_cd -= delta
		if _thunder_cd <= 0.0:
			_thunder_cd = randf_range(11.0, 24.0)
			if _ui_player != null:
				_ui_player.stream = clip_thunder
				_ui_player.volume_db = randf_range(-10.0, -5.0)
				_ui_player.pitch_scale = randf_range(0.86, 1.08)
				_ui_player.play()


func update_environment_ambience(is_night: bool, is_storm: bool) -> void:
	_storm_active = is_storm
	if _amb_player == null:
		return
	var target_mode: String = "storm" if is_storm else ("night" if is_night else "day")
	if target_mode == _cur_amb_mode and _amb_player.playing:
		return
	_cur_amb_mode = target_mode
	var target_clip: AudioStream = clip_amb_rain if is_storm else (clip_amb_night if is_night else clip_amb_day)
	if target_clip == null:
		_amb_player.stop()
		return
	_amb_player.stream = target_clip
	_amb_player.volume_db = -14.0 if is_storm else (-17.0 if is_night else -21.0)
	_amb_player.play()


func play_ui_sfx(kind: String) -> void:
	if _ui_player == null:
		return
	var s: AudioStream = null
	var vol: float = -7.0
	match kind:
		"map":
			s = clip_ui_map
		"menu":
			s = clip_ui_menu
		"equip":
			s = clip_equip
			vol = -8.5
		"loot":
			s = clip_loot
			vol = -4.5
		"hit":
			s = clip_hit
			vol = -10.5
		"crit":
			s = clip_hit
			vol = -5.5
		"empty":
			s = clip_empty
			vol = -8.0
		_:
			s = clip_ui_click
			vol = -10.0
	if s != null:
		_ui_player.stream = s
		_ui_player.volume_db = vol
		_ui_player.pitch_scale = 1.22 if kind == "crit" else randf_range(0.96, 1.04)
		_ui_player.play()


func play_reload_3d(world_pos: Vector3) -> void:
	if clip_reload != null:
		_schedule_3d(clip_reload, world_pos + Vector3(0.0, 1.3, 0.0), -6.5, 11000.0, randf_range(0.95, 1.05), 24.0, 0.0)


func play_melee_3d(world_pos: Vector3, is_hit: bool = false, is_katana: bool = false) -> void:
	var c: AudioStream = clip_melee_hit if (is_hit and clip_melee_hit != null) else clip_melee_whoosh
	if c == null:
		return
	var base_pitch: float = (0.84 if is_katana else 1.12) if is_hit else (0.78 if is_katana else 1.22)
	var vol_db: float = -3.0 if is_hit else -5.5
	_schedule_3d(c, world_pos + Vector3(0.0, 1.3, 0.0), vol_db, 12500.0, base_pitch * randf_range(0.95, 1.05), 26.0, 0.0)


func play_siren_3d(world_pos: Vector3) -> void:
	if clip_siren != null:
		_schedule_3d(clip_siren, world_pos + Vector3(0.0, 8.0, 0.0), -1.0, 12000.0, 1.0, 480.0, 0.0)


func _next_voice() -> AudioStreamPlayer3D:
	if _pool.is_empty():
		return null
	var p: AudioStreamPlayer3D = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	return p


func play_gunshot_3d(profile: String, muzzle_pos: Vector3, end_pos: Vector3, is_local: bool) -> void:
	if _pool.is_empty():
		return
	# Protecao extra: perfil melee NUNCA toca tiro!
	if profile.begins_with("melee"):
		return
	var clip: AudioStream = clip_rifle_556
	var base_vol: float = 0.0
	match profile:
		"pistol":
			clip = clip_pistol
			base_vol = -1.5
		"revolver":
			clip = clip_revolver
			base_vol = 0.8
		"smg":
			clip = clip_smg
			base_vol = -2.2
		"shotgun":
			clip = clip_shotgun
			base_vol = 1.4
		"rifle_556":
			clip = clip_rifle_556
			base_vol = 0.2
		"rifle_762":
			clip = clip_rifle_762
			base_vol = 0.7
		"sniper":
			clip = clip_sniper
			base_vol = 1.8
		"suppressed":
			clip = clip_suppressed
			base_vol = -6.5
		_:
			clip = clip_rifle_556

	if is_local:
		var v := _next_voice()
		if v == null:
			return
		v.global_position = muzzle_pos
		v.stream = clip
		v.unit_size = 26.0
		v.max_distance = 120.0
		v.volume_db = base_vol
		v.pitch_scale = randf_range(0.97, 1.03)
		v.attenuation_filter_cutoff_hz = 16500.0
		v.attenuation_filter_db = -1.5
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
	var front_dot: float = dir.dot(cam_fwd)

	var delay: float = minf(dist / SPEED_OF_SOUND, 1.4)
	var dist_norm: float = clampf(dist / max_d, 0.0, 1.0)
	var base_cutoff: float = lerpf(14500.0, 900.0, pow(dist_norm, 0.72))
	var rear_mult: float = lerpf(1.0, 0.38, clampf(-front_dot, 0.0, 1.0))
	var cutoff_hz: float = clampf(base_cutoff * rear_mult, 680.0, 16000.0)
	var rear_db: float = lerpf(0.0, -3.2, clampf(-front_dot, 0.0, 1.0))
	var dist_db: float = lerpf(base_vol + 0.5, -28.0, pow(dist_norm, 0.65))

	_schedule_3d(clip, muzzle_pos, dist_db + rear_db, cutoff_hz, randf_range(0.95, 1.04), max_d, delay)

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

	var clip: AudioStream = clip_zombie_idle
	match vocal_type:
		"alert": clip = clip_zombie_alert
		"attack": clip = clip_zombie_attack
		"hurt": clip = clip_zombie_hurt if clip_zombie_hurt != null else clip_zombie_attack
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
	var clip: AudioStream = clip_horn_moto if is_moto else clip_horn_car
	_schedule_3d(clip, world_pos + Vector3(0.0, 1.1, 0.0), -2.5, 9500.0, 1.0, 150.0, 0.0)


func play_engine_start_3d(is_moto: bool, world_pos: Vector3) -> void:
	if _pool.is_empty():
		return
	var clip: AudioStream = clip_start_moto if is_moto else clip_start_car
	_schedule_3d(clip, world_pos + Vector3(0.0, 0.8, 0.0), -4.0, 7500.0, 1.0, 55.0, 0.0)


func get_engine_clip(is_moto: bool, moto_style: String) -> AudioStream:
	if not is_moto:
		return clip_engine_car
	if moto_style == "street":
		return clip_engine_street
	return clip_engine_trail


func _schedule_3d(clip: AudioStream, pos: Vector3, vol_db: float, cutoff_hz: float, pitch: float, max_d: float, delay: float) -> void:
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
# SINTESE BALISTICA DEDICADA POR CALIBRE + SOUND FX STARTER PACK VOL. 1
# ==============================================================================
func _generate_all_clips() -> void:
	# Cada arma de fogo tem assinatura acustica propria e fiel ao calibre real!
	clip_pistol = _make_ballistic_shot(225.0, 0.28, 0.72, 1.00, 38.0, 0.28, 0.055, false)
	clip_revolver = _make_ballistic_shot(132.0, 0.54, 0.98, 1.05, 19.0, 0.50, 0.0, false)
	clip_smg = _make_ballistic_shot(260.0, 0.19, 0.62, 0.92, 46.0, 0.20, 0.032, false)
	clip_shotgun = _make_ballistic_shot(92.0, 0.68, 1.12, 1.05, 14.0, 0.58, 0.28, true)
	clip_rifle_556 = _make_ballistic_shot(175.0, 0.40, 0.84, 1.10, 26.0, 0.42, 0.048, false)
	clip_rifle_762 = _make_ballistic_shot(138.0, 0.48, 0.94, 0.98, 21.0, 0.48, 0.062, false)
	clip_sniper = _make_ballistic_shot(72.0, 0.98, 1.18, 1.15, 11.0, 0.66, 0.0, false)
	clip_suppressed = _make_suppressed_shot()
	clip_melee_whoosh = _make_blade_whoosh()
	clip_melee_hit = _make_blade_whoosh()
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
	_load_custom_audio_overrides()


func _load_custom_audio_overrides() -> void:
	# 1. Usa APENAS os clips do Sound FX Starter Pack Vol. 1 que realmente combinam com o jogo!
	# (NAO usa Steampunk Gun nem Mini Rocket Shot para fuzis/snipers reais!)
	var sfx: AudioStream
	sfx = AssetBridge.load_sfx_pack_clip("Hollywood/Mega Bomb.wav")
	if sfx != null: clip_explosion = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Hollywood/Heavy Gun Reload.wav")
	if sfx != null: clip_reload = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Hollywood/Knife Kills.wav")
	if sfx != null: clip_melee_hit = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Medieval/Weapon Whoosh.wav")
	if sfx != null: clip_melee_whoosh = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Hollywood/Deathpunch.wav")
	if sfx != null: clip_hit = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Hollywood/Reward.wav")
	if sfx != null: clip_loot = sfx
	sfx = AssetBridge.load_sfx_pack_clip("UI & Menus/Equip.wav")
	if sfx != null: clip_equip = sfx
	sfx = AssetBridge.load_sfx_pack_clip("UI & Menus/Map.wav")
	if sfx != null: clip_ui_map = sfx
	sfx = AssetBridge.load_sfx_pack_clip("UI & Menus/Inventory.wav")
	if sfx != null: clip_ui_menu = sfx
	sfx = AssetBridge.load_sfx_pack_clip("UI & Menus/Select.wav")
	if sfx != null: clip_ui_click = sfx
	sfx = AssetBridge.load_sfx_pack_clip("UI & Menus/Error.wav")
	if sfx != null: clip_empty = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Community Requests/Air Raid Siren.wav")
	if sfx != null: clip_siren = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Community Requests/Rolling Thunder.wav")
	if sfx != null: clip_thunder = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Community Requests/Animal Pain.wav")
	if sfx != null: clip_zombie_alert = sfx
	sfx = AssetBridge.load_sfx_pack_clip("Horror/Pain Glitch.wav")
	if sfx != null: clip_zombie_hurt = sfx

	# Ambientes continuos (dia / noite / tempestade)
	clip_amb_day = AssetBridge.load_sfx_pack_clip("Environment/Suburb Ext Distant Traffic Loop.wav")
	if clip_amb_day == null:
		clip_amb_day = AssetBridge.load_sfx_pack_clip("Environment/Grassy Field Loop.wav")
	clip_amb_night = AssetBridge.load_sfx_pack_clip("Horror/Wind Of Rotting.wav")
	if clip_amb_night == null:
		clip_amb_night = AssetBridge.load_sfx_pack_clip("Environment/Wind Loop.wav")
	clip_amb_rain = AssetBridge.load_sfx_pack_clip("Environment/Rain Urban Loop.wav")
	if clip_amb_rain == null:
		clip_amb_rain = AssetBridge.load_sfx_pack_clip("Environment/Rainy City Alley Loop.wav")

	# 2. Permite sobrescrever qualquer arma com .wav/.ogg proprios em res://assets/audio/
	var ov: AudioStream = AssetBridge.try_load_custom_audio(["gun_pistol", "pistol", "9mm"])
	if ov != null: clip_pistol = ov
	ov = AssetBridge.try_load_custom_audio(["gun_revolver", "revolver", "magnum"])
	if ov != null: clip_revolver = ov
	ov = AssetBridge.try_load_custom_audio(["gun_smg", "smg", "mp5"])
	if ov != null: clip_smg = ov
	ov = AssetBridge.try_load_custom_audio(["gun_shotgun", "shotgun", "12gauge"])
	if ov != null: clip_shotgun = ov
	ov = AssetBridge.try_load_custom_audio(["gun_rifle_556", "m4", "m4a1", "gun_rifle"])
	if ov != null: clip_rifle_556 = ov
	ov = AssetBridge.try_load_custom_audio(["gun_rifle_762", "ak47", "ak74"])
	if ov != null: clip_rifle_762 = ov
	ov = AssetBridge.try_load_custom_audio(["gun_sniper", "sniper", "awp", "50cal"])
	if ov != null: clip_sniper = ov
	ov = AssetBridge.try_load_custom_audio(["gun_suppressed", "suppressed", "silencer"])
	if ov != null: clip_suppressed = ov
	ov = AssetBridge.try_load_custom_audio(["engine_car", "car_engine"])
	if ov != null: clip_engine_car = ov
	ov = AssetBridge.try_load_custom_audio(["engine_moto", "engine_trail", "moto_engine"])
	if ov != null: clip_engine_trail = ov
	ov = AssetBridge.try_load_custom_audio(["engine_street", "sportbike"])
	if ov != null: clip_engine_street = ov
	ov = AssetBridge.try_load_custom_audio(["zombie_idle", "zombie_groan"])
	if ov != null: clip_zombie_idle = ov
	ov = AssetBridge.try_load_custom_audio(["zombie_alert", "zombie_scream"])
	if ov != null: clip_zombie_alert = ov
	ov = AssetBridge.try_load_custom_audio(["zombie_attack", "zombie_bite"])
	if ov != null: clip_zombie_attack = ov
	ov = AssetBridge.try_load_custom_audio(["zombie_death", "zombie_die"])
	if ov != null: clip_zombie_death = ov


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


func _make_ballistic_shot(base_hz: float, dur: float, punch: float, crack_gain: float, crack_decay: float, tail_gain: float, bolt_delay: float, is_pump: bool) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_hz * 137.0 + dur * 1000.0)
	var phase: float = 0.0
	var lp_mid: float = 0.0
	var lp_tail: float = 0.0
	var prev_noise: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var f: float = lerpf(base_hz, maxf(24.0, base_hz * 0.22), minf(1.0, t / 0.095))
		phase += TAU * f / float(SAMPLE_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var hp_crack: float = noise - prev_noise * 0.72
		prev_noise = noise

		# 1. Estalo supersonico inicial (primeiros 18ms)
		var crack: float = hp_crack * exp(-t * crack_decay) * crack_gain
		# 2. Corpo / pressao de polvora (grave + medio)
		var body_thump: float = sin(phase) * exp(-t * 17.5) * punch
		lp_mid = lerpf(lp_mid, noise, 0.24)
		var blast: float = lp_mid * exp(-t * 13.0) * (0.78 * punch)
		# 3. Cauda acustica urbana
		lp_tail = lerpf(lp_tail, noise, 0.075)
		var tail: float = lp_tail * exp(-t * (2.8 / maxf(0.18, dur))) * tail_gain
		# 4. Clique metalico de ferrolho / pump-action
		var mech: float = 0.0
		if bolt_delay > 0.0:
			var dt_b: float = t - bolt_delay
			if dt_b >= 0.0 and dt_b < 0.045:
				mech = (hp_crack * 0.45 + sin(TAU * 1450.0 * dt_b) * 0.3) * exp(-dt_b * 70.0) * (0.35 if is_pump else 0.16)
			if is_pump:
				var dt_p2: float = t - (bolt_delay + 0.12)
				if dt_p2 >= 0.0 and dt_p2 < 0.055:
					mech += (hp_crack * 0.42 + sin(TAU * 1120.0 * dt_p2) * 0.28) * exp(-dt_p2 * 60.0) * 0.34

		var s: float = tanh((crack + body_thump + blast + tail + mech) * 1.15)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _build_wav(bytes, false)


func _make_suppressed_shot() -> AudioStreamWAV:
	var dur: float = 0.15
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4401
	var lp: float = 0.0
	var prev: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.28)
		var hp: float = noise - prev * 0.82
		prev = noise
		var puff: float = lp * exp(-t * 36.0) * 0.72
		var bolt: float = (hp * 0.45 + sin(TAU * 1950.0 * t) * 0.25) * exp(-t * 95.0) * 0.42
		var s: float = clampf(puff + bolt, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(s * 32767.0))
	return _build_wav(bytes, false)


func _make_blade_whoosh() -> AudioStreamWAV:
	var dur: float = 0.22
	var n: int = int(SAMPLE_RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var lp: float = 0.0
	var prev: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var u: float = t / dur
		var env: float = sin(PI * u) * exp(-u * 1.6)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, lerpf(0.08, 0.34, env))
		var bp: float = lp - prev * 0.65
		prev = lp
		bytes.encode_s16(i * 2, int(clampf(bp * env * 1.5, -1.0, 1.0) * 32767.0))
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
	var n: int = SAMPLE_RATE
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
