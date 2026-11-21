extends CharacterBody3D
class_name Vehicle3D

## Veiculo 3D (Carro 4 lugares | Moto Trail 450 & Street 600 com Piloto + Garupa).
## - Freia limpo ate 0 km/h (nunca fica travado andando a 15 km/h).
## - Alinhamento ao chao sem flutuar + inclinacao (lean) realista da moto nas curvas.
## - Assentos Piloto e Garupa posicionados corretamente sobre o banco da moto.
## - Motor continuo 3D, chiado de drift 3D, ignicao e buzina 3D sincronizados para todos!

var vehicle_id: String = ""
var label: String = "Knox Sedan '92"
var is_moto: bool = false
var moto_style: String = "" # "trail" ou "street"
var max_speed: float = 28.0
var reverse_max: float = 8.5
var accel_rate: float = 15.5
var brake_rate: float = 31.0
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
var _engine_audio: AudioStreamPlayer3D
var _drift_audio: AudioStreamPlayer3D
var _world: Node = null


func setup(p_id: String, p_world: Node, kind: int) -> void:
	vehicle_id = p_id
	_world = p_world
	name = "Veh_%s" % p_id
	if kind == 1:
		is_moto = true
		moto_style = "trail"
		label = "MOTO TRAIL 450"
		max_speed = 31.0
		accel_rate = 18.0
		steer_deg_sec = 122.0
		seats = [0, 0]
	elif kind == 2:
		is_moto = true
		moto_style = "street"
		label = "MOTO STREET 600"
		max_speed = 37.0
		accel_rate = 21.0
		steer_deg_sec = 114.0
		seats = [0, 0]
	else:
		is_moto = false
		moto_style = ""
		label = "KNOX SEDAN '92"
		max_speed = 28.0
		accel_rate = 14.5
		steer_deg_sec = 88.0
		seats = [0, 0, 0, 0]


func _ready() -> void:
	_build_vehicle_mesh()
	_setup_audio_nodes()
	_net_pos = global_position
	_net_yaw = rotation.y


func _build_vehicle_mesh() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.76, 1.05, 2.2) if is_moto else Vector3(1.95, 1.45, 4.4)
	col.shape = box
	col.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	add_child(col)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	var body_mat := StandardMaterial3D.new()
	if is_moto:
		body_mat.albedo_color = Color(0.80, 0.32, 0.10) if moto_style == "trail" else Color(0.14, 0.18, 0.28)
	else:
		body_mat.albedo_color = Color(0.24, 0.34, 0.44)
	body_mat.metallic = 0.35
	body_mat.roughness = 0.45

	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.08, 0.08, 0.09)
	tire_mat.roughness = 0.9

	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.12, 0.11, 0.10)

	if is_moto:
		# Duas rodas alinhadas EXATAMENTE com y=0 (raio 0.34 -> centro y=0.34)
		for wz in [-0.74, 0.74]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.34
			wm.bottom_radius = 0.34
			wm.height = 0.16
			wheel.mesh = wm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(0.0, 0.34, wz)
			wheel.material_override = tire_mat
			_visual_root.add_child(wheel)

		# Quadro + Tanque + Banco duplo (Piloto + Garupa)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.36, 0.44, 1.55)
		frame.mesh = fm
		frame.position = Vector3(0.0, 0.58, 0.0)
		frame.material_override = body_mat
		_visual_root.add_child(frame)

		var saddle := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.34, 0.12, 1.05)
		saddle.mesh = sm
		saddle.position = Vector3(0.0, 0.84, 0.25)
		saddle.material_override = seat_mat
		_visual_root.add_child(saddle)

		var handlebar := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.76, 0.06, 0.06)
		handlebar.mesh = hm
		handlebar.position = Vector3(0.0, 1.04, -0.58)
		handlebar.material_override = tire_mat
		_visual_root.add_child(handlebar)

		# Assentos Piloto (0) e Garupa (1) elevados sobre o banco (nunca dentro da moto!)
		var s_pilot := Node3D.new()
		s_pilot.position = Vector3(0.0, 0.64, 0.02)
		_visual_root.add_child(s_pilot)
		var s_garupa := Node3D.new()
		s_garupa.position = Vector3(0.0, 0.72, 0.58)
		_visual_root.add_child(s_garupa)
		_seat_nodes = [s_pilot, s_garupa]

		_add_headlight(Vector3(0.0, 0.86, -0.95))
	else:
		# 4 rodas alinhadas a y=0 (raio 0.36 -> centro y=0.36)
		for wx in [-0.90, 0.90]:
			for wz in [-1.35, 1.35]:
				var wheel := MeshInstance3D.new()
				var wm := CylinderMesh.new()
				wm.top_radius = 0.36
				wm.bottom_radius = 0.36
				wm.height = 0.24
				wheel.mesh = wm
				wheel.rotation.z = PI * 0.5
				wheel.position = Vector3(wx, 0.36, wz)
				wheel.material_override = tire_mat
				_visual_root.add_child(wheel)

		var chassis := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(1.92, 0.68, 4.35)
		chassis.mesh = cm
		chassis.position = Vector3(0.0, 0.68, 0.0)
		chassis.material_override = body_mat
		_visual_root.add_child(chassis)

		var cabin := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(1.68, 0.62, 2.15)
		cabin.mesh = cbm
		cabin.position = Vector3(0.0, 1.28, 0.15)
		cabin.material_override = seat_mat
		_visual_root.add_child(cabin)

		var offsets: Array[Vector3] = [
			Vector3(-0.46, 0.42, -0.25),
			Vector3(0.46, 0.42, -0.25),
			Vector3(-0.46, 0.42, 0.68),
			Vector3(0.46, 0.42, 0.68)
		]
		for off in offsets:
			var sn := Node3D.new()
			sn.position = off
			_visual_root.add_child(sn)
			_seat_nodes.append(sn)

		_add_headlight(Vector3(-0.68, 0.72, -2.22))
		_add_headlight(Vector3(0.68, 0.72, -2.22))


func _add_headlight(pos: Vector3) -> void:
	var hl := SpotLight3D.new()
	hl.position = pos
	hl.spot_range = 48.0
	hl.spot_angle = 42.0
	hl.light_energy = 7.5
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

		# Frenagem limpa ate 0 km/h (zero deslize infinito!)
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

	_update_visual_lean(delta)
	_update_engine_audio(delta)


func _update_visual_lean(delta: float) -> void:
	if _visual_root == null:
		return
	if is_moto:
		# Moto inclina para dentro da curva!
		var lean_rad: float = clampf(steer_smooth * clampf(absf(speed_mps) / 14.0, 0.0, 1.0) * 0.44, -0.46, 0.46)
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, lean_rad, minf(1.0, delta * 10.0))
	else:
		var roll_rad: float = clampf(-steer_smooth * clampf(absf(speed_mps) / 22.0, 0.0, 1.0) * 0.09, -0.12, 0.12)
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, roll_rad, minf(1.0, delta * 10.0))


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
	var side: float = -1.6 if (cur % 2 == 0) else 1.6
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
