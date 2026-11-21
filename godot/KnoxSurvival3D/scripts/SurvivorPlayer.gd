extends CharacterBody3D
class_name SurvivorPlayer

## Sobrevivente 3D (Godot 4 + ENetMultiplayerPeer) com 1a/3a pessoa [V], troca de ombro [Q],
## combate sincronizado no servidor com som 3D direcional para todos os ouvintes,
## lanterna [F] e embarque em Carros/Motos (Piloto ou Garupa).

var peer_id: int = 1
var nick: String = "Sobrevivente"
var team_id: String = ""
var hp: int = 200
var is_dead: bool = false
var flashlight_on: bool = false

var current_vehicle: Vehicle3D = null
var current_seat: int = -1

var _yaw: float = 0.0
var _pitch: float = -0.1
var _first_person: bool = false
var _shoulder_sign: float = 1.0
var _fire_cd: float = 0.0
var _sync_acc: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0

var _cam_pivot: Node3D
var _cam: Camera3D
var _col_shape: CollisionShape3D
var _body_root: Node3D
var _flashlight: SpotLight3D
var _name_label: Label3D
var _world: Node = null


func setup(p_peer_id: int, p_world: Node, p_nick: String, p_team: String) -> void:
	peer_id = p_peer_id
	_world = p_world
	nick = p_nick
	team_id = p_team
	name = "Player_%d" % p_peer_id
	set_multiplayer_authority(p_peer_id)


func _ready() -> void:
	_build_visual_rig()
	_target_pos = global_position
	if is_local_player():
		_cam_pivot = Node3D.new()
		_cam_pivot.position = Vector3(0.0, 1.62, 0.0)
		add_child(_cam_pivot)
		_cam = Camera3D.new()
		_cam.current = true
		_cam.far = 650.0
		_cam_pivot.add_child(_cam)
		var listener := AudioListener3D.new()
		listener.current = true
		_cam.add_child(listener)
		_name_label.visible = false


func is_local_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return peer_id == multiplayer.get_unique_id()


func _build_visual_rig() -> void:
	_col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.78
	_col_shape.shape = cap
	_col_shape.position = Vector3(0.0, 0.90, 0.0)
	add_child(_col_shape)

	_body_root = Node3D.new()
	add_child(_body_root)

	var mat_coat := StandardMaterial3D.new()
	mat_coat.albedo_color = Color(0.18, 0.25, 0.20)
	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = Color(0.76, 0.60, 0.48)
	var mat_hat := StandardMaterial3D.new()
	mat_hat.albedo_color = Color(0.10, 0.10, 0.12)
	var mat_gun := StandardMaterial3D.new()
	mat_gun.albedo_color = Color(0.22, 0.24, 0.26)
	mat_gun.metallic = 0.5

	# Tronco
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.52, 0.72, 0.30)
	torso.mesh = tm
	torso.position = Vector3(0.0, 1.12, 0.0)
	torso.material_override = mat_coat
	_body_root.add_child(torso)

	# Pernas
	for side in [-0.14, 0.14]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.18, 0.76, 0.20)
		leg.mesh = lm
		leg.position = Vector3(side, 0.38, 0.0)
		leg.material_override = mat_hat
		_body_root.add_child(leg)

	# Cabeca + Chapeu tatico
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.32, 0.34, 0.32)
	head.mesh = hm
	head.position = Vector3(0.0, 1.66, 0.0)
	head.material_override = mat_skin
	_body_root.add_child(head)

	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.30
	bm.bottom_radius = 0.30
	bm.height = 0.04
	brim.mesh = bm
	brim.position = Vector3(0.0, 1.84, 0.0)
	brim.material_override = mat_hat
	_body_root.add_child(brim)

	# Rifle 3P alinhado para frente (-Z)
	var rifle := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.08, 0.11, 0.85)
	rifle.mesh = rm
	rifle.position = Vector3(0.28, 1.18, -0.36)
	rifle.material_override = mat_gun
	_body_root.add_child(rifle)

	# Lanterna
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.25, 1.48, -0.25)
	_flashlight.spot_range = 38.0
	_flashlight.spot_angle = 36.0
	_flashlight.light_energy = 5.0
	_flashlight.visible = false
	_body_root.add_child(_flashlight)

	# Nametag 3D
	_name_label = Label3D.new()
	_name_label.text = nick
	_name_label.position = Vector3(0.0, 2.15, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 36
	add_child(_name_label)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player() or _world == null:
		return
	if _world.is_ui_blocking():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0024
		_pitch = clampf(_pitch - mm.relative.y * 0.0022, -1.25, 1.20)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_V:
			_first_person = not _first_person
			_body_root.visible = not _first_person or current_vehicle != null
		elif key == KEY_Q:
			_shoulder_sign = -_shoulder_sign
		elif key == KEY_F:
			if current_vehicle != null and current_seat == 0:
				current_vehicle.request_toggle_lights()
			else:
				flashlight_on = not flashlight_on
				_flashlight.visible = flashlight_on
				_rpc_set_flashlight.rpc(flashlight_on)
		elif key == KEY_E:
			_handle_interact_vehicle(Input.is_key_pressed(KEY_SHIFT))
		elif key == KEY_G and current_vehicle != null:
			current_vehicle.request_switch_seat(peer_id)
		elif key == KEY_H and current_vehicle != null and current_seat == 0:
			current_vehicle.request_horn()


func _physics_process(delta: float) -> void:
	if current_vehicle != null and is_instance_valid(current_vehicle):
		var seat_node: Node3D = current_vehicle.get_seat_node(current_seat)
		if seat_node != null:
			global_transform = seat_node.global_transform
	elif not is_local_player():
		global_position = global_position.lerp(_target_pos, minf(1.0, delta * 14.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 14.0))

	if not is_local_player():
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	var blocked: bool = _world != null and _world.is_ui_blocking()

	if not blocked and not is_dead:
		if current_vehicle == null:
			_tick_foot_movement(delta)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cd <= 0.0:
				_fire_weapon()
		else:
			if current_seat == 0:
				var thr: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
				var str_in: float = (1.0 if Input.is_key_pressed(KEY_A) else 0.0) - (1.0 if Input.is_key_pressed(KEY_D) else 0.0)
				var hb: bool = Input.is_key_pressed(KEY_SPACE)
				current_vehicle.send_drive_input(thr, str_in, hb)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _fire_cd <= 0.0:
				_fire_weapon()

	_update_camera()

	# Envia transformacao na rede (~24Hz)
	_sync_acc += delta
	if _sync_acc >= 0.042 and multiplayer.has_multiplayer_peer():
		_sync_acc = 0.0
		_rpc_sync_state.rpc(global_position, rotation.y, nick, team_id, hp, is_dead)


func _tick_foot_movement(delta: float) -> void:
	rotation.y = _yaw
	var fwd_in: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	var str_in: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var crouch: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var sprint: bool = Input.is_key_pressed(KEY_SHIFT) and not crouch and fwd_in > 0.1

	var spd: float = 2.6 if crouch else (7.6 if sprint else 4.8)
	var move_dir: Vector3 = (-global_transform.basis.z * fwd_in + global_transform.basis.x * str_in)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()

	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd

	if is_on_floor():
		if Input.is_key_pressed(KEY_SPACE) and not crouch:
			velocity.y = 5.6
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()


func _update_camera() -> void:
	if _cam == null or _cam_pivot == null:
		return

	if current_vehicle != null:
		_cam_pivot.global_position = current_vehicle.global_position + Vector3(0.0, 1.48 if current_vehicle.is_moto else 1.80, 0.0)
		_cam_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)
		_cam.position = Vector3(0.0, 0.35, 4.4 if current_vehicle.is_moto else 5.8)
		return

	_cam_pivot.position = Vector3(0.0, 1.62, 0.0)
	_cam_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	if _first_person:
		_cam.position = Vector3(0.0, 0.02, -0.10)
	else:
		_cam.position = Vector3(0.58 * _shoulder_sign, 0.18, 3.35)


func _fire_weapon() -> void:
	if _cam == null or _world == null:
		return
	_fire_cd = 0.12
	var origin: Vector3 = _cam.global_position + (-_cam.global_transform.basis.z) * 0.55
	var dir: Vector3 = -_cam.global_transform.basis.z.normalized()
	_world.request_fire_shot(peer_id, origin, dir, "rifle")


func _handle_interact_vehicle(prefer_passenger: bool) -> void:
	if _world == null:
		return
	if current_vehicle != null:
		current_vehicle.request_exit(peer_id)
		return
	var nearest: Vehicle3D = _world.find_nearest_vehicle(global_position, 4.5)
	if nearest != null:
		nearest.request_enter(peer_id, prefer_passenger)


func attach_to_vehicle(veh: Vehicle3D, seat_idx: int) -> void:
	current_vehicle = veh
	current_seat = seat_idx
	if _col_shape != null:
		_col_shape.disabled = (veh != null)
	if veh != null:
		var seat_node: Node3D = veh.get_seat_node(seat_idx)
		if seat_node != null:
			global_transform = seat_node.global_transform
		_body_root.visible = true
	else:
		rotation.x = 0.0
		rotation.z = 0.0
		_body_root.visible = not _first_person


func apply_damage(amount: int) -> void:
	if is_dead:
		return
	hp = maxi(0, hp - amount)
	if hp <= 0:
		is_dead = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_state(p_pos: Vector3, p_yaw: float, p_nick: String, p_team: String, p_hp: int, p_dead: bool) -> void:
	_target_pos = p_pos
	_target_yaw = p_yaw
	nick = p_nick
	team_id = p_team
	hp = p_hp
	is_dead = p_dead
	if _name_label != null:
		_name_label.text = nick


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_flashlight(on: bool) -> void:
	flashlight_on = on
	if _flashlight != null:
		_flashlight.visible = on
