extends CharacterBody3D
class_name Zombie3D

## Zumbi autoritativo no Servidor (todos os jogadores veem exatamente os mesmos zumbis!)
## com audio 3D de gemido ambiente, alerta, perseguicao, ataque, dor e morte.

var zombie_id: String = ""
var hp: float = 100.0
var is_dead: bool = false
var is_chasing: bool = false
var vocal_pitch: float = 1.0

var _alert_t: float = 0.0
var _atk_cd: float = 0.0
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.FORWARD
var _sync_acc: float = 0.0
var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0

var _vocal_cd: float = 2.0
var _was_chasing: bool = false
var _body: Node3D
var _world: Node = null


func setup(p_id: String, p_world: Node, p_pitch: float) -> void:
	zombie_id = p_id
	_world = p_world
	vocal_pitch = p_pitch
	name = "Z_%s" % p_id


func _ready() -> void:
	_build_visual()
	_net_pos = global_position
	_net_yaw = rotation.y
	_vocal_cd = randf_range(1.4, 6.2)
	_wander_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()


func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.78
	col.shape = cap
	col.position = Vector3(0.0, 0.90, 0.0)
	add_child(col)

	_body = Node3D.new()
	add_child(_body)

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.36, 0.46, 0.32)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.24, 0.22, 0.20)

	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.50, 0.72, 0.28)
	torso.mesh = tm
	torso.position = Vector3(0.0, 1.10, 0.0)
	torso.material_override = cloth
	_body.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.30, 0.32, 0.30)
	head.mesh = hm
	head.position = Vector3(0.0, 1.62, -0.05)
	head.material_override = skin
	_body.add_child(head)

	for side in [-0.30, 0.30]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.14, 0.14, 0.62)
		arm.mesh = am
		arm.position = Vector3(side, 1.32, -0.34)
		arm.material_override = skin
		_body.add_child(arm)

	for side in [-0.14, 0.14]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.17, 0.74, 0.18)
		leg.mesh = lm
		leg.position = Vector3(side, 0.37, 0.0)
		leg.material_override = cloth
		_body.add_child(leg)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var is_srv: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if is_srv:
		_tick_server_ai(delta)
	else:
		global_position = global_position.lerp(_net_pos, minf(1.0, delta * 11.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 11.0))

	_tick_spatial_vocals(delta)


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

	if nearest != null and best_d <= 22.0:
		_alert_t = maxf(_alert_t, 9.5)

	is_chasing = _alert_t > 0.0 and nearest != null
	var move_dir: Vector3 = Vector3.ZERO
	var spd: float = 1.65

	if is_chasing:
		if best_d <= 1.55 and nearest.current_vehicle == null:
			if _atk_cd <= 0.0:
				_atk_cd = 1.2
				nearest.apply_damage(16)
				_rpc_vocal.rpc("attack")
		else:
			move_dir = nearest.global_position - global_position
			move_dir.y = 0.0
			spd = 4.65
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


func apply_server_damage(dmg: float) -> void:
	if is_dead:
		return
	hp = maxf(0.0, hp - dmg)
	_alert_t = 18.0
	if hp <= 0.0:
		_rpc_die.rpc()
	else:
		_rpc_vocal.rpc("hurt")


@rpc("authority", "call_local", "reliable")
func _rpc_vocal(vtype: String) -> void:
	if _world != null and _world.audio_3d != null:
		_world.audio_3d.play_zombie_vocal_3d(vtype, global_position, vocal_pitch)


@rpc("authority", "call_local", "reliable")
func _rpc_die() -> void:
	if is_dead:
		return
	is_dead = true
	hp = 0.0
	if _body != null:
		_body.rotation.x = deg_to_rad(85.0)
		_body.position.y = 0.20
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
