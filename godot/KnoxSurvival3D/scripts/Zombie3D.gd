extends CharacterBody3D
class_name Zombie3D

## Zumbi 3D Knox Survival (Godot 4):
## - 3 arquetipos reais (0=Shambler lento, 1=Walker classico, 2=Sprinter rapido)
## - Maquina de estados exclusiva de animacao (1 animacao por vez, sem agachar sozinho parado
##   e morte definitiva com Death01 uma unica vez — NUNCA caminha deitado!)
## - Audio espacial 3D sincronizado em multiplayer.

const STAND_EXCLUDE: PackedStringArray = [
	"crouch", "sit", "swim", "climb", "roll", "crawl", "talk", "torch", "dance", "fix", "push"
]

var zombie_id: String = ""
var hp: float = 100.0
var is_dead: bool = false
var is_chasing: bool = false
var vocal_pitch: float = 1.0
var archetype: int = 1 # 0=Shambler, 1=Walker, 2=Sprinter

var _alert_t: float = 0.0
var _atk_cd: float = 0.0
var _atk_anim_t: float = 0.0
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.FORWARD
var _sync_acc: float = 0.0
var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0

var _walk_phase: float = 0.0
var _vocal_cd: float = 2.0
var _was_chasing: bool = false
var _col_shape: CollisionShape3D
var _body: Node3D
var _spine: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _world: Node = null
var _ext_model: Node3D = null
var _ext_anim: AnimationPlayer = null
var _ext_cur_anim: String = ""
var _ext_is_one_shot: bool = false

const SHIRT_COLORS: Array[Color] = [
	Color(0.32, 0.34, 0.30), Color(0.26, 0.30, 0.38),
	Color(0.42, 0.28, 0.24), Color(0.24, 0.24, 0.22), Color(0.38, 0.36, 0.28)
]
const PANTS_COLORS: Array[Color] = [
	Color(0.18, 0.20, 0.24), Color(0.20, 0.18, 0.16), Color(0.15, 0.16, 0.18)
]


func setup(p_id: String, p_world: Node, p_pitch: float) -> void:
	zombie_id = p_id
	_world = p_world
	vocal_pitch = p_pitch
	archetype = abs(p_id.hash()) % 3
	name = "Z_%s" % p_id


func _ready() -> void:
	_build_zombie_rig()
	_net_pos = global_position
	_net_yaw = rotation.y
	_vocal_cd = randf_range(1.4, 6.2)
	_wander_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()


func _mk(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 10
	return c


func _build_zombie_rig() -> void:
	_col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.78
	_col_shape.shape = cap
	_col_shape.position = Vector3(0.0, 0.90, 0.0)
	add_child(_col_shape)

	var rng := RandomNumberGenerator.new()
	rng.seed = zombie_id.hash()

	_body = Node3D.new()
	var sc: float = rng.randf_range(0.95, 1.06)
	_body.scale = Vector3.ONE * sc
	add_child(_body)

	_ext_model = AssetBridge.try_instantiate_character(true)
	if _ext_model != null:
		_body.add_child(_ext_model)
		_ext_anim = AssetBridge.find_first_animation_player(_ext_model)
		if _ext_anim == null:
			_ext_anim = AnimationPlayer.new()
			_ext_model.add_child(_ext_anim)
		AssetBridge.stop_extra_animation_players(_ext_model, _ext_anim)
		AssetBridge.merge_external_animations(_ext_anim)
		var init_idle: String = AssetBridge.find_best_anim_name(_ext_anim, ["Idle_Loop", "Idle"], STAND_EXCLUDE)
		if not init_idle.is_empty():
			_ext_cur_anim = init_idle
			_ext_anim.play(init_idle)
		return

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.43, 0.49, 0.39)
	skin.roughness = 0.88
	var face_mat := ProceduralTextures.get_zombie_face_mat()
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()]
	shirt.roughness = 0.92
	var pants := StandardMaterial3D.new()
	pants.albedo_color = PANTS_COLORS[rng.randi() % PANTS_COLORS.size()]
	pants.roughness = 0.92
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.36, 0.06, 0.05)
	blood.roughness = 0.65
	var shoe := StandardMaterial3D.new()
	shoe.albedo_color = Color(0.14, 0.13, 0.12)
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color(0.14, 0.12, 0.10)

	var pelvis := Node3D.new()
	pelvis.position = Vector3(0.0, 0.90, 0.0)
	_body.add_child(pelvis)
	_mk(pelvis, _cyl(0.155, 0.145, 0.15), pants, Vector3.ZERO, Vector3(1.0, 1.0, 0.68))

	_spine = Node3D.new()
	_spine.position = Vector3(0.0, 0.06, 0.0)
	pelvis.add_child(_spine)
	var torso_m := BoxMesh.new()
	torso_m.size = Vector3(0.34, 0.44, 0.19)
	_mk(_spine, torso_m, shirt, Vector3(0.0, 0.225, 0.0))
	var stain_m := BoxMesh.new()
	stain_m.size = Vector3(0.16, 0.20, 0.015)
	_mk(_spine, stain_m, blood, Vector3(rng.randf_range(-0.05, 0.05), 0.22, -0.098))

	var head := Node3D.new()
	head.position = Vector3(0.0, 0.455, 0.0)
	_spine.add_child(head)
	_mk(head, _cyl(0.052, 0.058, 0.09), skin, Vector3(0.0, 0.032, -0.005))
	var head_sph := SphereMesh.new()
	head_sph.radius = 0.115
	head_sph.height = 0.23
	_mk(head, head_sph, skin, Vector3(0.0, 0.152, 0.0), Vector3(0.90, 1.04, 0.94))
	var face_box := BoxMesh.new()
	face_box.size = Vector3(0.162, 0.185, 0.028)
	_mk(head, face_box, face_mat, Vector3(0.0, 0.152, -0.096))
	if rng.randf() > 0.30:
		var hair_m := BoxMesh.new()
		hair_m.size = Vector3(0.19, 0.06, 0.20)
		_mk(head, hair_m, hair, Vector3(0.0, 0.248, 0.01))

	_arm_l = _build_z_arm(-1.0, shirt, skin)
	_arm_r = _build_z_arm(1.0, shirt, skin)
	_leg_l = _build_z_leg(-1.0, pelvis, pants, shoe)
	_leg_r = _build_z_leg(1.0, pelvis, pants, shoe)


func _build_z_arm(side: float, shirt: Material, skin: Material) -> Node3D:
	var sh := Node3D.new()
	sh.position = Vector3(side * 0.205, 0.395, 0.0)
	_spine.add_child(sh)
	_mk(sh, _cyl(0.052, 0.045, 0.25), shirt, Vector3(0.0, -0.125, 0.0))
	_mk(sh, _cyl(0.044, 0.038, 0.23), skin, Vector3(0.0, -0.35, 0.0))
	var hand_m := BoxMesh.new()
	hand_m.size = Vector3(0.056, 0.072, 0.042)
	_mk(sh, hand_m, skin, Vector3(0.0, -0.49, -0.01))
	sh.rotation.x = deg_to_rad(68.0)
	return sh


func _build_z_leg(side: float, pelvis: Node3D, pants: Material, shoe: Material) -> Node3D:
	var hip := Node3D.new()
	hip.position = Vector3(side * 0.092, -0.04, 0.0)
	pelvis.add_child(hip)
	_mk(hip, _cyl(0.072, 0.060, 0.42), pants, Vector3(0.0, -0.21, 0.0))
	_mk(hip, _cyl(0.060, 0.050, 0.41), pants, Vector3(0.0, -0.62, 0.0))
	var shoe_m := BoxMesh.new()
	shoe_m.size = Vector3(0.098, 0.065, 0.21)
	_mk(hip, shoe_m, shoe, Vector3(0.0, -0.84, -0.04))
	return hip


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_atk_anim_t = maxf(0.0, _atk_anim_t - delta)
	var prev_pos: Vector3 = global_position
	var is_srv: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if is_srv:
		_tick_server_ai(delta)
	else:
		global_position = global_position.lerp(_net_pos, minf(1.0, delta * 11.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 11.0))

	var spd: float = Vector2(global_position.x - prev_pos.x, global_position.z - prev_pos.z).length() / maxf(0.001, delta)
	_animate_zombie(delta, spd)
	_tick_spatial_vocals(delta)


func _animate_zombie(delta: float, spd: float) -> void:
	if _ext_anim != null:
		var want: String = ""
		var sp_s: float = 0.72 if archetype == 0 else (1.30 if archetype == 2 else 1.0)
		var one_shot: bool = false

		if _atk_anim_t > 0.0:
			want = AssetBridge.find_best_anim_name(_ext_anim, ["Punch_Jab", "Punch_Cross", "Zombie_Attack", "Attack"], STAND_EXCLUDE)
			sp_s = 1.25
			one_shot = true
		elif is_chasing and spd > 2.2:
			want = AssetBridge.find_best_anim_name(_ext_anim, ["Sprint_Loop", "Jog_Fwd_Loop", "Run_Fwd_Loop", "Walk_Loop"], STAND_EXCLUDE)
		elif spd > 0.25:
			want = AssetBridge.find_best_anim_name(_ext_anim, ["Zombie_Walk_Fwd_Loop", "Walk_Loop", "Walk_Fwd_Loop", "Walk"], STAND_EXCLUDE)
		else:
			want = AssetBridge.find_best_anim_name(_ext_anim, ["Idle_Loop", "Idle"], STAND_EXCLUDE)

		if not want.is_empty():
			_ext_anim.speed_scale = sp_s
			if want != _ext_cur_anim or (not one_shot and not _ext_anim.is_playing()):
				_ext_cur_anim = want
				_ext_is_one_shot = one_shot
				_ext_anim.play(want, 0.14)
		return

	if _leg_l == null or _leg_r == null:
		return
	if spd > 0.2:
		_walk_phase += delta * clampf(spd * 2.4, 3.0, 12.5)
		var sw: float = sin(_walk_phase) * (0.68 if is_chasing else 0.36)
		_leg_l.rotation.x = sw
		_leg_r.rotation.x = -sw
		if _spine != null:
			_spine.rotation.x = deg_to_rad(-16.0 if is_chasing else -8.0)
			_spine.rotation.z = sin(_walk_phase) * (0.09 if archetype == 0 else 0.04)
		if _arm_l != null and _arm_r != null:
			var reach: float = deg_to_rad(86.0) if is_chasing else deg_to_rad(52.0)
			_arm_l.rotation.x = reach + sw * 0.22
			_arm_r.rotation.x = reach - sw * 0.22


func _tick_server_ai(delta: float) -> void:
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_alert_t = maxf(0.0, _alert_t - delta)

	var nearest: SurvivorPlayer = null
	var best_d: float = 9999.0
	if _world != null:
		for p in _world.get_all_players():
			if p.is_dead:
				continue
			var d: float = global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				nearest = p

	if nearest != null and best_d <= 24.0:
		_alert_t = maxf(_alert_t, 9.5)

	is_chasing = _alert_t > 0.0 and nearest != null
	var move_dir: Vector3 = Vector3.ZERO
	var chase_spd: float = 5.4 if archetype == 2 else (3.4 if archetype == 0 else 4.4)
	var spd: float = 1.55

	if is_chasing:
		if best_d <= 1.55 and nearest.current_vehicle == null:
			if _atk_cd <= 0.0:
				_atk_cd = 1.15
				_atk_anim_t = 0.45
				nearest.apply_damage(16)
				_rpc_vocal.rpc("attack")
		else:
			move_dir = nearest.global_position - global_position
			move_dir.y = 0.0
			spd = chase_spd
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(3.0, 6.5)
			_wander_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		move_dir = _wander_dir

	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()
		var target_yaw: float = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 6.5))
		velocity.x = move_dir.x * spd
		velocity.z = move_dir.z * spd
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	velocity.y = -2.0 if is_on_floor() else (velocity.y - 18.0 * delta)
	move_and_slide()

	_sync_acc += delta
	if _sync_acc >= 0.085 and multiplayer.has_multiplayer_peer():
		_sync_acc = 0.0
		_rpc_sync_zombie.rpc(global_position, rotation.y, is_chasing, hp, is_dead)


func _tick_spatial_vocals(delta: float) -> void:
	if _world == null or _world.audio_3d == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist: float = cam.global_position.distance_to(global_position)
	if dist > 52.0:
		return

	_vocal_cd = maxf(0.0, _vocal_cd - delta)
	if is_chasing and not _was_chasing:
		_was_chasing = true
		_world.audio_3d.play_zombie_vocal_3d("alert", global_position, vocal_pitch)
		_vocal_cd = randf_range(3.0, 5.4)
	elif not is_chasing and _was_chasing:
		_was_chasing = false
	elif _vocal_cd <= 0.0:
		if is_chasing and dist < 38.0:
			_world.audio_3d.play_zombie_vocal_3d("chase", global_position, vocal_pitch)
			_vocal_cd = randf_range(3.2, 6.2)
		elif not is_chasing and dist < 32.0:
			_world.audio_3d.play_zombie_vocal_3d("idle", global_position, vocal_pitch)
			_vocal_cd = randf_range(5.5, 11.0)
		else:
			_vocal_cd = 2.5


func alert_by_sound(duration: float = 14.0) -> void:
	if not is_dead:
		_alert_t = maxf(_alert_t, duration)


func apply_server_damage(dmg: float) -> bool:
	if is_dead:
		return false
	hp = maxf(0.0, hp - dmg)
	_alert_t = 18.0
	if hp <= 0.0:
		_rpc_die.rpc()
		return true
	_rpc_vocal.rpc("hurt")
	return false


@rpc("authority", "call_local", "reliable")
func _rpc_vocal(vtype: String) -> void:
	if vtype == "attack":
		_atk_anim_t = 0.45
	if _world != null and _world.audio_3d != null:
		_world.audio_3d.play_zombie_vocal_3d(vtype, global_position, vocal_pitch)


@rpc("authority", "call_local", "reliable")
func _rpc_die() -> void:
	if is_dead:
		return
	is_dead = true
	is_chasing = false
	hp = 0.0
	velocity = Vector3.ZERO
	# Desativa colisao imediatamente para nao bloquear tiros nem passagem
	if _col_shape != null:
		_col_shape.set_deferred("disabled", true)

	# Para a caminhada IMEDIATAMENTE e toca Death01 UMA UNICA VEZ (sem caminhar deitado!)
	if _ext_anim != null:
		_ext_anim.stop(false)
		var death_anim: String = AssetBridge.find_best_anim_name(_ext_anim, ["Death01", "Death_01", "Death", "Die"], ["loop"])
		if not death_anim.is_empty():
			var dclip: Animation = _ext_anim.get_animation(death_anim)
			if dclip != null:
				dclip.loop_mode = Animation.LOOP_NONE
			_ext_cur_anim = death_anim
			_ext_is_one_shot = true
			_ext_anim.speed_scale = 1.0
			_ext_anim.play(death_anim, 0.08)
		elif _body != null:
			_body.rotation.x = deg_to_rad(86.0)
			_body.position.y = 0.18
	elif _body != null:
		if _leg_l != null: _leg_l.rotation.x = 0.0
		if _leg_r != null: _leg_r.rotation.x = 0.0
		_body.rotation.x = deg_to_rad(86.0)
		_body.position.y = 0.18

	if _world != null and _world.audio_3d != null:
		_world.audio_3d.play_zombie_vocal_3d("death", global_position, vocal_pitch)
	var t := get_tree().create_timer(22.0)
	t.timeout.connect(func() -> void:
		if is_inside_tree():
			queue_free()
	)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_zombie(p_pos: Vector3, p_yaw: float, p_chasing: bool, p_hp: float, p_dead: bool) -> void:
	_net_pos = p_pos
	_net_yaw = p_yaw
	is_chasing = p_chasing
	hp = p_hp
	if p_dead and not is_dead:
		_rpc_die()
