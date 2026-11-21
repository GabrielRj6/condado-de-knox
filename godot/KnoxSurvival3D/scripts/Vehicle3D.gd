extends CharacterBody3D
class_name Vehicle3D

## Veiculo 3D detalhado 1:1 portado de buildDrivableVehicle() do Knox Survival 3D:
## - Motocicleta composta (14+ pecas: quadro, motor metalico, tanque, carenagens, banco duplo
##   Piloto+Garupa, pedaleiras cromadas, escapamento, garfo dianteiro articulado com guidao e farol).
## - Carro 4 lugares (capo, porta-malas, portas, teto, pilares A/B/C, painel, volante, 4 bancos,
##   vidros transparentes, para-choques cromados, farois/lanternas, giroflex policial).
## - Freia limpo ate 0 km/h + rodas giram + guidão/rodas dianteiras estercam + audio 3D.

var vehicle_id: String = ""
var label: String = "KNOX SEDAN '92"
var is_moto: bool = false
var is_police: bool = false
var moto_style: String = "" # "trail" ou "street"
var max_speed: float = 28.0
var reverse_max: float = 8.5
var accel_rate: float = 15.5
var brake_rate: float = 32.0
var coast_drag: float = 5.5
var steer_deg_sec: float = 95.0

var seats: Array[int] = [] # peer_id ou 0 se vazio
var speed_mps: float = 0.0
var steer_smooth: float = 0.0
var drift_alpha: float = 0.0
var lights_on: bool = false

var _in_thr: float = 0.0
var _in_str: float = 0.0
var _in_hb: bool = false
var _sync_acc: float = 0.0
var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0

var _visual_root: Node3D
var _seat_nodes: Array[Node3D] = []
var _headlights: Array[SpotLight3D] = []
var _hl_mat: StandardMaterial3D
var _tl_mat: StandardMaterial3D
var _steer_pivots: Array[Node3D] = []
var _spin_wheels: Array[Node3D] = []
var _steer_wheel_mesh: Node3D = null
var _engine_audio: AudioStreamPlayer3D
var _drift_audio: AudioStreamPlayer3D
var _world: Node = null


func setup(p_id: String, p_world: Node, kind: int) -> void:
	vehicle_id = p_id
	_world = p_world
	name = "Veh_%s" % p_id
	if kind == 1:
		is_moto = true
		is_police = false
		moto_style = "trail"
		label = "MOTO TRAIL 450"
		max_speed = 31.0
		accel_rate = 18.5
		steer_deg_sec = 122.0
		seats = [0, 0]
	elif kind == 2:
		is_moto = true
		is_police = false
		moto_style = "street"
		label = "MOTO STREET 600"
		max_speed = 38.0
		accel_rate = 21.5
		steer_deg_sec = 114.0
		seats = [0, 0]
	elif kind == 3:
		is_moto = false
		is_police = true
		moto_style = ""
		label = "VIATURA KNOX PD"
		max_speed = 33.0
		accel_rate = 17.5
		steer_deg_sec = 94.0
		seats = [0, 0, 0, 0]
	else:
		is_moto = false
		is_police = false
		moto_style = ""
		label = "KNOX SEDAN '92"
		max_speed = 28.5
		accel_rate = 15.0
		steer_deg_sec = 88.0
		seats = [0, 0, 0, 0]


func _ready() -> void:
	_build_vehicle_mesh()
	_setup_audio_nodes()
	_net_pos = global_position
	_net_yaw = rotation.y


func _mk_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot_x: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation.x = rot_x
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _mk_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_vehicle_mesh() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.76, 1.05, 2.2) if is_moto else Vector3(2.02, 1.56, 4.65)
	col.shape = box
	col.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	add_child(col)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	var body_mat := StandardMaterial3D.new()
	if is_moto:
		body_mat.albedo_color = Color.html("#c44a1c") if moto_style == "trail" else Color.html("#1a2b4c")
		body_mat.roughness = 0.30
		body_mat.metallic = 0.58
	elif is_police:
		body_mat.albedo_color = Color.html("#1d232b")
		body_mat.roughness = 0.38
		body_mat.metallic = 0.52
	else:
		body_mat.albedo_color = Color.html("#344e68")
		body_mat.roughness = 0.42
		body_mat.metallic = 0.48

	var cab_mat := body_mat
	if is_police:
		cab_mat = StandardMaterial3D.new()
		cab_mat.albedo_color = Color.html("#dad6cc")
		cab_mat.roughness = 0.48

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color.html("#1f2226")
	trim_mat.roughness = 0.78
	trim_mat.metallic = 0.25

	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color.html("#3b4046")
	engine_mat.roughness = 0.44
	engine_mat.metallic = 0.74

	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color.html("#26221e")
	seat_mat.roughness = 0.90

	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color.html("#141517")
	tire_mat.roughness = 0.92

	var chrome_mat: StandardMaterial3D = ProceduralTextures.get_chrome_mat()
	var glass_mat: StandardMaterial3D = ProceduralTextures.get_car_glass_mat()

	_hl_mat = StandardMaterial3D.new()
	_hl_mat.albedo_color = Color.html("#98968a")
	_hl_mat.emission = Color(1.0, 0.95, 0.78)
	_hl_mat.emission_enabled = false

	_tl_mat = StandardMaterial3D.new()
	_tl_mat.albedo_color = Color.html("#8c1c1c")
	_tl_mat.emission = Color(1.0, 0.14, 0.10)
	_tl_mat.emission_enabled = true
	_tl_mat.emission_energy_multiplier = 0.6

	if is_moto:
		# === MOTOCICLETA 3D COMPOSTA (14+ PECAS IDENTICAS AO WEB) ===
		_mk_box(_visual_root, Vector3(0.28, 0.30, 1.06), Vector3(0.0, 0.54, 0.04), trim_mat)
		_mk_box(_visual_root, Vector3(0.36, 0.34, 0.46), Vector3(0.0, 0.44, -0.10), engine_mat)
		_mk_box(_visual_root, Vector3(0.40, 0.26, 0.62), Vector3(0.0, 0.84, -0.32), body_mat, 0.14)
		_mk_box(_visual_root, Vector3(0.06, 0.24, 0.56), Vector3(-0.21, 0.72, -0.34), body_mat)
		_mk_box(_visual_root, Vector3(0.06, 0.24, 0.56), Vector3(0.21, 0.72, -0.34), body_mat)

		# Rabeta + Banco duplo escalonado (Piloto + Garupa)
		_mk_box(_visual_root, Vector3(0.32, 0.16, 0.72), Vector3(0.0, 0.80, 0.58), body_mat, -0.10)
		_mk_box(_visual_root, Vector3(0.32, 0.11, 0.48), Vector3(0.0, 0.78, 0.08), seat_mat)
		_mk_box(_visual_root, Vector3(0.28, 0.11, 0.42), Vector3(0.0, 0.87, 0.54), seat_mat)

		# Pedaleiras cromadas + Escapamento cromado + Balanca + Lanterna traseira
		_mk_cyl(_visual_root, 0.02, 0.02, 0.58, Vector3(0.0, 0.34, 0.04), chrome_mat, Vector3(0.0, 0.0, PI * 0.5))
		_mk_cyl(_visual_root, 0.02, 0.02, 0.58, Vector3(0.0, 0.46, 0.56), chrome_mat, Vector3(0.0, 0.0, PI * 0.5))
		_mk_cyl(_visual_root, 0.052, 0.046, 0.82, Vector3(0.22, 0.44, 0.48), chrome_mat, Vector3(PI * 0.5 - 0.18, 0.0, 0.0))
		_mk_box(_visual_root, Vector3(0.24, 0.08, 0.62), Vector3(0.0, 0.36, 0.52), engine_mat)
		_mk_box(_visual_root, Vector3(0.22, 0.06, 0.38), Vector3(0.0, 0.72, 0.90), trim_mat, 0.32)
		_mk_box(_visual_root, Vector3(0.18, 0.07, 0.05), Vector3(0.0, 0.82, 0.96), _tl_mat)

		# Conjunto dianteiro articulado (garfo, guidao, farol, para-brisa e roda dianteira)
		var front_pivot := Node3D.new()
		front_pivot.position = Vector3(0.0, 0.34, -0.78)
		_visual_root.add_child(front_pivot)
		_steer_pivots.append(front_pivot)

		_mk_cyl(front_pivot, 0.028, 0.026, 0.78, Vector3(-0.12, 0.36, 0.10), chrome_mat, Vector3(0.28, 0.0, 0.0))
		_mk_cyl(front_pivot, 0.028, 0.026, 0.78, Vector3(0.12, 0.36, 0.10), chrome_mat, Vector3(0.28, 0.0, 0.0))
		_mk_box(front_pivot, Vector3(0.18, 0.05, 0.42), Vector3(0.0, 0.36, -0.02), body_mat, 0.14)
		_mk_cyl(front_pivot, 0.018, 0.018, 0.74, Vector3(0.0, 0.74, 0.27), trim_mat, Vector3(0.0, 0.0, PI * 0.5))
		_mk_box(front_pivot, Vector3(0.24, 0.20, 0.18), Vector3(0.0, 0.64, 0.06), body_mat)
		_mk_cyl(front_pivot, 0.085, 0.085, 0.06, Vector3(0.0, 0.64, -0.04), _hl_mat, Vector3(PI * 0.5, 0.0, 0.0))
		if moto_style == "street":
			_mk_box(front_pivot, Vector3(0.26, 0.20, 0.04), Vector3(0.0, 0.80, 0.09), glass_mat, 0.55)

		var front_spin := Node3D.new()
		front_pivot.add_child(front_spin)
		_mk_cyl(front_spin, 0.34, 0.34, 0.15, Vector3.ZERO, tire_mat, Vector3(0.0, 0.0, PI * 0.5))
		_mk_cyl(front_spin, 0.21, 0.21, 0.16, Vector3.ZERO, chrome_mat, Vector3(0.0, 0.0, PI * 0.5))
		_spin_wheels.append(front_spin)

		# Roda traseira
		var rear_pivot := Node3D.new()
		rear_pivot.position = Vector3(0.0, 0.34, 0.78)
		_visual_root.add_child(rear_pivot)
		var rear_spin := Node3D.new()
		rear_pivot.add_child(rear_spin)
		_mk_cyl(rear_spin, 0.34, 0.34, 0.15, Vector3.ZERO, tire_mat, Vector3(0.0, 0.0, PI * 0.5))
		_mk_cyl(rear_spin, 0.21, 0.21, 0.16, Vector3.ZERO, chrome_mat, Vector3(0.0, 0.0, PI * 0.5))
		_spin_wheels.append(rear_spin)

		# Assentos Piloto (0) e Garupa (1) alinhados EXATAMENTE sobre os bancos!
		var s_pilot := Node3D.new()
		s_pilot.position = Vector3(0.0, 0.52, 0.06)
		_visual_root.add_child(s_pilot)
		var s_garupa := Node3D.new()
		s_garupa.position = Vector3(0.0, 0.61, 0.54)
		_visual_root.add_child(s_garupa)
		_seat_nodes = [s_pilot, s_garupa]

		_add_headlight(Vector3(0.0, 0.98, -0.88))
	else:
		# === CARRO 4 LUGARES COM INTERIOR VISIVEL E VIDROS TRANSPARENTES ===
		_mk_box(_visual_root, Vector3(1.98, 0.20, 4.55), Vector3(0.0, 0.30, 0.0), trim_mat)
		_mk_box(_visual_root, Vector3(2.02, 0.54, 1.44), Vector3(0.0, 0.62, -1.58), body_mat)
		_mk_box(_visual_root, Vector3(2.02, 0.56, 1.18), Vector3(0.0, 0.63, 1.72), body_mat)
		_mk_box(_visual_root, Vector3(0.14, 0.54, 2.08), Vector3(-0.94, 0.62, 0.14), cab_mat if is_police else body_mat)
		_mk_box(_visual_root, Vector3(0.14, 0.54, 2.08), Vector3(0.94, 0.62, 0.14), cab_mat if is_police else body_mat)
		_mk_box(_visual_root, Vector3(1.86, 0.10, 2.04), Vector3(0.0, 1.58, 0.16), cab_mat)

		# Pilares A, B e C
		_mk_box(_visual_root, Vector3(0.10, 0.76, 0.11), Vector3(-0.88, 1.22, -0.84), cab_mat, 0.28)
		_mk_box(_visual_root, Vector3(0.10, 0.76, 0.11), Vector3(0.88, 1.22, -0.84), cab_mat, 0.28)
		_mk_box(_visual_root, Vector3(0.10, 0.72, 0.12), Vector3(-0.88, 1.23, 0.14), trim_mat)
		_mk_box(_visual_root, Vector3(0.10, 0.72, 0.12), Vector3(0.88, 1.23, 0.14), trim_mat)
		_mk_box(_visual_root, Vector3(0.11, 0.76, 0.14), Vector3(-0.88, 1.22, 1.12), cab_mat, -0.24)
		_mk_box(_visual_root, Vector3(0.11, 0.76, 0.14), Vector3(0.88, 1.22, 1.12), cab_mat, -0.24)

		# Painel e Volante
		_mk_box(_visual_root, Vector3(1.74, 0.34, 0.38), Vector3(0.0, 0.84, -0.78), trim_mat)
		var sw := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.13
		torus.outer_radius = 0.17
		sw.mesh = torus
		sw.position = Vector3(-0.45, 0.94, -0.58)
		sw.rotation.x = PI * 0.5 - 0.35
		sw.material_override = trim_mat
		_visual_root.add_child(sw)
		_steer_wheel_mesh = sw

		# 4 Bancos internos + Nos de Assento
		var seat_offsets: Array[Vector3] = [
			Vector3(-0.46, 0.38, -0.18),
			Vector3(0.46, 0.38, -0.18),
			Vector3(-0.46, 0.38, 0.68),
			Vector3(0.46, 0.38, 0.68)
		]
		for so in seat_offsets:
			_mk_box(_visual_root, Vector3(0.56, 0.14, 0.50), Vector3(so.x, 0.46, so.z + 0.02), seat_mat)
			_mk_box(_visual_root, Vector3(0.54, 0.56, 0.12), Vector3(so.x, 0.78, so.z + 0.24), seat_mat, -0.14)
			var sn := Node3D.new()
			sn.position = so
			_visual_root.add_child(sn)
			_seat_nodes.append(sn)

		# Vidros transparentes
		_mk_box(_visual_root, Vector3(1.70, 0.72, 0.03), Vector3(0.0, 1.22, -0.85), glass_mat, 0.28)
		_mk_box(_visual_root, Vector3(1.70, 0.70, 0.03), Vector3(0.0, 1.22, 1.13), glass_mat, -0.24)
		_mk_box(_visual_root, Vector3(0.03, 0.62, 1.88), Vector3(-0.91, 1.22, 0.14), glass_mat)
		_mk_box(_visual_root, Vector3(0.03, 0.62, 1.88), Vector3(0.91, 1.22, 0.14), glass_mat)

		# Para-choques cromados + Farois + Lanternas
		_mk_box(_visual_root, Vector3(2.08, 0.18, 0.18), Vector3(0.0, 0.36, -2.35), chrome_mat)
		_mk_box(_visual_root, Vector3(2.08, 0.18, 0.18), Vector3(0.0, 0.36, 2.35), chrome_mat)
		_mk_box(_visual_root, Vector3(0.32, 0.14, 0.06), Vector3(-0.68, 0.58, -2.34), _hl_mat)
		_mk_box(_visual_root, Vector3(0.32, 0.14, 0.06), Vector3(0.68, 0.58, -2.34), _hl_mat)
		_mk_box(_visual_root, Vector3(0.32, 0.14, 0.06), Vector3(-0.68, 0.58, 2.34), _tl_mat)
		_mk_box(_visual_root, Vector3(0.32, 0.14, 0.06), Vector3(0.68, 0.58, 2.34), _tl_mat)

		if is_police:
			var red_m := StandardMaterial3D.new()
			red_m.albedo_color = Color(0.85, 0.14, 0.14)
			red_m.emission_enabled = true
			red_m.emission = Color(1.0, 0.15, 0.12)
			red_m.emission_energy_multiplier = 1.6
			var blue_m := StandardMaterial3D.new()
			blue_m.albedo_color = Color(0.14, 0.34, 0.90)
			blue_m.emission_enabled = true
			blue_m.emission = Color(0.18, 0.48, 1.0)
			blue_m.emission_energy_multiplier = 1.6
			_mk_box(_visual_root, Vector3(0.54, 0.12, 0.24), Vector3(-0.28, 1.67, 0.08), red_m)
			_mk_box(_visual_root, Vector3(0.54, 0.12, 0.24), Vector3(0.28, 1.67, 0.08), blue_m)

		# 4 Rodas com calotas cromadas
		var w_coords: Array = [
			[Vector3(-0.95, 0.35, -1.42), true],
			[Vector3(0.95, 0.35, -1.42), true],
			[Vector3(-0.95, 0.35, 1.42), false],
			[Vector3(0.95, 0.35, 1.42), false]
		]
		for wc in w_coords:
			var sp := Node3D.new()
			sp.position = wc[0]
			add_child(sp)
			if wc[1]:
				_steer_pivots.append(sp)
			var spin := Node3D.new()
			sp.add_child(spin)
			_mk_cyl(spin, 0.35, 0.35, 0.25, Vector3.ZERO, tire_mat, Vector3(0.0, 0.0, PI * 0.5))
			_mk_cyl(spin, 0.18, 0.18, 0.26, Vector3.ZERO, chrome_mat, Vector3(0.0, 0.0, PI * 0.5))
			_spin_wheels.append(spin)

		_add_headlight(Vector3(-0.68, 0.64, -2.38))
		_add_headlight(Vector3(0.68, 0.64, -2.38))


func _add_headlight(pos: Vector3) -> void:
	var hl := SpotLight3D.new()
	hl.position = pos
	hl.spot_range = 52.0
	hl.spot_angle = 44.0
	hl.light_color = Color(1.0, 0.96, 0.86)
	hl.light_energy = 8.5
	hl.visible = false
	_visual_root.add_child(hl)
	_headlights.append(hl)


func _setup_audio_nodes() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.position = Vector3(0.0, 0.7, -0.4 if is_moto else -1.2)
	_engine_audio.unit_size = 10.0
	_engine_audio.max_distance = 120.0 if is_moto else 105.0
	_engine_audio.volume_db = -80.0
	add_child(_engine_audio)

	_drift_audio = AudioStreamPlayer3D.new()
	_drift_audio.position = Vector3(0.0, 0.3, 0.8)
	_drift_audio.unit_size = 8.0
	_drift_audio.max_distance = 70.0
	_drift_audio.volume_db = -80.0
	add_child(_drift_audio)


func _physics_process(delta: float) -> void:
	var is_srv: bool = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()

	if is_srv:
		var has_driver: bool = seats.size() > 0 and seats[0] != 0
		var thr: float = _in_thr if has_driver else 0.0
		var str_in: float = _in_str if has_driver else 0.0
		var hb: bool = _in_hb and has_driver

		if hb:
			speed_mps = move_toward(speed_mps, 0.0, brake_rate * 1.45 * delta)
		elif thr > 0.05:
			if speed_mps < -0.2:
				speed_mps = move_toward(speed_mps, 0.0, brake_rate * delta)
			else:
				speed_mps = move_toward(speed_mps, max_speed, accel_rate * thr * delta)
		elif thr < -0.05:
			if speed_mps > 0.2:
				speed_mps = move_toward(speed_mps, 0.0, brake_rate * delta)
			else:
				speed_mps = move_toward(speed_mps, -reverse_max, accel_rate * 0.55 * (-thr) * delta)
		else:
			speed_mps = move_toward(speed_mps, 0.0, coast_drag * delta)
			if absf(speed_mps) < 0.08:
				speed_mps = 0.0

		steer_smooth = lerpf(steer_smooth, str_in, minf(1.0, delta * 10.0))
		var spd_factor: float = clampf(absf(speed_mps) / 3.5, 0.0, 1.0)
		var dir_sign: float = 1.0 if speed_mps >= 0.0 else -1.0
		rotation.y += deg_to_rad(steer_smooth * steer_deg_sec * spd_factor * dir_sign * (1.35 if hb else 1.0) * delta)

		var fwd: Vector3 = -global_transform.basis.z
		velocity.x = fwd.x * speed_mps
		velocity.z = fwd.z * speed_mps
		velocity.y = -4.0 if is_on_floor() else (velocity.y - 22.0 * delta)
		move_and_slide()

		drift_alpha = lerpf(drift_alpha, 1.0 if (hb and absf(speed_mps) > 5.5 and absf(str_in) > 0.2) else 0.0, minf(1.0, delta * 10.0))

		_sync_acc += delta
		if _sync_acc >= 0.04 and multiplayer.has_multiplayer_peer():
			_sync_acc = 0.0
			_rpc_sync_vehicle.rpc(global_position, rotation.y, speed_mps, steer_smooth, drift_alpha)
	else:
		global_position = global_position.lerp(_net_pos, minf(1.0, delta * 15.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 15.0))

	_update_visual_motion(delta)
	_update_engine_audio(delta)


func _update_visual_motion(delta: float) -> void:
	if _visual_root == null:
		return
	if is_moto:
		var lean_rad: float = clampf(steer_smooth * clampf(absf(speed_mps) / 14.0, 0.0, 1.0) * 0.44, -0.46, 0.46)
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, lean_rad, minf(1.0, delta * 10.0))
	else:
		var roll_rad: float = clampf(-steer_smooth * clampf(absf(speed_mps) / 22.0, 0.0, 1.0) * 0.08, -0.10, 0.10)
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, roll_rad, minf(1.0, delta * 10.0))

	# Esterco do garfo/rodas dianteiras + giro proporcional das rodas
	for sp in _steer_pivots:
		if is_instance_valid(sp):
			sp.rotation.y = steer_smooth * (0.48 if is_moto else 0.42)
	var spin_step: float = -(speed_mps / 0.35) * delta
	for sw in _spin_wheels:
		if is_instance_valid(sw):
			sw.rotation.x += spin_step
	if _steer_wheel_mesh != null:
		_steer_wheel_mesh.rotation.y = steer_smooth * 1.4


func _update_engine_audio(delta: float) -> void:
	if _engine_audio == null or _world == null or _world.audio_3d == null:
		return
	if _engine_audio.stream == null:
		_engine_audio.stream = _world.audio_3d.get_engine_clip(is_moto, moto_style)
		if _engine_audio.stream != null:
			_engine_audio.play()
	if _drift_audio != null and _drift_audio.stream == null:
		_drift_audio.stream = _world.audio_3d.clip_drift_loop
		if _drift_audio.stream != null:
			_drift_audio.play()

	var occupied: bool = false
	for sid in seats:
		if sid != 0:
			occupied = true
			break

	var abs_spd: float = absf(speed_mps)
	if not occupied and abs_spd < 0.35:
		_engine_audio.volume_db = lerpf(_engine_audio.volume_db, -80.0, minf(1.0, delta * 6.0))
		if _drift_audio != null:
			_drift_audio.volume_db = -80.0
		return

	var spd_norm: float = clampf(abs_spd / maxf(1.0, max_speed), 0.0, 1.0)
	var gears: float = 6.0 if moto_style == "street" else (5.0 if is_moto else 4.0)
	var gear_pos: float = fmod(spd_norm * gears, 1.0)
	var rpm: float = clampf(0.18 + spd_norm * 0.55 + gear_pos * 0.34, 0.0, 1.0)

	var target_pitch: float = lerpf(0.85, 2.35, rpm) if moto_style == "street" else (lerpf(0.78, 1.95, rpm) if is_moto else lerpf(0.72, 1.80, rpm))
	var target_db: float = lerpf(-14.0, -4.5, rpm)
	_engine_audio.pitch_scale = lerpf(_engine_audio.pitch_scale, target_pitch, minf(1.0, delta * 10.0))
	_engine_audio.volume_db = lerpf(_engine_audio.volume_db, target_db, minf(1.0, delta * 8.0))

	if _drift_audio != null:
		var dr_db: float = lerpf(-80.0, -8.0, drift_alpha)
		_drift_audio.volume_db = lerpf(_drift_audio.volume_db, dr_db, minf(1.0, delta * 10.0))


func get_seat_node(seat_idx: int) -> Node3D:
	if seat_idx >= 0 and seat_idx < _seat_nodes.size():
		return _seat_nodes[seat_idx]
	return _visual_root


func send_drive_input(thr: float, str_in: float, hb: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_in_thr = thr
		_in_str = str_in
		_in_hb = hb
	else:
		_rpc_drive_input.rpc_id(1, thr, str_in, hb)


func request_enter(pid: int, prefer_passenger: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_enter(pid, prefer_passenger)
	else:
		_rpc_req_enter.rpc_id(1, pid, prefer_passenger)


func request_switch_seat(pid: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_switch_seat(pid)
	else:
		_rpc_req_switch.rpc_id(1, pid)


func request_exit(pid: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_exit(pid)
	else:
		_rpc_req_exit.rpc_id(1, pid)


func request_toggle_lights() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_rpc_set_lights.rpc(not lights_on)
	else:
		_rpc_req_lights.rpc_id(1)


func request_horn() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_horn()
	else:
		_rpc_req_horn.rpc_id(1)


func _server_enter(pid: int, prefer_passenger: bool) -> void:
	var chosen: int = -1
	if prefer_passenger:
		for i in range(1, seats.size()):
			if seats[i] == 0:
				chosen = i
				break
	if chosen < 0:
		for i in range(seats.size()):
			if seats[i] == 0:
				chosen = i
				break
	if chosen < 0:
		return
	seats[chosen] = pid
	_rpc_apply_seat.rpc(pid, chosen, chosen == 0)


func _server_switch_seat(pid: int) -> void:
	var cur: int = seats.find(pid)
	if cur < 0:
		return
	for step in range(1, seats.size()):
		var nxt: int = (cur + step) % seats.size()
		if seats[nxt] == 0:
			seats[cur] = 0
			seats[nxt] = pid
			_rpc_apply_seat.rpc(pid, nxt, nxt == 0 and absf(speed_mps) < 0.8)
			return


func _server_exit(pid: int) -> void:
	var cur: int = seats.find(pid)
	if cur < 0:
		return
	seats[cur] = 0
	var side: float = -1.65 if (cur % 2 == 0) else 1.65
	var exit_pos: Vector3 = global_position + global_transform.basis.x * side + Vector3(0.0, 0.25, 0.0)
	_rpc_apply_exit.rpc(pid, exit_pos)


func _server_horn() -> void:
	if _world != null:
		_world.alert_zombies_in_radius(global_position, 65.0)
	_rpc_play_horn.rpc()


@rpc("any_peer", "call_local", "unreliable_ordered")
func _rpc_drive_input(thr: float, str_in: float, hb: bool) -> void:
	_in_thr = clampf(thr, -1.0, 1.0)
	_in_str = clampf(str_in, -1.0, 1.0)
	_in_hb = hb


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_enter(pid: int, pref: bool) -> void:
	if multiplayer.is_server():
		_server_enter(pid, pref)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_switch(pid: int) -> void:
	if multiplayer.is_server():
		_server_switch_seat(pid)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_exit(pid: int) -> void:
	if multiplayer.is_server():
		_server_exit(pid)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_lights() -> void:
	if multiplayer.is_server():
		_rpc_set_lights.rpc(not lights_on)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_horn() -> void:
	if multiplayer.is_server():
		_server_horn()


@rpc("authority", "call_local", "reliable")
func _rpc_apply_seat(pid: int, seat_idx: int, play_start: bool) -> void:
	for i in range(seats.size()):
		if seats[i] == pid:
			seats[i] = 0
	if seat_idx >= 0 and seat_idx < seats.size():
		seats[seat_idx] = pid
	if _world != null:
		var p: SurvivorPlayer = _world.get_player_by_peer(pid)
		if p != null:
			p.attach_to_vehicle(self, seat_idx)
		if play_start and _world.audio_3d != null:
			_world.audio_3d.play_engine_start_3d(is_moto, global_position)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_exit(pid: int, exit_pos: Vector3) -> void:
	for i in range(seats.size()):
		if seats[i] == pid:
			seats[i] = 0
	if _world != null:
		var p: SurvivorPlayer = _world.get_player_by_peer(pid)
		if p != null:
			p.attach_to_vehicle(null, -1)
			p.global_position = exit_pos


@rpc("authority", "call_local", "reliable")
func _rpc_set_lights(on: bool) -> void:
	lights_on = on
	for hl in _headlights:
		hl.visible = on
	if _hl_mat != null:
		_hl_mat.emission_enabled = on
		_hl_mat.emission_energy_multiplier = 2.4 if on else 0.0
	if _tl_mat != null:
		_tl_mat.emission_energy_multiplier = 2.0 if on else 0.6


@rpc("authority", "call_local", "reliable")
func _rpc_play_horn() -> void:
	if _world != null and _world.audio_3d != null:
		_world.audio_3d.play_horn_3d(is_moto, global_position)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_vehicle(p_pos: Vector3, p_yaw: float, p_spd: float, p_str: float, p_drift: float) -> void:
	_net_pos = p_pos
	_net_yaw = p_yaw
	speed_mps = p_spd
	steer_smooth = p_str
	drift_alpha = p_drift
