extends CharacterBody3D
class_name SurvivorPlayer

## Sobrevivente 3D Knox Survival (Godot 4):
## - Movimentacao 3a Pessoa fluida com inercia suave, direcao livre (W/A/S/D gira o corpo para
##   esquerda/direita/tras/diagonais) + Strafing tatico real ao mirar (Botao Dir.), atirar ou em 1P!
## - Alinhamento preciso das 9 armas 3D (.obj) com empunhadura bi-manual articulada (ombros + cotovelos)
## - Motorista/Piloto guarda a arma (maos no volante/guidao) e senta DENTRO da cabine (sem atravessar teto!)
## - Auto-deteccao de modelo 3D externo (.glb/.tscn) + AnimationPlayer via AssetBridge (fallback Omni rig)

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
var god_mode: bool = false
var infinite_ammo: bool = false

var active_weapon_idx: int = 5 # Comeca com Fuzil M41-T 5.56
var suppressed: bool = false
var mags: Array[int] = []
var reloading: bool = false
var reload_timer: float = 0.0

var current_vehicle: Vehicle3D = null
var current_seat: int = -1

var _yaw: float = 0.0         # Yaw da camera / mira
var _body_yaw: float = 0.0    # Yaw real do corpo (gira livremente ao caminhar em 3P, trava na mira em ADS/tiro/1P)
var _pitch: float = -0.1
var _first_person: bool = false
var _shoulder_sign: float = 1.0
var _ads_alpha: float = 0.0
var _combat_stance_t: float = 0.0
var _fire_cd: float = 0.0
var _recoil_kick: float = 0.0
var _melee_swing_t: float = 0.0
var _muzzle_flash_t: float = 0.0
var _trigger_held_prev: bool = false
var _walk_phase: float = 0.0
var _idle_phase: float = 0.0
var _crouch_alpha: float = 0.0
var _land_dip: float = 0.0
var _was_on_floor: bool = true
var _is_sprinting: bool = false
var _local_move_vel: Vector2 = Vector2.ZERO # x = lateral (direita+), y = frente+
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
var _elbow_l: Node3D
var _arm_r: Node3D
var _elbow_r: Node3D
var _weapon_aim_pivot: Node3D
var _tp_weapon_mount: Node3D
var _fp_weapon_mount: Node3D
var _muzzle_light: OmniLight3D
var _flashlight: SpotLight3D
var _name_label: Label3D
var _world: Node = null

# Suporte automatico a modelo 3D rigado (.glb/.tscn) + AnimationPlayer (Asset Store / Mixamo)
var _ext_model: Node3D = null
var _ext_anim: AnimationPlayer = null
var _ext_cur_anim: String = ""


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
	_build_character_rig()
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


func get_aim_yaw() -> float:
	return _yaw


func is_first_person_mode() -> bool:
	return _first_person


func get_posture_label() -> String:
	if is_dead:
		return "ABATIDO"
	if current_vehicle != null:
		return "PILOTANDO" if current_seat == 0 else "PASSAGEIRO"
	if _crouch_alpha > 0.45:
		return "AGACHADO"
	if _is_sprinting:
		return "CORRENDO"
	if _ads_alpha > 0.45:
		return "MIRANDO"
	return "EM PE"


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


func _build_character_rig() -> void:
	_col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	_col_shape.shape = cap
	_col_shape.position = Vector3(0.0, 0.90, 0.0)
	add_child(_col_shape)

	_body_root = Node3D.new()
	add_child(_body_root)

	# 1. Tenta carregar automaticamente modelo 3D (.glb/.tscn) + animacoes colocados em res://assets/characters/
	_ext_model = AssetBridge.try_instantiate_character(false)
	if _ext_model != null:
		_body_root.add_child(_ext_model)
		_ext_anim = AssetBridge.find_first_animation_player(_ext_model)
		if _ext_anim == null:
			_ext_anim = AnimationPlayer.new()
			_ext_model.add_child(_ext_anim)
		AssetBridge.merge_external_animations(_ext_anim)
		var skel := AssetBridge.find_first_skeleton(_ext_model)
		_weapon_aim_pivot = Node3D.new()
		_tp_weapon_mount = Node3D.new()
		_weapon_aim_pivot.add_child(_tp_weapon_mount)
		if not AssetBridge.attach_node_to_right_hand(skel, _weapon_aim_pivot):
			_weapon_aim_pivot.position = Vector3(0.18, 1.32, -0.25)
			_body_root.add_child(_weapon_aim_pivot)
	else:
		_build_omni_rig_parts()

	# Clarao de boca (muzzle flash)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.position = Vector3(0.16, 1.34, -0.78)
	_muzzle_light.light_color = Color(1.0, 0.78, 0.36)
	_muzzle_light.light_energy = 7.0
	_muzzle_light.omni_range = 9.0
	_muzzle_light.visible = false
	_body_root.add_child(_muzzle_light)

	# Lanterna tatica [F]
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.22, 1.46, -0.24)
	_flashlight.spot_range = 48.0
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


func _build_omni_rig_parts() -> void:
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
	_mk(_head_pivot, _box(Vector3(0.165, 0.19, 0.03)), face_mat, Vector3(0.0, 0.156, -0.098))
	_mk(_head_pivot, _sph(0.015), skin_mat, Vector3(0.0, 0.140, -0.116))

	for side in [-1.0, 1.0]:
		_mk(_head_pivot, _box(Vector3(0.072, 0.040, 0.014)), frame_mat, Vector3(side * 0.044, 0.172, -0.112))
		_mk(_head_pivot, _box(Vector3(0.062, 0.030, 0.016)), lens_mat, Vector3(side * 0.044, 0.171, -0.114))
		_mk(_head_pivot, _box(Vector3(0.009, 0.010, 0.12)), frame_mat, Vector3(side * 0.092, 0.175, -0.052))
	_mk(_head_pivot, _box(Vector3(0.024, 0.009, 0.014)), frame_mat, Vector3(0.0, 0.180, -0.114))

	var hat := Node3D.new()
	hat.position = Vector3(0.0, 0.252, 0.004)
	hat.rotation.x = -0.04
	_head_pivot.add_child(hat)
	_mk(hat, _cyl(0.178, 0.182, 0.014), hat_mat, Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.0, 1.07))
	_mk(hat, _cyl(0.109, 0.122, 0.088), hat_mat, Vector3(0.0, 0.046, 0.0), Vector3.ZERO, Vector3(0.93, 1.0, 1.06))
	_mk(hat, _cyl(0.121, 0.123, 0.022), hat_band_mat, Vector3(0.0, 0.018, 0.0), Vector3.ZERO, Vector3(0.935, 1.0, 1.065))

	# Bracos articulados com ombro + cotovelo (para empunhadura realista de fuzil/pistola/volante!)
	var arm_l_nodes: Array[Node3D] = _build_arm(-1.0, jacket_mat, rib_mat, skin_mat)
	_arm_l = arm_l_nodes[0]
	_elbow_l = arm_l_nodes[1]
	var arm_r_nodes: Array[Node3D] = _build_arm(1.0, jacket_mat, rib_mat, skin_mat)
	_arm_r = arm_r_nodes[0]
	_elbow_r = arm_r_nodes[1]

	# Pivot dedicado da arma 3D na altura do ombro/peito (garante cano SEMPRE nivelado e nas 2 maos!)
	_weapon_aim_pivot = Node3D.new()
	_weapon_aim_pivot.position = Vector3(0.14, 0.34, -0.22)
	_spine.add_child(_weapon_aim_pivot)

	_tp_weapon_mount = Node3D.new()
	_weapon_aim_pivot.add_child(_tp_weapon_mount)

	# Pernas articuladas (Quadril + Joelho + Sapato)
	var leg_l_nodes: Array[Node3D] = _build_leg(-1.0, pants_mat, shoe_mat, belt_mat)
	_leg_l_hip = leg_l_nodes[0]
	_leg_l_knee = leg_l_nodes[1]
	var leg_r_nodes: Array[Node3D] = _build_leg(1.0, pants_mat, shoe_mat, belt_mat)
	_leg_r_hip = leg_r_nodes[0]
	_leg_r_knee = leg_r_nodes[1]


func _build_arm(side: float, jacket_mat: Material, rib_mat: Material, skin_mat: Material) -> Array[Node3D]:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.215, 0.405, 0.005)
	_spine.add_child(shoulder)
	_mk(shoulder, _sph(0.060), jacket_mat, Vector3(0.0, -0.01, 0.0))
	_mk(shoulder, _cyl(0.056, 0.049, 0.24), jacket_mat, Vector3(0.0, -0.12, 0.0))

	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -0.24, 0.0)
	shoulder.add_child(elbow)
	_mk(elbow, _sph(0.048), jacket_mat, Vector3.ZERO)
	_mk(elbow, _cyl(0.048, 0.041, 0.22), jacket_mat, Vector3(0.0, -0.11, 0.0))
	_mk(elbow, _cyl(0.042, 0.040, 0.034), rib_mat, Vector3(0.0, -0.215, 0.0))
	_mk(elbow, _box(Vector3(0.056, 0.076, 0.044)), skin_mat, Vector3(0.0, -0.265, -0.008))
	return [shoulder, elbow]


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
		_fp_weapon_mount.add_child(WeaponArsenal.build_weapon_node(idx, suppressed, 0.86))


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
		_pitch = clampf(_pitch - mm.relative.y * sens, -1.22, 1.18)
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
			_body_root.rotation.y = 0.0
	elif not is_local_player():
		global_position = global_position.lerp(_target_pos, minf(1.0, delta * 14.0))
		_body_yaw = lerp_angle(_body_yaw, _target_yaw, minf(1.0, delta * 14.0))
		_body_root.rotation.y = _body_yaw

	if not is_local_player():
		var remote_vel: Vector3 = (global_position - prev_pos) / maxf(0.001, delta)
		var remote_spd: float = Vector2(remote_vel.x, remote_vel.z).length()
		_animate_character(delta, remote_spd)
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	_combat_stance_t = maxf(0.0, _combat_stance_t - delta)
	_melee_swing_t = maxf(0.0, _melee_swing_t - delta)
	_recoil_kick = lerpf(_recoil_kick, 0.0, minf(1.0, delta * 14.0))
	_land_dip = lerpf(_land_dip, 0.0, minf(1.0, delta * 12.0))
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			mags[active_weapon_idx] = int(get_active_weapon_def()["mag_size"])

	# Vitais de sobrevivencia (suaves; modo Deus mantem sempre cheio)
	if god_mode:
		hp = 200
		stamina = 100.0
		hunger = 100.0
		thirst = 100.0
		is_dead = false
	elif not is_dead:
		hunger = maxf(0.0, hunger - delta * 0.05)
		thirst = maxf(0.0, thirst - delta * 0.08)

	var blocked: bool = _world != null and _world.is_ui_blocking()
	var aiming: bool = (not blocked) and (not is_dead) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and (current_vehicle == null or current_seat > 0)
	_ads_alpha = lerpf(_ads_alpha, 1.0 if aiming else 0.0, minf(1.0, delta * 12.0))

	var move_spd: float = 0.0
	if not blocked and not is_dead:
		if current_vehicle == null:
			move_spd = _tick_foot_movement(delta)
			_tick_trigger()
		else:
			_is_sprinting = false
			_local_move_vel = Vector2.ZERO
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
		if current_vehicle == null:
			velocity.x = lerpf(velocity.x, 0.0, minf(1.0, delta * 10.0))
			velocity.z = lerpf(velocity.z, 0.0, minf(1.0, delta * 10.0))
			if not is_on_floor():
				velocity.y -= 18.0 * delta
			move_and_slide()

	_animate_character(delta, move_spd)
	_update_camera_and_viewmodel(delta, move_spd)

	_sync_acc += delta
	if _sync_acc >= 0.042 and multiplayer.has_multiplayer_peer():
		_sync_acc = 0.0
		_rpc_sync_state.rpc(global_position, _body_yaw, nick, team_id, hp, is_dead, active_weapon_idx, suppressed)


func _tick_trigger() -> void:
	var held: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var w: Dictionary = get_active_weapon_def()
	var can_pull: bool = held if bool(w["auto"]) else (held and not _trigger_held_prev)
	_trigger_held_prev = held
	if can_pull and _fire_cd <= 0.0 and not reloading:
		_fire_weapon()


func _tick_foot_movement(delta: float) -> float:
	# Raiz do personagem nao trava mais na camera: o corpo gira livremente com W/A/S/D!
	rotation = Vector3.ZERO
	var fwd_in: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
	var str_in: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var crouch: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var has_input: bool = (absf(fwd_in) > 0.05 or absf(str_in) > 0.05)
	var wants_sprint: bool = Input.is_key_pressed(KEY_SHIFT) and not crouch and has_input and _ads_alpha < 0.25 and stamina > 4.0
	_is_sprinting = wants_sprint

	if wants_sprint:
		stamina = maxf(0.0, stamina - delta * 16.0)
	else:
		stamina = minf(100.0, stamina + delta * 15.0)

	_crouch_alpha = lerpf(_crouch_alpha, 1.0 if crouch else 0.0, minf(1.0, delta * 10.0))

	# Direcao de movimento relativa ao yaw da camera (_yaw)
	var cam_fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var cam_right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var move_dir: Vector3 = cam_fwd * fwd_in + cam_right * str_in
	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()

	var target_spd: float = 2.7 if crouch else (8.0 if wants_sprint else (3.8 if _ads_alpha > 0.35 else 5.3))
	var target_vx: float = move_dir.x * target_spd
	var target_vz: float = move_dir.z * target_spd
	var accel_k: float = 14.0 if has_input else 11.5
	if not is_on_floor():
		accel_k = 4.5
	velocity.x = lerpf(velocity.x, target_vx, minf(1.0, delta * accel_k))
	velocity.z = lerpf(velocity.z, target_vz, minf(1.0, delta * accel_k))

	# Decisao de orientacao do corpo (_body_yaw):
	# - Em 1P, mirando (RMB), ou logo apos atirar: corpo alinha a mira (strafing tatico lateral!)
	# - Em 3P exploracao livre: corpo gira suavemente para a direcao real do movimento (A=esquerda, D=direita, S=tras)!
	var lock_to_aim: bool = _first_person or _ads_alpha > 0.15 or _combat_stance_t > 0.0
	if lock_to_aim:
		_body_yaw = lerp_angle(_body_yaw, _yaw, minf(1.0, delta * 16.0))
	elif has_input:
		var move_yaw: float = atan2(-move_dir.x, -move_dir.z)
		_body_yaw = lerp_angle(_body_yaw, move_yaw, minf(1.0, delta * 11.0))

	_body_root.rotation.y = _body_yaw

	# Calcula velocidade local (frente/tras e esquerda/direita) em relacao ao corpo para strafing fluido
	var body_fwd := Vector3(-sin(_body_yaw), 0.0, -cos(_body_yaw))
	var body_right := Vector3(cos(_body_yaw), 0.0, -sin(_body_yaw))
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	_local_move_vel = Vector2(h_vel.dot(body_right), h_vel.dot(body_fwd))

	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor:
		_land_dip = 0.16
	_was_on_floor = on_floor_now

	if on_floor_now:
		if Input.is_key_pressed(KEY_SPACE) and not crouch:
			velocity.y = 5.8
	else:
		velocity.y -= 18.0 * delta

	move_and_slide()
	return Vector2(velocity.x, velocity.z).length()


func _animate_character(delta: float, h_spd: float) -> void:
	if _body_root == null:
		return

	# Controla visibilidade da arma 3P: MOTORISTA/PILOTO (assento 0) GUARDA A ARMA!
	var in_driver_seat: bool = (current_vehicle != null and current_seat == 0)
	if _weapon_aim_pivot != null:
		_weapon_aim_pivot.visible = not in_driver_seat and not is_dead

	# Se um modelo 3D externo (.glb/.tscn) com AnimationPlayer foi carregado, dirige seus clips
	if _ext_model != null:
		if current_vehicle != null:
			_body_root.position.y = -0.34 if current_vehicle.is_moto else -0.64
		else:
			_body_root.position.y = lerpf(0.0, -0.30, _crouch_alpha)
		_drive_external_animations(h_spd)
		return

	if _leg_l_hip == null or _leg_r_hip == null or _pelvis == null or _spine == null:
		return

	_idle_phase += delta * 2.2
	var lerp_k: float = minf(1.0, delta * 13.0)

	# 1. MORTE
	if is_dead:
		_body_root.position.y = lerpf(_body_root.position.y, 0.18, lerp_k)
		_body_root.rotation.x = lerpf(_body_root.rotation.x, deg_to_rad(86.0), lerp_k)
		return
	else:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, lerp_k)

	# 2. DENTRO DE VEICULO (CORRECAO TOTAL: cabeca dentro do teto + maos no volante/guidao!)
	if current_vehicle != null:
		var steer_v: float = current_vehicle.steer_smooth
		_pelvis.position.y = 0.93
		_pelvis.rotation = Vector3.ZERO
		if current_vehicle.is_moto:
			# Postura realista montado na moto
			_body_root.position.y = -0.36
			_spine.rotation = Vector3(deg_to_rad(-18.0 if current_seat == 0 else -10.0), 0.0, 0.0)
			_head_pivot.rotation = Vector3(deg_to_rad(10.0), clampf(steer_v * 0.28, -0.3, 0.3), 0.0)
			_leg_l_hip.rotation = Vector3(deg_to_rad(56.0), 0.0, deg_to_rad(-18.0))
			_leg_r_hip.rotation = Vector3(deg_to_rad(56.0), 0.0, deg_to_rad(18.0))
			_leg_l_knee.rotation.x = deg_to_rad(-76.0)
			_leg_r_knee.rotation.x = deg_to_rad(-76.0)
			if current_seat == 0:
				_arm_l.rotation = Vector3(deg_to_rad(64.0 + steer_v * 12.0), 0.0, deg_to_rad(-14.0))
				_elbow_l.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
				_arm_r.rotation = Vector3(deg_to_rad(64.0 - steer_v * 12.0), 0.0, deg_to_rad(14.0))
				_elbow_r.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
			else:
				_pose_weapon_arms(lerp_k, true)
		else:
			# Sentado DENTRO do carro (assento Y=0.28 + body Y=-0.64 -> topo do chapeu em 1.44m < teto 1.53m!)
			_body_root.position.y = -0.64
			_spine.rotation = Vector3(deg_to_rad(6.0), 0.0, 0.0)
			_head_pivot.rotation = Vector3(deg_to_rad(-4.0), clampf(steer_v * 0.22, -0.25, 0.25), 0.0)
			_leg_l_hip.rotation = Vector3(deg_to_rad(82.0), 0.0, deg_to_rad(-4.0))
			_leg_r_hip.rotation = Vector3(deg_to_rad(82.0), 0.0, deg_to_rad(4.0))
			_leg_l_knee.rotation.x = deg_to_rad(-82.0)
			_leg_r_knee.rotation.x = deg_to_rad(-82.0)
			if current_seat == 0:
				# Duas maos segurando o volante (sem arma atravessando o painel!)
				_arm_l.rotation = Vector3(deg_to_rad(54.0 + steer_v * 10.0), deg_to_rad(-12.0), deg_to_rad(14.0))
				_elbow_l.rotation = Vector3(deg_to_rad(30.0), 0.0, 0.0)
				_arm_r.rotation = Vector3(deg_to_rad(54.0 - steer_v * 10.0), deg_to_rad(12.0), deg_to_rad(-14.0))
				_elbow_r.rotation = Vector3(deg_to_rad(30.0), 0.0, 0.0)
			else:
				_pose_weapon_arms(lerp_k, true)
		return

	# 3. LOCOMOCAO A PE (FLUIDA, DIRECAO LIVRE + STRAFING TATICO!)
	var in_air: bool = not is_on_floor() and is_local_player()
	var stride_norm: float = clampf(h_spd / 7.8, 0.0, 1.0)
	var fwd_v: float = _local_move_vel.y
	var side_v: float = _local_move_vel.x
	var is_combat: bool = _ads_alpha > 0.15 or _combat_stance_t > 0.0 or _first_person

	if h_spd > 0.20 and not in_air:
		_walk_phase += delta * clampf(h_spd * 2.15, 4.5, 14.5)
	var sw: float = sin(_walk_phase)
	var cw: float = cos(_walk_phase)

	# Altura da pelve (agachar + passo natural + aterrissagem + respiracao)
	var bob_y: float = (absf(sw) * 0.045 * stride_norm) if (h_spd > 0.20 and not in_air) else (sin(_idle_phase) * 0.010)
	var target_root_y: float = lerpf(0.0, -0.34, _crouch_alpha) - _land_dip + bob_y
	_body_root.position.y = lerpf(_body_root.position.y, target_root_y, lerp_k)

	# Giro sutil de quadril no strafe + contrarrotacao da coluna para manter mira reta
	var strafe_ratio: float = clampf(side_v / 4.8, -1.0, 1.0)
	var fwd_ratio: float = clampf(fwd_v / 6.5, -1.0, 1.0)
	var pelvis_twist: float = -strafe_ratio * 0.30 if is_combat else (sw * 0.06 * stride_norm)
	_pelvis.rotation.y = lerpf(_pelvis.rotation.y, pelvis_twist, lerp_k)
	_pelvis.rotation.z = lerpf(_pelvis.rotation.z, -strafe_ratio * 0.06, lerp_k)

	var lean_fwd: float = lerpf(-0.04, -0.22, _crouch_alpha) - clampf(fwd_ratio, 0.0, 1.0) * 0.14
	var lean_side: float = -strafe_ratio * 0.08
	_spine.rotation.x = lerpf(_spine.rotation.x, lean_fwd, lerp_k)
	_spine.rotation.y = lerpf(_spine.rotation.y, -pelvis_twist * 0.85, lerp_k)
	_spine.rotation.z = lerpf(_spine.rotation.z, lean_side, lerp_k)

	# Cabeca olha levemente na direcao da camera/mira
	var head_yaw_diff: float = wrapf(_yaw - _body_yaw, -PI, PI)
	var target_head_y: float = clampf(head_yaw_diff * 0.55, -0.65, 0.65)
	_head_pivot.rotation.y = lerpf(_head_pivot.rotation.y, target_head_y, lerp_k)
	_head_pivot.rotation.x = lerpf(_head_pivot.rotation.x, clampf(_pitch * 0.50, -0.5, 0.5), lerp_k)

	# Pernas: Pulo / Agachado / Corrida & Strafing Lateral real!
	if in_air:
		_leg_l_hip.rotation = _leg_l_hip.rotation.lerp(Vector3(deg_to_rad(32.0), 0.0, deg_to_rad(-4.0)), lerp_k)
		_leg_r_hip.rotation = _leg_r_hip.rotation.lerp(Vector3(deg_to_rad(14.0), 0.0, deg_to_rad(4.0)), lerp_k)
		_leg_l_knee.rotation.x = lerpf(_leg_l_knee.rotation.x, deg_to_rad(-55.0), lerp_k)
		_leg_r_knee.rotation.x = lerpf(_leg_r_knee.rotation.x, deg_to_rad(-28.0), lerp_k)
	elif h_spd > 0.22:
		var fwd_dir_sign: float = -1.0 if (fwd_v < -0.35 and is_combat) else 1.0
		var amp_x: float = minf(0.76, (absf(fwd_v) * 0.11 + (0.0 if is_combat else absf(side_v) * 0.09)))
		var amp_z: float = minf(0.32, absf(side_v) * 0.065) if is_combat else 0.0
		var crouch_hip_bias: float = deg_to_rad(34.0) * _crouch_alpha
		var crouch_knee_bias: float = deg_to_rad(-58.0) * _crouch_alpha

		var lx: float = sw * amp_x * fwd_dir_sign + crouch_hip_bias
		var rx: float = -sw * amp_x * fwd_dir_sign + crouch_hip_bias
		var lz: float = sw * amp_z - deg_to_rad(3.0)
		var rz: float = -sw * amp_z + deg_to_rad(3.0)

		_leg_l_hip.rotation = _leg_l_hip.rotation.lerp(Vector3(lx, 0.0, lz), lerp_k)
		_leg_r_hip.rotation = _leg_r_hip.rotation.lerp(Vector3(rx, 0.0, rz), lerp_k)

		var l_knee: float = crouch_knee_bias - maxf(0.0, -cw * 0.72 * stride_norm + 0.12 * stride_norm)
		var r_knee: float = crouch_knee_bias - maxf(0.0, cw * 0.72 * stride_norm + 0.12 * stride_norm)
		_leg_l_knee.rotation.x = lerpf(_leg_l_knee.rotation.x, l_knee, lerp_k)
		_leg_r_knee.rotation.x = lerpf(_leg_r_knee.rotation.x, r_knee, lerp_k)
	else:
		# Parado em pe ou agachado tatico
		var l_idle_hip := Vector3(deg_to_rad(44.0) * _crouch_alpha, 0.0, deg_to_rad(-4.0))
		var r_idle_hip := Vector3(deg_to_rad(34.0) * _crouch_alpha, 0.0, deg_to_rad(4.0))
		_leg_l_hip.rotation = _leg_l_hip.rotation.lerp(l_idle_hip, lerp_k)
		_leg_r_hip.rotation = _leg_r_hip.rotation.lerp(r_idle_hip, lerp_k)
		_leg_l_knee.rotation.x = lerpf(_leg_l_knee.rotation.x, deg_to_rad(-82.0) * _crouch_alpha, lerp_k)
		_leg_r_knee.rotation.x = lerpf(_leg_r_knee.rotation.x, deg_to_rad(-66.0) * _crouch_alpha, lerp_k)

	# 4. POSICIONAMENTO DA ARMA NAS 2 MAOS + BRACOS ARTICULADOS
	_pose_weapon_arms(lerp_k, is_combat)


func _pose_weapon_arms(lerp_k: float, is_combat: bool) -> void:
	var w: Dictionary = get_active_weapon_def()
	var is_melee: bool = bool(w["melee"])
	var two_hand: bool = bool(w["two_hand"])
	var aim_p: float = clampf(_pitch * 0.72, -0.68, 0.68) if is_combat else clampf(_pitch * 0.25, -0.25, 0.25)
	var walk_sway: float = sin(_walk_phase) * 0.03 * clampf(Vector2(velocity.x, velocity.z).length() / 6.0, 0.0, 1.0)

	# Calcula swing de faca/katana ou inclinacao de recarga
	var slash_rot_x: float = 0.0
	var slash_rot_y: float = 0.0
	if _melee_swing_t > 0.0:
		var u: float = 1.0 - clampf(_melee_swing_t / 0.28, 0.0, 1.0)
		var arc: float = sin(u * PI)
		slash_rot_x = -arc * 1.15
		slash_rot_y = (u - 0.5) * 1.65

	var rel_rot_z: float = 0.42 if reloading else 0.0
	var rel_drop_y: float = -0.07 if reloading else 0.0

	if _weapon_aim_pivot != null:
		var target_wp_pos: Vector3
		var target_wp_rot: Vector3
		if is_melee:
			target_wp_pos = Vector3(0.24, 0.22 + rel_drop_y, -0.22)
			target_wp_rot = Vector3(deg_to_rad(-18.0) + slash_rot_x, deg_to_rad(-10.0) + slash_rot_y, deg_to_rad(-8.0))
		elif two_hand:
			# Fuzil / SMG / Escopeta / Sniper encostado no ombro direito e apoiado na mao esquerda!
			var ready_pos := Vector3(0.14, 0.30 + rel_drop_y, -0.24 + _recoil_kick * 0.07)
			var ads_pos := Vector3(0.11, 0.35 + rel_drop_y, -0.21 + _recoil_kick * 0.05)
			var relaxed_pos := Vector3(0.15, 0.25 + rel_drop_y, -0.22)
			target_wp_pos = ready_pos.lerp(ads_pos, _ads_alpha) if is_combat else relaxed_pos
			var relaxed_pitch: float = deg_to_rad(-16.0) if not is_combat else aim_p
			var relaxed_yaw: float = deg_to_rad(22.0) if not is_combat else 0.0
			target_wp_rot = Vector3(relaxed_pitch + _recoil_kick * 0.22, relaxed_yaw + walk_sway, rel_rot_z)
		else:
			# Pistola / Revolver na linha dos olhos em combate, abaixada com naturalidade ao explorar
			var p_combat := Vector3(0.15, 0.34 + rel_drop_y, -0.32 + _recoil_kick * 0.06)
			var p_relax := Vector3(0.21, 0.22 + rel_drop_y, -0.24)
			target_wp_pos = p_combat if is_combat else p_relax
			target_wp_rot = Vector3((aim_p if is_combat else deg_to_rad(-28.0)) + _recoil_kick * 0.28, walk_sway, rel_rot_z)

		_weapon_aim_pivot.position = _weapon_aim_pivot.position.lerp(target_wp_pos, lerp_k)
		_weapon_aim_pivot.rotation = _weapon_aim_pivot.rotation.lerp(target_wp_rot, lerp_k)

	# Posicao dos bracos direito e esquerdo acompanhando a empunhadura da arma!
	if is_melee:
		_arm_r.rotation = _arm_r.rotation.lerp(Vector3(deg_to_rad(36.0) + slash_rot_x * 0.8, slash_rot_y * 0.5, deg_to_rad(-12.0)), lerp_k)
		_elbow_r.rotation = _elbow_r.rotation.lerp(Vector3(deg_to_rad(42.0), 0.0, 0.0), lerp_k)
		var l_swing: float = sin(_walk_phase) * 0.52 * clampf(Vector2(velocity.x, velocity.z).length() / 5.5, 0.0, 1.0)
		_arm_l.rotation = _arm_l.rotation.lerp(Vector3(l_swing, 0.0, deg_to_rad(-8.0)), lerp_k)
		_elbow_l.rotation = _elbow_l.rotation.lerp(Vector3(deg_to_rad(18.0), 0.0, 0.0), lerp_k)
	elif two_hand:
		# Braco direito dobra no cotovelo segurando o pistol grip
		var r_sh := Vector3(deg_to_rad(48.0 if is_combat else 30.0) + aim_p * 0.55 + _recoil_kick * 0.25, deg_to_rad(-14.0), deg_to_rad(-10.0))
		var r_el := Vector3(deg_to_rad(56.0 if is_combat else 46.0), 0.0, deg_to_rad(14.0))
		# Braco esquerdo cruza a frente segurando o guarda-mao (foregrip) — ou desce ao recarregar!
		var l_sh := Vector3(deg_to_rad(58.0 if is_combat else 40.0) + aim_p * 0.45, deg_to_rad(28.0 if is_combat else 34.0), deg_to_rad(22.0))
		var l_el := Vector3(deg_to_rad(48.0 if not reloading else 82.0), deg_to_rad(16.0), 0.0)
		_arm_r.rotation = _arm_r.rotation.lerp(r_sh, lerp_k)
		_elbow_r.rotation = _elbow_r.rotation.lerp(r_el, lerp_k)
		_arm_l.rotation = _arm_l.rotation.lerp(l_sh, lerp_k)
		_elbow_l.rotation = _elbow_l.rotation.lerp(l_el, lerp_k)
	else:
		# Pistola: 2 maos juntas em combate, braco esquerdo livre ao caminhar!
		var r_sh := Vector3(deg_to_rad(72.0 if is_combat else 26.0) + aim_p * 0.65 + _recoil_kick * 0.30, deg_to_rad(-8.0), deg_to_rad(-6.0))
		var r_el := Vector3(deg_to_rad(18.0 if is_combat else 28.0), 0.0, 0.0)
		_arm_r.rotation = _arm_r.rotation.lerp(r_sh, lerp_k)
		_elbow_r.rotation = _elbow_r.rotation.lerp(r_el, lerp_k)
		if is_combat:
			_arm_l.rotation = _arm_l.rotation.lerp(Vector3(deg_to_rad(68.0) + aim_p * 0.60, deg_to_rad(26.0), deg_to_rad(14.0)), lerp_k)
			_elbow_l.rotation = _elbow_l.rotation.lerp(Vector3(deg_to_rad(24.0), 0.0, 0.0), lerp_k)
		else:
			var l_sw: float = sin(_walk_phase) * 0.50 * clampf(Vector2(velocity.x, velocity.z).length() / 5.5, 0.0, 1.0)
			_arm_l.rotation = _arm_l.rotation.lerp(Vector3(l_sw, 0.0, deg_to_rad(-6.0)), lerp_k)
			_elbow_l.rotation = _elbow_l.rotation.lerp(Vector3(deg_to_rad(18.0), 0.0, 0.0), lerp_k)


func _drive_external_animations(h_spd: float) -> void:
	if _ext_anim == null:
		return
	var desired: String = ""
	if is_dead:
		desired = AssetBridge.find_best_anim_name(_ext_anim, ["death", "die"])
	elif reloading:
		desired = AssetBridge.find_best_anim_name(_ext_anim, ["reload"])
	elif _crouch_alpha > 0.45:
		desired = AssetBridge.find_best_anim_name(_ext_anim, ["crouch", "kneel"])
	elif h_spd > 0.35:
		if absf(_local_move_vel.x) > absf(_local_move_vel.y) * 1.15 and (_ads_alpha > 0.15 or _combat_stance_t > 0.0):
			desired = AssetBridge.find_best_anim_name(_ext_anim, ["strafe_right", "right"] if _local_move_vel.x > 0.0 else ["strafe_left", "left"])
		elif _local_move_vel.y < -0.35 and (_ads_alpha > 0.15 or _combat_stance_t > 0.0):
			desired = AssetBridge.find_best_anim_name(_ext_anim, ["walk_back", "run_back", "back"])
		elif _is_sprinting or h_spd > 6.0:
			desired = AssetBridge.find_best_anim_name(_ext_anim, ["run_fwd", "run", "sprint"])
		else:
			desired = AssetBridge.find_best_anim_name(_ext_anim, ["walk_fwd", "walk"])
	else:
		desired = AssetBridge.find_best_anim_name(_ext_anim, ["rifle_idle", "idle"])

	if not desired.is_empty() and desired != _ext_cur_anim:
		_ext_cur_anim = desired
		_ext_anim.play(desired, 0.16)


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

	# Pivot da camera acompanha altura (em pe / agachado) e orbita livremente em torno do jogador!
	_cam_pivot.position = Vector3(0.0, lerpf(1.62, 1.18, _crouch_alpha), 0.0)
	_cam_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
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
		var dist: float = lerpf(3.35, 1.68, _ads_alpha)
		_cam.position = Vector3(0.56 * _shoulder_sign, 0.16, dist)


func _fire_weapon() -> void:
	if _cam == null or _world == null:
		return
	var w: Dictionary = get_active_weapon_def()
	var is_melee: bool = bool(w["melee"])
	if not is_melee:
		if mags[active_weapon_idx] <= 0 and not infinite_ammo:
			start_reload()
			return
		if not infinite_ammo:
			mags[active_weapon_idx] -= 1
	else:
		_melee_swing_t = 0.28

	_combat_stance_t = 1.65
	_fire_cd = float(w["cooldown"])
	var recoil: float = float(w["recoil"]) * lerpf(1.0, 0.58, _ads_alpha)
	_pitch = clampf(_pitch + recoil, -1.22, 1.18)
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

	if not is_melee and not infinite_ammo and mags[active_weapon_idx] <= 0:
		start_reload()


func _handle_interact(prefer_passenger: bool) -> void:
	if _world == null:
		return
	if current_vehicle != null:
		current_vehicle.request_exit(peer_id)
		return
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
		_body_root.rotation = Vector3.ZERO
	else:
		rotation = Vector3.ZERO
		_body_root.position.y = 0.0
		_body_yaw = _yaw


func apply_damage(amount: int) -> void:
	if is_dead or god_mode:
		return
	hp = maxi(0, hp - amount)
	if hp <= 0:
		is_dead = true


func heal_and_restock() -> void:
	is_dead = false
	hp = 200
	hunger = 100.0
	thirst = 100.0
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
