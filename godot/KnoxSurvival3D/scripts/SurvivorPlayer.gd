extends CharacterBody3D
class_name SurvivorPlayer

## Sobrevivente 3D (Godot 4 + ENetMultiplayerPeer) com:
## - Arsenal completo de 6 armas [1..6] ou Scroll, Recarga [R], Silenciador [X], Mira ADS (Botao Dir.)
## - Camera 1a/3a Pessoa [V], Troca de Ombro [Q], Lanterna [F], Agachar [Ctrl/C], Correr [Shift]
## - Animacao articulada de pernas/bracos + arma na mao sincronizada para todos os jogadores
## - Embarque em Carros (4 lugares) e Motos (Piloto + Garupa) [E] / [G] / [H]

var peer_id: int = 1
var nick: String = "Sobrevivente"
var team_id: String = ""
var hp: int = 200
var is_dead: bool = false
var flashlight_on: bool = false

var active_weapon_idx: int = 3 # Comeca com Rifle M4A1
var suppressed: bool = false
var mags: Array[int] = []
var reloading: bool = false
var reload_timer: float = 0.0

var current_vehicle: Vehicle3D = null
var current_seat: int = -1

var _yaw: float = 0.0
var _pitch: float = -0.1
var _first_person: bool = false
var _shoulder_sign: float = 1.0
var _ads_alpha: float = 0.0
var _fire_cd: float = 0.0
var _trigger_held_prev: bool = false
var _walk_phase: float = 0.0
var _crouch_alpha: float = 0.0
var _sync_acc: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _draw_distance: float = 550.0

var _cam_pivot: Node3D
var _cam: Camera3D
var _col_shape: CollisionShape3D
var _body_root: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_r: Node3D
var _weapon_mesh: MeshInstance3D
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
	mags.clear()
	for w in WeaponArsenal.WEAPONS:
		mags.append(int(w["mag_size"]))


func _ready() -> void:
	if mags.is_empty():
		for w in WeaponArsenal.WEAPONS:
			mags.append(int(w["mag_size"]))
	_build_visual_rig()
	_apply_weapon_visual(active_weapon_idx)
	_target_pos = global_position
	if is_local_player():
		_cam_pivot = Node3D.new()
		_cam_pivot.position = Vector3(0.0, 1.62, 0.0)
		add_child(_cam_pivot)
		_cam = Camera3D.new()
		_cam.current = true
		_cam.fov = 72.0
		_cam.far = _draw_distance
		_cam_pivot.add_child(_cam)
		var listener := AudioListener3D.new()
		listener.current = true
		_cam.add_child(listener)
		_name_label.visible = false


func is_local_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return peer_id == multiplayer.get_unique_id()


func set_draw_distance(meters: float) -> void:
	_draw_distance = clampf(meters, 140.0, 1200.0)
	if _cam != null:
		_cam.far = _draw_distance


func get_active_weapon_def() -> Dictionary:
	return WeaponArsenal.get_weapon(active_weapon_idx)


func get_active_mag() -> int:
	if active_weapon_idx >= 0 and active_weapon_idx < mags.size():
		return mags[active_weapon_idx]
	return 0


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

	# Tronco
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.50, 0.72, 0.28)
	torso.mesh = tm
	torso.position = Vector3(0.0, 1.12, 0.0)
	torso.material_override = mat_coat
	_body_root.add_child(torso)

	# Pernas articuladas no quadril
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.14, 0.76, 0.0)
	_body_root.add_child(_leg_l)
	var leg_l_mesh := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.18, 0.76, 0.20)
	leg_l_mesh.mesh = lm
	leg_l_mesh.position = Vector3(0.0, -0.38, 0.0)
	leg_l_mesh.material_override = mat_hat
	_leg_l.add_child(leg_l_mesh)

	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.14, 0.76, 0.0)
	_body_root.add_child(_leg_r)
	var leg_r_mesh := MeshInstance3D.new()
	leg_r_mesh.mesh = lm
	leg_r_mesh.position = Vector3(0.0, -0.38, 0.0)
	leg_r_mesh.material_override = mat_hat
	_leg_r.add_child(leg_r_mesh)

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

	# Braco direito + Arma alinhada horizontalmente para frente (-Z)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.29, 1.38, -0.04)
	_body_root.add_child(_arm_r)

	var arm_mesh := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.14, 0.14, 0.42)
	arm_mesh.mesh = am
	arm_mesh.position = Vector3(0.0, -0.10, -0.18)
	arm_mesh.material_override = mat_coat
	_arm_r.add_child(arm_mesh)

	_weapon_mesh = MeshInstance3D.new()
	_weapon_mesh.position = Vector3(0.0, -0.10, -0.46)
	_arm_r.add_child(_weapon_mesh)

	# Lanterna
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.25, 1.48, -0.25)
	_flashlight.spot_range = 42.0
	_flashlight.spot_angle = 36.0
	_flashlight.light_energy = 5.5
	_flashlight.visible = false
	_body_root.add_child(_flashlight)

	# Nametag 3D
	_name_label = Label3D.new()
	_name_label.text = nick
	_name_label.position = Vector3(0.0, 2.15, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 36
	add_child(_name_label)


func _apply_weapon_visual(idx: int) -> void:
	if _weapon_mesh == null:
		return
	var w: Dictionary = WeaponArsenal.get_weapon(idx)
	var bm := BoxMesh.new()
	var wlen: float = float(w["len"])
	bm.size = Vector3(0.07, 0.10, wlen)
	_weapon_mesh.mesh = bm
	_weapon_mesh.position = Vector3(0.0, -0.10, -0.24 - wlen * 0.42)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = w["color"]
	mat.metallic = 0.48
	mat.roughness = 0.42
	_weapon_mesh.material_override = mat


func equip_weapon(idx: int) -> void:
	var clamped: int = clampi(idx, 0, WeaponArsenal.WEAPONS.size() - 1)
	if clamped == active_weapon_idx:
		return
	active_weapon_idx = clamped
	reloading = false
	reload_timer = 0.0
	_apply_weapon_visual(active_weapon_idx)


func start_reload() -> void:
	if reloading or is_dead:
		return
	var w: Dictionary = get_active_weapon_def()
	if bool(w["melee"]):
		return
	var max_m: int = int(w["mag_size"])
	if mags[active_weapon_idx] >= max_m:
		return
	reloading = true
	reload_timer = float(w["reload_time"])


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player() or _world == null:
		return
	if _world.is_ui_blocking():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens: float = 0.0024 * lerpf(1.0, 0.48, _ads_alpha)
		_yaw -= mm.relative.x * sens
		_pitch = clampf(_pitch - mm.relative.y * sens, -1.25, 1.20)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			equip_weapon((active_weapon_idx + 1) % WeaponArsenal.WEAPONS.size())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			equip_weapon((active_weapon_idx - 1 + WeaponArsenal.WEAPONS.size()) % WeaponArsenal.WEAPONS.size())
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_6:
			equip_weapon(key - KEY_1)
		elif key == KEY_R:
			start_reload()
		elif key == KEY_X:
			suppressed = not suppressed
		elif key == KEY_V:
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
	var prev_pos: Vector3 = global_position

	if current_vehicle != null and is_instance_valid(current_vehicle):
		var seat_node: Node3D = current_vehicle.get_seat_node(current_seat)
		if seat_node != null:
			global_transform = seat_node.global_transform
	elif not is_local_player():
		global_position = global_position.lerp(_target_pos, minf(1.0, delta * 14.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 14.0))

	if not is_local_player():
		var remote_spd: float = Vector2(global_position.x - prev_pos.x, global_position.z - prev_pos.z).length() / maxf(0.001, delta)
		_animate_limbs(delta, remote_spd)
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			mags[active_weapon_idx] = int(get_active_weapon_def()["mag_size"])

	var blocked: bool = _world != null and _world.is_ui_blocking()
	var aiming: bool = (not blocked) and (not is_dead) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and (current_vehicle == null or current_seat > 0)
	_ads_alpha = lerpf(_ads_alpha, 1.0 if aiming else 0.0, minf(1.0, delta * 12.0))

	var move_spd: float = 0.0
	if not blocked and not is_dead:
		if current_vehicle == null:
			move_spd = _tick_foot_movement(delta)
			_tick_trigger()
		else:
			if current_seat == 0:
				var thr: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
				var str_in: float = (1.0 if Input.is_key_pressed(KEY_A) else 0.0) - (1.0 if Input.is_key_pressed(KEY_D) else 0.0)
				var hb: bool = Input.is_key_pressed(KEY_SPACE)
				current_vehicle.send_drive_input(thr, str_in, hb)
			else:
				_tick_trigger()
	else:
		_trigger_held_prev = false

	_animate_limbs(delta, move_spd)
	_update_camera(delta)

	# Envia transformacao + arma na rede (~24Hz)
	_sync_acc += delta
	if _sync_acc >= 0.042 and multiplayer.has_multiplayer_peer():
		_sync_acc = 0.0
		_rpc_sync_state.rpc(global_position, rotation.y, nick, team_id, hp, is_dead, active_weapon_idx)


func _tick_trigger() -> void:
	var held: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var w: Dictionary = get_active_weapon_def()
	var can_pull: bool = held if bool(w["auto"]) else (held and not _trigger_held_prev)
	_trigger_held_prev = held
	if can_pull and _fire_cd <= 0.0 and not reloading:
		_fire_weapon()


func _tick_foot_movement(delta: float) -> float:
	rotation.y = _yaw
	var fwd_in: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	var str_in: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var crouch: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var sprint: bool = Input.is_key_pressed(KEY_SHIFT) and not crouch and fwd_in > 0.1 and _ads_alpha < 0.25

	_crouch_alpha = lerpf(_crouch_alpha, 1.0 if crouch else 0.0, minf(1.0, delta * 10.0))
	var spd: float = 2.6 if crouch else (7.6 if sprint else (3.6 if _ads_alpha > 0.4 else 4.9))
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
	return Vector2(velocity.x, velocity.z).length()


func _animate_limbs(delta: float, h_spd: float) -> void:
	if _leg_l == null or _leg_r == null or _body_root == null:
		return
	if current_vehicle != null:
		_leg_l.rotation.x = deg_to_rad(-65.0)
		_leg_r.rotation.x = deg_to_rad(-65.0)
		_body_root.position.y = -0.18
		return

	_body_root.position.y = lerpf(0.0, -0.34, _crouch_alpha)
	if h_spd > 0.25:
		_walk_phase += delta * clampf(h_spd * 2.1, 4.0, 14.0)
		var sw: float = sin(_walk_phase) * minf(0.72, h_spd * 0.11)
		_leg_l.rotation.x = sw
		_leg_r.rotation.x = -sw
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, minf(1.0, delta * 10.0))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, minf(1.0, delta * 10.0))


func _update_camera(delta: float) -> void:
	if _cam == null or _cam_pivot == null:
		return

	var w: Dictionary = get_active_weapon_def()
	var target_fov: float = lerpf(72.0, float(w["ads_fov"]), _ads_alpha)
	_cam.fov = lerpf(_cam.fov, target_fov, minf(1.0, delta * 14.0))

	if current_vehicle != null:
		_cam_pivot.global_position = current_vehicle.global_position + Vector3(0.0, 1.48 if current_vehicle.is_moto else 1.80, 0.0)
		_cam_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)
		_cam.position = Vector3(0.0, 0.35, 4.4 if current_vehicle.is_moto else 5.8)
		return

	_cam_pivot.position = Vector3(0.0, lerpf(1.62, 1.18, _crouch_alpha), 0.0)
	_cam_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	if _first_person or (_ads_alpha > 0.75 and float(w["ads_fov"]) <= 35.0):
		_cam.position = Vector3(0.0, 0.02, -0.12)
		_body_root.visible = false
	else:
		_body_root.visible = true
		var dist: float = lerpf(3.35, 1.75, _ads_alpha)
		_cam.position = Vector3(0.56 * _shoulder_sign, 0.16, dist)


func _fire_weapon() -> void:
	if _cam == null or _world == null:
		return
	var w: Dictionary = get_active_weapon_def()
	var is_melee: bool = bool(w["melee"])
	if not is_melee:
		if mags[active_weapon_idx] <= 0:
			start_reload()
			return
		mags[active_weapon_idx] -= 1

	_fire_cd = float(w["cooldown"])
	var recoil: float = float(w["recoil"]) * lerpf(1.0, 0.6, _ads_alpha)
	_pitch = clampf(_pitch + recoil, -1.25, 1.20)
	_yaw += randf_range(-recoil * 0.35, recoil * 0.35)

	var spread: float = lerpf(float(w["spread"]), float(w["ads_spread"]), _ads_alpha)
	var pellets: int = int(w["pellets"])
	var snd: String = "suppressed" if (suppressed and not is_melee) else str(w["sound"])
	var origin: Vector3 = _cam.global_position + (-_cam.global_transform.basis.z) * 0.55
	var base_dir: Vector3 = -_cam.global_transform.basis.z.normalized()
	var right_v: Vector3 = _cam.global_transform.basis.x
	var up_v: Vector3 = _cam.global_transform.basis.y

	for i in range(pellets):
		var d: Vector3 = (base_dir + right_v * randf_range(-spread, spread) + up_v * randf_range(-spread, spread)).normalized()
		var play_audio: bool = (i == 0)
		_world.request_fire_shot(peer_id, origin, d, snd, float(w["dmg"]), float(w["range"]), float(w["noise"]), play_audio)

	if not is_melee and mags[active_weapon_idx] <= 0:
		start_reload()


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
func _rpc_sync_state(p_pos: Vector3, p_yaw: float, p_nick: String, p_team: String, p_hp: int, p_dead: bool, p_widx: int) -> void:
	_target_pos = p_pos
	_target_yaw = p_yaw
	nick = p_nick
	team_id = p_team
	hp = p_hp
	is_dead = p_dead
	if p_widx != active_weapon_idx:
		active_weapon_idx = clampi(p_widx, 0, WeaponArsenal.WEAPONS.size() - 1)
		_apply_weapon_visual(active_weapon_idx)
	if _name_label != null:
		_name_label.text = nick


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_flashlight(on: bool) -> void:
	flashlight_on = on
	if _flashlight != null:
		_flashlight.visible = on
