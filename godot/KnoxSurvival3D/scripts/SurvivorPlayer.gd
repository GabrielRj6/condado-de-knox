extends CharacterBody3D
class_name SurvivorPlayer

## Sobrevivente 3D 1:1 portado de buildOmniCharacter() do Knox Survival 3D:
## - Personagem iconico (chapeu Pork-Pie preto, oculos Wayfarer, jaqueta xadrez vinho aberta
##   sobre camisa social cinza, cinto com fivela, pernas e bracos cilindricos articulados, sapatos)
## - Modelos 3D REAIS (.obj) das 9 armas na mao (3a Pessoa E Viewmodel 1a Pessoa!) + silenciador [X]
## - Vitais completos (HP 200, Stamina 100, Fome 100, Sede 100) + Recuo + Muzzle Flash
## - Postura correta de piloto/garupa em motos (straddle sobre o banco) e motorista/passageiro em carros

var peer_id: int = 1
var nick: String = "Sobrevivente"
var team_id: String = ""
var hp: int = 200
var stamina: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var kills: int = 0
var is_dead: bool = false
var flashlight_on: bool = false

var active_weapon_idx: int = 5 # Comeca com Fuzil M41-T 5.56
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
var _recoil_kick: float = 0.0
var _muzzle_flash_t: float = 0.0
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
var _pelvis: Node3D
var _spine: Node3D
var _head_pivot: Node3D
var _leg_l_hip: Node3D
var _leg_l_knee: Node3D
var _leg_r_hip: Node3D
var _leg_r_knee: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _tp_weapon_mount: Node3D
var _fp_weapon_mount: Node3D
var _muzzle_light: OmniLight3D
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
	_build_omni_character_rig()
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

		# Viewmodel 1a Pessoa (arma real .obj na mao direita quando em 1P)
		_fp_weapon_mount = Node3D.new()
		_fp_weapon_mount.position = Vector3(0.24, -0.22, -0.44)
		_fp_weapon_mount.visible = false
		_cam.add_child(_fp_weapon_mount)

		var listener := AudioListener3D.new()
		listener.current = true
		_cam.add_child(listener)
		_name_label.visible = false
	_apply_weapon_visual(active_weapon_idx)


func is_local_player() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return peer_id == multiplayer.get_unique_id()


func is_sniper_scoped() -> bool:
	var w: Dictionary = get_active_weapon_def()
	return _ads_alpha > 0.72 and float(w["ads_fov"]) <= 30.0


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


func _mk(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 12
	return c


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 8
	return s


func _build_omni_character_rig() -> void:
	_col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	_col_shape.shape = cap
	_col_shape.position = Vector3(0.0, 0.90, 0.0)
	add_child(_col_shape)

	_body_root = Node3D.new()
	add_child(_body_root)

	# Materiais 1:1 do buildOmniCharacter()
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color.html("#c89679")
	skin_mat.roughness = 0.76
	var face_mat := ProceduralTextures.get_omni_face_mat()
	var jacket_mat := ProceduralTextures.get_omni_jacket_mat()
	var shirt_mat := ProceduralTextures.get_omni_shirt_mat()
	var rib_mat := StandardMaterial3D.new()
	rib_mat.albedo_color = Color.html("#160b16")
	rib_mat.roughness = 0.92
	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = Color.html("#241f28")
	pants_mat.roughness = 0.88
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color.html("#171211")
	belt_mat.roughness = 0.55
	var shoe_mat := StandardMaterial3D.new()
	shoe_mat.albedo_color = Color.html("#3b322b")
	shoe_mat.roughness = 0.76
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color.html("#181316")
	hat_mat.roughness = 0.90
	var hat_band_mat := StandardMaterial3D.new()
	hat_band_mat.albedo_color = Color.html("#2b1d29")
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color.html("#111113")
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color.html("#060709")
	lens_mat.metallic = 0.68
	lens_mat.roughness = 0.10
	var chrome_mat := ProceduralTextures.get_chrome_mat()

	# Pelve + Cinto Social + Fivela
	_pelvis = Node3D.new()
	_pelvis.position = Vector3(0.0, 0.93, 0.0)
	_body_root.add_child(_pelvis)
	_mk(_pelvis, _cyl(0.162, 0.152, 0.16), pants_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.68))
	_mk(_pelvis, _cyl(0.166, 0.165, 0.036), belt_mat, Vector3(0.0, 0.066, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.69))
	_mk(_pelvis, _box(Vector3(0.052, 0.042, 0.016)), chrome_mat, Vector3(0.0, 0.066, -0.114))

	# Coluna + Jaqueta Xadrez Vinho Aberta + Camisa Cinza + Golas
	_spine = Node3D.new()
	_spine.position = Vector3(0.0, 0.06, 0.0)
	_pelvis.add_child(_spine)
	_mk(_spine, _box(Vector3(0.285, 0.44, 0.184)), shirt_mat, Vector3(0.0, 0.23, -0.006))
	_mk(_spine, _box(Vector3(0.352, 0.445, 0.14)), jacket_mat, Vector3(0.0, 0.235, 0.042))
	_mk(_spine, _box(Vector3(0.058, 0.44, 0.215)), jacket_mat, Vector3(-0.154, 0.235, 0.002))
	_mk(_spine, _box(Vector3(0.058, 0.44, 0.215)), jacket_mat, Vector3(0.154, 0.235, 0.002))
	_mk(_spine, _box(Vector3(0.112, 0.44, 0.055)), jacket_mat, Vector3(-0.118, 0.235, -0.088))
	_mk(_spine, _box(Vector3(0.112, 0.44, 0.055)), jacket_mat, Vector3(0.118, 0.235, -0.088))
	_mk(_spine, _box(Vector3(0.354, 0.048, 0.15)), rib_mat, Vector3(0.0, 0.024, 0.042))
	_mk(_spine, _box(Vector3(0.195, 0.062, 0.032)), jacket_mat, Vector3(0.0, 0.468, 0.068), Vector3(-0.16, 0.0, 0.0))

	# Cabeca Esculpida + Oculos Wayfarer + Chapeu Pork-Pie
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0.0, 0.465, 0.0)
	_spine.add_child(_head_pivot)
	_mk(_head_pivot, _cyl(0.058, 0.066, 0.095), skin_mat, Vector3(0.0, 0.032, -0.004))
	_mk(_head_pivot, _sph(0.118), skin_mat, Vector3(0.0, 0.158, 0.0), Vector3.ZERO, Vector3(0.88, 1.08, 0.94))
	# Rosto frontal texturizado
	_mk(_head_pivot, _box(Vector3(0.165, 0.19, 0.03)), face_mat, Vector3(0.0, 0.156, -0.098))
	_mk(_head_pivot, _sph(0.015), skin_mat, Vector3(0.0, 0.140, -0.116))

	# Oculos Wayfarer escuros
	for side in [-1.0, 1.0]:
		_mk(_head_pivot, _box(Vector3(0.072, 0.040, 0.014)), frame_mat, Vector3(side * 0.044, 0.172, -0.112))
		_mk(_head_pivot, _box(Vector3(0.062, 0.030, 0.016)), lens_mat, Vector3(side * 0.044, 0.171, -0.114))
		_mk(_head_pivot, _box(Vector3(0.009, 0.010, 0.12)), frame_mat, Vector3(side * 0.092, 0.175, -0.052))
	_mk(_head_pivot, _box(Vector3(0.024, 0.009, 0.014)), frame_mat, Vector3(0.0, 0.180, -0.114))

	# Chapeu Pork-Pie classico
	var hat := Node3D.new()
	hat.position = Vector3(0.0, 0.252, 0.004)
	hat.rotation.x = -0.04
	_head_pivot.add_child(hat)
	_mk(hat, _cyl(0.178, 0.182, 0.014), hat_mat, Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.0, 1.07))
	_mk(hat, _cyl(0.109, 0.122, 0.088), hat_mat, Vector3(0.0, 0.046, 0.0), Vector3.ZERO, Vector3(0.93, 1.0, 1.06))
	_mk(hat, _cyl(0.121, 0.123, 0.022), hat_band_mat, Vector3(0.0, 0.018, 0.0), Vector3.ZERO, Vector3(0.935, 1.0, 1.065))

	# Bracos cilindricos articulados
	_arm_l = _build_arm(-1.0, jacket_mat, rib_mat, skin_mat)
	_arm_r = _build_arm(1.0, jacket_mat, rib_mat, skin_mat)

	# Mount da Arma 3D REAL na mao direita (3a pessoa)
	_tp_weapon_mount = Node3D.new()
	_tp_weapon_mount.position = Vector3(-0.02, -0.44, -0.14)
	_tp_weapon_mount.rotation.x = deg_to_rad(-78.0)
	_arm_r.add_child(_tp_weapon_mount)

	# Pernas cilindricas articuladas (Coxa + Joelho + Canela + Sapato)
	var leg_l_nodes: Array[Node3D] = _build_leg(-1.0, pants_mat, shoe_mat, belt_mat)
	_leg_l_hip = leg_l_nodes[0]
	_leg_l_knee = leg_l_nodes[1]
	var leg_r_nodes: Array[Node3D] = _build_leg(1.0, pants_mat, shoe_mat, belt_mat)
	_leg_r_hip = leg_r_nodes[0]
	_leg_r_knee = leg_r_nodes[1]

	# Clarão de boca (muzzle flash)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.position = Vector3(0.22, 1.38, -0.75)
	_muzzle_light.light_color = Color(1.0, 0.78, 0.36)
	_muzzle_light.light_energy = 7.0
	_muzzle_light.omni_range = 9.0
	_muzzle_light.visible = false
	_body_root.add_child(_muzzle_light)

	# Lanterna tatica [F]
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.25, 1.48, -0.25)
	_flashlight.spot_range = 46.0
	_flashlight.spot_angle = 38.0
	_flashlight.light_color = Color(1.0, 0.96, 0.88)
	_flashlight.light_energy = 6.5
	_flashlight.visible = false
	_body_root.add_child(_flashlight)

	# Nametag 3D
	_name_label = Label3D.new()
	_name_label.text = nick
	_name_label.position = Vector3(0.0, 2.12, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 34
	_name_label.outline_size = 6
	add_child(_name_label)


func _build_arm(side: float, jacket_mat: Material, rib_mat: Material, skin_mat: Material) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.215, 0.405, 0.005)
	_spine.add_child(shoulder)
	_mk(shoulder, _sph(0.060), jacket_mat, Vector3(0.0, -0.01, 0.0))
	_mk(shoulder, _cyl(0.058, 0.050, 0.25), jacket_mat, Vector3(0.0, -0.125, 0.0))
	_mk(shoulder, _cyl(0.050, 0.043, 0.21), jacket_mat, Vector3(0.0, -0.34, -0.04), Vector3(0.24, 0.0, 0.0))
	_mk(shoulder, _cyl(0.044, 0.042, 0.036), rib_mat, Vector3(0.0, -0.44, -0.065), Vector3(0.24, 0.0, 0.0))
	_mk(shoulder, _box(Vector3(0.058, 0.078, 0.040)), skin_mat, Vector3(0.0, -0.49, -0.075))
	return shoulder


func _build_leg(side: float, pants_mat: Material, shoe_mat: Material, sole_mat: Material) -> Array[Node3D]:
	var hip := Node3D.new()
	hip.position = Vector3(side * 0.095, -0.04, 0.0)
	_pelvis.add_child(hip)
	_mk(hip, _cyl(0.076, 0.064, 0.42), pants_mat, Vector3(0.0, -0.21, 0.0))

	var knee := Node3D.new()
	knee.position = Vector3(0.0, -0.42, 0.0)
	hip.add_child(knee)
	_mk(knee, _sph(0.060), pants_mat, Vector3.ZERO)
	_mk(knee, _cyl(0.064, 0.054, 0.41), pants_mat, Vector3(0.0, -0.205, 0.0))
	# Sapato de couro escuro + sola
	_mk(knee, _box(Vector3(0.102, 0.062, 0.225)), shoe_mat, Vector3(0.0, -0.42, -0.045))
	_mk(knee, _box(Vector3(0.106, 0.022, 0.238)), sole_mat, Vector3(0.0, -0.455, -0.045))
	return [hip, knee]


func _apply_weapon_visual(idx: int) -> void:
	if _tp_weapon_mount != null:
		for c in _tp_weapon_mount.get_children():
			c.queue_free()
		_tp_weapon_mount.add_child(WeaponArsenal.build_weapon_node(idx, suppressed, 1.0))

	if _fp_weapon_mount != null:
		for c in _fp_weapon_mount.get_children():
			c.queue_free()
		_fp_weapon_mount.add_child(WeaponArsenal.build_weapon_node(idx, suppressed, 0.85))


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
		var sens: float = 0.0024 * lerpf(1.0, 0.42, _ads_alpha)
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
		if key >= KEY_1 and key <= KEY_9:
			equip_weapon(key - KEY_1)
		elif key == KEY_R:
			start_reload()
		elif key == KEY_X:
			suppressed = not suppressed
			_apply_weapon_visual(active_weapon_idx)
		elif key == KEY_V:
			_first_person = not _first_person
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
			_handle_interact(Input.is_key_pressed(KEY_SHIFT))
		elif key == KEY_G and current_vehicle != null:
			current_vehicle.request_switch_seat(peer_id)
		elif key == KEY_H and current_vehicle != null and current_seat == 0:
			current_vehicle.request_horn()


func _physics_process(delta: float) -> void:
	var prev_pos: Vector3 = global_position

	if _muzzle_flash_t > 0.0:
		_muzzle_flash_t -= delta
		if _muzzle_flash_t <= 0.0 and _muzzle_light != null:
			_muzzle_light.visible = false

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
	_recoil_kick = lerpf(_recoil_kick, 0.0, minf(1.0, delta * 14.0))
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			mags[active_weapon_idx] = int(get_active_weapon_def()["mag_size"])

	# Fome e sede suaves de sobrevivencia
	if not is_dead:
		hunger = maxf(0.0, hunger - delta * 0.06)
		thirst = maxf(0.0, thirst - delta * 0.09)

	var blocked: bool = _world != null and _world.is_ui_blocking()
	var aiming: bool = (not blocked) and (not is_dead) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and (current_vehicle == null or current_seat > 0)
	_ads_alpha = lerpf(_ads_alpha, 1.0 if aiming else 0.0, minf(1.0, delta * 12.0))

	var move_spd: float = 0.0
	if not blocked and not is_dead:
		if current_vehicle == null:
			move_spd = _tick_foot_movement(delta)
			_tick_trigger()
		else:
			stamina = minf(100.0, stamina + delta * 16.0)
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
	_update_camera_and_viewmodel(delta, move_spd)

	_sync_acc += delta
	if _sync_acc >= 0.042 and multiplayer.has_multiplayer_peer():
		_sync_acc = 0.0
		_rpc_sync_state.rpc(global_position, rotation.y, nick, team_id, hp, is_dead, active_weapon_idx, suppressed)


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
	var wants_sprint: bool = Input.is_key_pressed(KEY_SHIFT) and not crouch and fwd_in > 0.1 and _ads_alpha < 0.25 and stamina > 4.0

	if wants_sprint:
		stamina = maxf(0.0, stamina - delta * 18.0)
	else:
		stamina = minf(100.0, stamina + delta * 14.0)

	_crouch_alpha = lerpf(_crouch_alpha, 1.0 if crouch else 0.0, minf(1.0, delta * 10.0))
	var spd: float = 2.6 if crouch else (7.8 if wants_sprint else (3.6 if _ads_alpha > 0.4 else 5.0))
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
	if _leg_l_hip == null or _leg_r_hip == null or _body_root == null:
		return

	if current_vehicle != null:
		if current_vehicle.is_moto:
			# Postura realista montado na moto (pernas abertas no tanque + joelhos dobrados nas pedaleiras)
			_body_root.position.y = -0.34
			_spine.rotation.x = deg_to_rad(-16.0 if current_seat == 0 else -10.0)
			_leg_l_hip.rotation = Vector3(deg_to_rad(56.0), 0.0, deg_to_rad(-18.0))
			_leg_r_hip.rotation = Vector3(deg_to_rad(56.0), 0.0, deg_to_rad(18.0))
			_leg_l_knee.rotation.x = deg_to_rad(-76.0)
			_leg_r_knee.rotation.x = deg_to_rad(-76.0)
			if current_seat == 0:
				_arm_l.rotation = Vector3(deg_to_rad(68.0), 0.0, deg_to_rad(-10.0))
				_arm_r.rotation = Vector3(deg_to_rad(68.0), 0.0, deg_to_rad(10.0))
			else:
				_arm_l.rotation = Vector3(deg_to_rad(42.0), 0.0, deg_to_rad(12.0))
				_arm_r.rotation = Vector3(deg_to_rad(62.0), 0.0, 0.0)
		else:
			# Sentado no banco do carro
			_body_root.position.y = -0.32
			_spine.rotation.x = deg_to_rad(6.0)
			_leg_l_hip.rotation = Vector3(deg_to_rad(78.0), 0.0, 0.0)
			_leg_r_hip.rotation = Vector3(deg_to_rad(78.0), 0.0, 0.0)
			_leg_l_knee.rotation.x = deg_to_rad(-78.0)
			_leg_r_knee.rotation.x = deg_to_rad(-78.0)
			_arm_l.rotation = Vector3(deg_to_rad(52.0), 0.0, 0.0)
			_arm_r.rotation = Vector3(deg_to_rad(52.0), 0.0, 0.0)
		return

	_body_root.position.y = lerpf(0.0, -0.34, _crouch_alpha)
	_spine.rotation.x = lerpf(0.0, deg_to_rad(-12.0), _crouch_alpha)

	# Braco direito apontando a arma na altura do ombro
	_arm_r.rotation = Vector3(deg_to_rad(78.0) + _pitch * 0.55 + _recoil_kick * 0.4, 0.0, 0.0)
	_arm_l.rotation = Vector3(deg_to_rad(56.0) + _pitch * 0.35, 0.0, deg_to_rad(16.0))

	if h_spd > 0.25:
		_walk_phase += delta * clampf(h_spd * 2.1, 4.0, 14.0)
		var sw: float = sin(_walk_phase) * minf(0.68, h_spd * 0.10)
		_leg_l_hip.rotation = Vector3(sw, 0.0, 0.0)
		_leg_r_hip.rotation = Vector3(-sw, 0.0, 0.0)
		_leg_l_knee.rotation.x = -maxf(0.0, -sw * 0.85)
		_leg_r_knee.rotation.x = -maxf(0.0, sw * 0.85)
	else:
		_leg_l_hip.rotation = _leg_l_hip.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
		_leg_r_hip.rotation = _leg_r_hip.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
		_leg_l_knee.rotation.x = lerpf(_leg_l_knee.rotation.x, 0.0, minf(1.0, delta * 10.0))
		_leg_r_knee.rotation.x = lerpf(_leg_r_knee.rotation.x, 0.0, minf(1.0, delta * 10.0))


func _update_camera_and_viewmodel(delta: float, move_spd: float) -> void:
	if _cam == null or _cam_pivot == null:
		return

	var w: Dictionary = get_active_weapon_def()
	var target_fov: float = lerpf(72.0, float(w["ads_fov"]), _ads_alpha)
	_cam.fov = lerpf(_cam.fov, target_fov, minf(1.0, delta * 14.0))

	if current_vehicle != null:
		_cam_pivot.global_position = current_vehicle.global_position + Vector3(0.0, 1.48 if current_vehicle.is_moto else 1.82, 0.0)
		_cam_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)
		_cam.position = Vector3(0.0, 0.36, 4.3 if current_vehicle.is_moto else 5.8)
		_body_root.visible = true
		if _fp_weapon_mount != null:
			_fp_weapon_mount.visible = false
		return

	_cam_pivot.position = Vector3(0.0, lerpf(1.62, 1.18, _crouch_alpha), 0.0)
	_cam_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	var scoped: bool = is_sniper_scoped()
	var use_fp: bool = _first_person or scoped

	if use_fp:
		_cam.position = Vector3(0.0, 0.02, -0.10)
		_body_root.visible = false
		if _fp_weapon_mount != null:
			_fp_weapon_mount.visible = not scoped
			var bob_x: float = cos(_walk_phase * 0.5) * 0.012 * clampf(move_spd / 5.0, 0.0, 1.0)
			var bob_y: float = absf(sin(_walk_phase * 0.5)) * 0.014 * clampf(move_spd / 5.0, 0.0, 1.0)
			var hip_pos := Vector3(0.24 + bob_x, -0.21 - bob_y, -0.44 + _recoil_kick * 0.10)
			var ads_pos := Vector3(0.0, -0.145, -0.34 + _recoil_kick * 0.06)
			_fp_weapon_mount.position = hip_pos.lerp(ads_pos, _ads_alpha)
			_fp_weapon_mount.rotation.x = _recoil_kick * 0.22
	else:
		_body_root.visible = true
		if _fp_weapon_mount != null:
			_fp_weapon_mount.visible = false
		var dist: float = lerpf(3.25, 1.68, _ads_alpha)
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
	var recoil: float = float(w["recoil"]) * lerpf(1.0, 0.58, _ads_alpha)
	_pitch = clampf(_pitch + recoil, -1.25, 1.20)
	_yaw += randf_range(-recoil * 0.35, recoil * 0.35)
	_recoil_kick = minf(1.0, _recoil_kick + 0.55)
	if not is_melee and _muzzle_light != null:
		_muzzle_light.visible = true
		_muzzle_flash_t = 0.055

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


func _handle_interact(prefer_passenger: bool) -> void:
	if _world == null:
		return
	if current_vehicle != null:
		current_vehicle.request_exit(peer_id)
		return
	# Primeiro tenta coletar caixa de suprimento proxima
	if _world.try_pickup_nearest_loot(self, 3.2):
		return
	var nearest: Vehicle3D = _world.find_nearest_vehicle(global_position, 4.6)
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


func apply_damage(amount: int) -> void:
	if is_dead:
		return
	hp = maxi(0, hp - amount)
	if hp <= 0:
		is_dead = true


func heal_and_restock() -> void:
	hp = mini(200, hp + 65)
	hunger = minf(100.0, hunger + 40.0)
	thirst = minf(100.0, thirst + 45.0)
	stamina = 100.0
	for i in range(mags.size()):
		mags[i] = int(WeaponArsenal.WEAPONS[i]["mag_size"])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_state(p_pos: Vector3, p_yaw: float, p_nick: String, p_team: String, p_hp: int, p_dead: bool, p_widx: int, p_sup: bool) -> void:
	_target_pos = p_pos
	_target_yaw = p_yaw
	nick = p_nick
	team_id = p_team
	hp = p_hp
	is_dead = p_dead
	if p_widx != active_weapon_idx or p_sup != suppressed:
		active_weapon_idx = clampi(p_widx, 0, WeaponArsenal.WEAPONS.size() - 1)
		suppressed = p_sup
		_apply_weapon_visual(active_weapon_idx)
	if _name_label != null:
		_name_label.text = nick


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_flashlight(on: bool) -> void:
	flashlight_on = on
	if _flashlight != null:
		_flashlight.visible = on
