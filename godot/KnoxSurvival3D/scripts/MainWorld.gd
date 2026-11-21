extends Node3D
class_name MainWorld

## Cena principal Knox Survival 3D (Godot 4 + ENet UDP Radmin VPN + Servidor Dedicado).
## Gerencia conexoes Radmin VPN (Host/Cliente/Dedicado), nome salvo do sobrevivente,
## sincronizacao de horario do dia, spawn global de Carros, Motos e Zumbis, tiros 3D e HUD.

const PROFILE_PATH: String = "user://knox_profile.cfg"

var audio_3d: SpatialAudio3D
var map_loader: RealWorldMapLoader
var tactical_map: TacticalMapOverlay

var players_root: Node3D
var vehicles_root: Node3D
var zombies_root: Node3D

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _sky_mat: ProceduralSkyMaterial

var local_nick: String = "Sobrevivente"
var local_team: String = ""
var target_ip: String = "127.0.0.1"
var server_port: int = 7777
var is_dedicated: bool = false
var time_hours: float = 11.5
var storm_mode: bool = false

var _menu_open: bool = true
var _hud_layer: CanvasLayer
var _menu_panel: PanelContainer
var _status_lbl: Label
var _hud_info_lbl: Label
var _nick_inp: LineEdit
var _team_inp: LineEdit
var _ip_inp: LineEdit
var _lat_inp: LineEdit
var _lng_inp: LineEdit

var _veh_seq: int = 0
var _z_seq: int = 0


func _ready() -> void:
	_load_profile()
	_parse_cli_args()
	_build_environment_and_ground()

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	vehicles_root = Node3D.new()
	vehicles_root.name = "Vehicles"
	add_child(vehicles_root)

	zombies_root = Node3D.new()
	zombies_root.name = "Zombies"
	add_child(zombies_root)

	audio_3d = SpatialAudio3D.new()
	audio_3d.name = "SpatialAudio3D"
	add_child(audio_3d)

	map_loader = RealWorldMapLoader.new()
	map_loader.name = "RealWorldMapLoader"
	add_child(map_loader)
	map_loader.map_loaded.connect(func(msg: String) -> void: _set_status(msg))

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if is_dedicated:
		_menu_open = false
		start_dedicated_server()
	else:
		_build_ui()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_apply_time_of_day()


func _parse_cli_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--dedicated":
			is_dedicated = true
		elif args[i] == "--port" and i + 1 < args.size():
			server_port = int(args[i + 1])


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		local_nick = str(cfg.get_value("profile", "nick", "Sobrevivente"))
		local_team = str(cfg.get_value("profile", "team", ""))
		target_ip = str(cfg.get_value("profile", "ip", "127.0.0.1"))


func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "nick", local_nick)
	cfg.set_value("profile", "team", local_team)
	cfg.set_value("profile", "ip", target_ip)
	cfg.save(PROFILE_PATH)


func _build_environment_and_ground() -> void:
	_world_env = WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world_env.environment = env
	add_child(_world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)

	# Terreno base 1000x1000m com colisao StaticBody3D
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 1.0, 1000.0)
	col.shape = shape
	col.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(col)

	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1000.0, 1000.0)
	mesh.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.18, 0.24, 0.16)
	gmat.roughness = 0.95
	mesh.material_override = gmat
	ground.add_child(mesh)
	add_child(ground)


func _build_ui() -> void:
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)

	# Mira central discreta
	var cross := ColorRect.new()
	cross.color = Color(1.0, 1.0, 1.0, 0.85)
	cross.custom_minimum_size = Vector2(4, 4)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -2
	cross.offset_top = -2
	cross.offset_right = 2
	cross.offset_bottom = 2
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(cross)

	# Barra de HUD inferior
	_hud_info_lbl = Label.new()
	_hud_info_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud_info_lbl.offset_left = 18
	_hud_info_lbl.offset_top = -38
	_hud_info_lbl.offset_right = 920
	_hud_info_lbl.offset_bottom = -10
	_hud_info_lbl.text = "[TAB] Menu Radmin · [M] Mapa Tatico · [E] Entrar/Sair Veiculo · [G] Trocar Banco/Garupa · [H] Buzina · [V] 1P/3P"
	_hud_layer.add_child(_hud_info_lbl)

	# Mapa Tatico Completo [M]
	tactical_map = TacticalMapOverlay.new()
	tactical_map.world = self
	_hud_layer.add_child(tactical_map)

	# Menu Radmin / Multiplayer [TAB]
	_menu_panel = PanelContainer.new()
	_menu_panel.position = Vector2(20, 20)
	_menu_panel.custom_minimum_size = Vector2(390, 520)
	_hud_layer.add_child(_menu_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "KNOX SURVIVAL 3D — GODOT 4 (RADMIN VPN)"
	vbox.add_child(title)

	vbox.add_child(_mk_lbl("Nome do Sobrevivente (salvo automaticamente):"))
	_nick_inp = LineEdit.new()
	_nick_inp.text = local_nick
	_nick_inp.text_changed.connect(func(v: String) -> void:
		local_nick = v.strip_edges().left(18) if not v.strip_edges().is_empty() else "Sobrevivente"
		_save_profile()
		var lp := get_local_player()
		if lp != null:
			lp.nick = local_nick
	)
	vbox.add_child(_nick_inp)

	vbox.add_child(_mk_lbl("Codigo do Time / Party (so aliados do mesmo time aparecem no Mapa [M]):"))
	_team_inp = LineEdit.new()
	_team_inp.text = local_team
	_team_inp.placeholder_text = "Ex: ALFA (vazio = lobo solitario)"
	_team_inp.text_changed.connect(func(v: String) -> void:
		local_team = v.strip_edges().to_upper().left(12)
		_save_profile()
		var lp := get_local_player()
		if lp != null:
			lp.team_id = local_team
	)
	vbox.add_child(_team_inp)

	vbox.add_child(_mk_lbl("IP do Host no Radmin VPN (ex: 26.x.x.x ou 127.0.0.1):"))
	_ip_inp = LineEdit.new()
	_ip_inp.text = target_ip
	vbox.add_child(_ip_inp)

	var btn_host := Button.new()
	btn_host.text = "CRIAR SERVIDOR (HOST UDP 7777)"
	btn_host.pressed.connect(start_host_game)
	vbox.add_child(btn_host)

	var btn_join := Button.new()
	btn_join.text = "ENTRAR NO SERVIDOR (RADMIN IP)"
	btn_join.pressed.connect(func() -> void: start_client_game(_ip_inp.text))
	vbox.add_child(btn_join)

	var btn_resume := Button.new()
	btn_resume.text = "VOLTAR A PARTIDA [TAB]"
	btn_resume.pressed.connect(func() -> void: toggle_menu(false))
	vbox.add_child(btn_resume)

	# Horario do dia sincronizado para todos
	vbox.add_child(_mk_lbl("Horario Global (sincronizado para TODOS):"))
	var h_row := HBoxContainer.new()
	vbox.add_child(h_row)
	for pair in [["Dia 11h", 11.5], ["Tarde 17h", 17.5], ["Noite 22h", 22.5]]:
		var b := Button.new()
		b.text = pair[0]
		var target_h: float = pair[1]
		b.pressed.connect(func() -> void: request_set_time(target_h, storm_mode))
		h_row.add_child(b)

	# Spawns globais (Carros, Motos e Zumbis)
	vbox.add_child(_mk_lbl("Spawnar para TODOS na sala:"))
	var s_row := HBoxContainer.new()
	vbox.add_child(s_row)
	for sp_item in [["+ Carro", 0], ["+ Moto Trail", 1], ["+ Moto Street", 2]]:
		var b := Button.new()
		b.text = sp_item[0]
		var k: int = sp_item[1]
		b.pressed.connect(func() -> void: request_spawn_vehicle(k))
		s_row.add_child(b)

	var btn_z := Button.new()
	btn_z.text = "+ SPAWNAR 10 ZUMBIS (SINCRONIZADO P/ TODOS)"
	btn_z.pressed.connect(func() -> void: request_spawn_zombies(10))
	vbox.add_child(btn_z)

	# Carregar cidade real via OpenStreetMap
	vbox.add_child(_mk_lbl("Cidade Real OpenStreetMap (Lat / Lng):"))
	var geo_row := HBoxContainer.new()
	vbox.add_child(geo_row)
	_lat_inp = LineEdit.new()
	_lat_inp.text = "-23.5614"
	_lat_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lng_inp = LineEdit.new()
	_lng_inp.text = "-46.6559"
	_lng_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_osm := Button.new()
	btn_osm.text = "CARREGAR MAPA"
	btn_osm.pressed.connect(func() -> void:
		request_load_real_city(_lat_inp.text.to_float(), _lng_inp.text.to_float(), 1.0)
	)
	geo_row.add_child(_lat_inp)
	geo_row.add_child(_lng_inp)
	geo_row.add_child(btn_osm)

	var btn_disc := Button.new()
	btn_disc.text = "SAIR / ENCERRAR CONEXAO"
	btn_disc.pressed.connect(disconnect_network)
	vbox.add_child(btn_disc)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.text = "Pronto! Clique em CRIAR SERVIDOR (Host) ou digite o IP Radmin do amigo."
	vbox.add_child(_status_lbl)


func _mk_lbl(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	return l


func _set_status(msg: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg
	print("[Knox] ", msg)


func is_ui_blocking() -> bool:
	return _menu_open or (tactical_map != null and tactical_map.visible)


func toggle_menu(open_state: bool) -> void:
	_menu_open = open_state
	if _menu_panel != null:
		_menu_panel.visible = open_state
	if open_state and tactical_map != null:
		tactical_map.close_map()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_ui_blocking() else Input.MOUSE_MODE_CAPTURED


func toggle_full_map(open_state: bool) -> void:
	if tactical_map == null:
		return
	if open_state:
		_menu_open = false
		if _menu_panel != null:
			_menu_panel.visible = false
		tactical_map.open_map()
	else:
		tactical_map.close_map()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_ui_blocking() else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_dedicated:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_TAB or kc == KEY_ESCAPE:
			toggle_menu(not _menu_open)
		elif kc == KEY_M:
			toggle_full_map(tactical_map != null and not tactical_map.visible)


func _process(_delta: float) -> void:
	if is_dedicated or _hud_info_lbl == null:
		return
	var lp := get_local_player()
	if lp != null:
		if lp.current_vehicle != null:
			var kmh: int = int(roundf(absf(lp.current_vehicle.speed_mps) * 3.6))
			var seat_name: String = "PILOTO" if (lp.current_vehicle.is_moto and lp.current_seat == 0) else ("GARUPA" if lp.current_vehicle.is_moto else ("MOTORISTA" if lp.current_seat == 0 else "PASSAGEIRO"))
			_hud_info_lbl.text = "HP: %d/200  |  %s (%s) — %d km/h  |  [E] Sair · [G] Trocar Assento · [H] Buzina · [F] Farol · [M] Mapa GPS" % [lp.hp, lp.current_vehicle.label, seat_name, kmh]
		else:
			_hud_info_lbl.text = "HP: %d/200  |  Time: %s  |  [TAB] Menu Radmin · [M] Mapa · [E] Entrar Carro/Moto · [V] 1P/3P · [F] Lanterna" % [lp.hp, local_team if not local_team.is_empty() else "SOLO"]


# ==============================================================================
# REDE ENet UDP (RADMIN VPN + SERVIDOR DEDICADO)
# ==============================================================================
func start_dedicated_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(server_port, 32)
	if err != OK:
		push_error("Falha ao abrir Servidor Dedicado na porta %d (erro %d)" % [server_port, err])
		return
	multiplayer.multiplayer_peer = peer
	_spawn_starter_world_entities()
	print("[KnoxDedicated] Servidor Dedicado ativo na porta UDP %d (Radmin VPN pronto!)" % server_port)


func start_host_game() -> void:
	disconnect_network()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(server_port, 32)
	if err != OK:
		_set_status("Erro ao abrir porta UDP %d (ja em uso?)" % server_port)
		return
	multiplayer.multiplayer_peer = peer
	_spawn_player_local(1, Vector3(0.0, 0.5, 0.0), local_nick, local_team)
	_spawn_starter_world_entities()
	_set_status("HOST ATIVO (UDP %d) — Passe seu IP Radmin (26.x.x.x) aos amigos!" % server_port)
	toggle_menu(false)


func start_client_game(ip: String) -> void:
	disconnect_network()
	target_ip = ip.strip_edges() if not ip.strip_edges().is_empty() else "127.0.0.1"
	_save_profile()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(target_ip, server_port)
	if err != OK:
		_set_status("Erro ao conectar em %s:%d" % [target_ip, server_port])
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Conectando ao Radmin %s:%d..." % [target_ip, server_port])


func disconnect_network() -> void:
	if multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for child in players_root.get_children():
		child.queue_free()
	for child in vehicles_root.get_children():
		child.queue_free()
	for child in zombies_root.get_children():
		child.queue_free()
	_set_status("Desconectado.")


func _spawn_starter_world_entities() -> void:
	# Ja inicia com 1 Carro, 1 Moto Trail 450, 1 Moto Street 600 e 8 Zumbis sincronizados!
	_server_spawn_vehicle(Vector3(6.5, 0.2, -6.0), 0.0, 0)
	_server_spawn_vehicle(Vector3(-5.0, 0.2, -6.0), 0.4, 1)
	_server_spawn_vehicle(Vector3(-8.5, 0.2, -6.0), -0.3, 2)
	_server_spawn_zombies(Vector3(0.0, 0.0, -32.0), 8)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[KnoxServer] Jogador conectado: peer ", id)
	# Envia todo o estado atual da sala (jogadores, veiculos, zumbis, hora) para o recem-chegado!
	_rpc_apply_time.rpc_id(id, time_hours, storm_mode)
	for p in get_all_players():
		_rpc_spawn_player.rpc_id(id, p.peer_id, p.global_position, p.nick, p.team_id)
	for v in get_all_vehicles():
		var kind: int = 2 if v.moto_style == "street" else (1 if v.is_moto else 0)
		_rpc_spawn_vehicle.rpc_id(id, v.vehicle_id, v.global_position, v.rotation.y, kind)
	for z in get_all_zombies():
		if not z.is_dead:
			_rpc_spawn_zombie.rpc_id(id, z.zombie_id, z.global_position, z.vocal_pitch)

	# Cria o novo jogador para TODOS os clientes (inclusive ele mesmo!)
	var spawn_pos := Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
	_rpc_spawn_player.rpc(id, spawn_pos, "Sobrevivente", "")


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_rpc_remove_player.rpc(id)


func _on_connected_to_server() -> void:
	_set_status("Conectado ao servidor Radmin %s:%d!" % [target_ip, server_port])
	toggle_menu(false)


func _on_connection_failed() -> void:
	_set_status("Falha ao conectar em %s:%d — confira Radmin VPN e porta UDP 7777." % [target_ip, server_port])
	toggle_menu(true)


func _on_server_disconnected() -> void:
	_set_status("Servidor encerrado ou conexao perdida.")
	toggle_menu(true)


# ==============================================================================
# ENTIDADES, COMBATE 3D E RPCs GLOBAIS
# ==============================================================================
func _spawn_player_local(pid: int, pos: Vector3, p_nick: String, p_team: String) -> SurvivorPlayer:
	var existing := get_player_by_peer(pid)
	if existing != null:
		return existing
	var p := SurvivorPlayer.new()
	var is_me: bool = multiplayer.has_multiplayer_peer() and pid == multiplayer.get_unique_id()
	p.setup(pid, self, local_nick if is_me else p_nick, local_team if is_me else p_team)
	players_root.add_child(p)
	p.global_position = pos
	return p


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(pid: int, pos: Vector3, p_nick: String, p_team: String) -> void:
	_spawn_player_local(pid, pos, p_nick, p_team)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_player(pid: int) -> void:
	var p := get_player_by_peer(pid)
	if p != null:
		if p.current_vehicle != null:
			p.current_vehicle.request_exit(pid)
		p.queue_free()


func request_set_time(h: float, storm: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_rpc_apply_time.rpc(h, storm)
	else:
		_rpc_req_time.rpc_id(1, h, storm)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_time(h: float, storm: bool) -> void:
	if multiplayer.is_server():
		_rpc_apply_time.rpc(h, storm)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_time(h: float, storm: bool) -> void:
	time_hours = fposmod(h, 24.0)
	storm_mode = storm
	_apply_time_of_day()


func _apply_time_of_day() -> void:
	if _sun == null:
		return
	var elev: float = sin(((time_hours - 6.0) / 24.0) * TAU)
	var pitch_deg: float = lerpf(-22.0, -72.0, inverse_lerp(-1.0, 1.0, elev))
	_sun.rotation_degrees = Vector3(pitch_deg, (time_hours / 24.0) * 360.0 - 90.0, 0.0)
	var is_night: bool = elev < 0.05
	_sun.light_energy = 0.14 if is_night else lerpf(0.45, 1.35, clampf(elev, 0.0, 1.0))
	_sun.light_color = Color(0.56, 0.70, 0.96) if is_night else Color(1.0, 0.95, 0.86)
	if _sky_mat != null:
		_sky_mat.sky_top_color = Color(0.03, 0.05, 0.11) if is_night else Color(0.24, 0.48, 0.82)
		_sky_mat.sky_horizon_color = Color(0.07, 0.09, 0.16) if is_night else Color(0.66, 0.76, 0.86)
	if map_loader != null:
		map_loader.set_night_streetlights(is_night)


func request_spawn_vehicle(kind: int) -> void:
	var lp := get_local_player()
	var pos: Vector3 = Vector3(0.0, 0.3, -6.0)
	var yaw: float = 0.0
	if lp != null:
		pos = lp.global_position + (-lp.global_transform.basis.z) * 5.5 + Vector3(0.0, 0.25, 0.0)
		yaw = lp.rotation.y
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_spawn_vehicle(pos, yaw, kind)
	else:
		_rpc_req_spawn_vehicle.rpc_id(1, pos, yaw, kind)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_spawn_vehicle(pos: Vector3, yaw: float, kind: int) -> void:
	if multiplayer.is_server():
		_server_spawn_vehicle(pos, yaw, kind)


func _server_spawn_vehicle(pos: Vector3, yaw: float, kind: int) -> void:
	_veh_seq += 1
	var vid: String = "v%d" % _veh_seq
	_rpc_spawn_vehicle.rpc(vid, pos, yaw, kind)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_vehicle(vid: String, pos: Vector3, yaw: float, kind: int) -> void:
	if vehicles_root.has_node("Veh_%s" % vid):
		return
	var v := Vehicle3D.new()
	v.setup(vid, self, kind)
	vehicles_root.add_child(v)
	v.global_position = pos
	v.rotation.y = yaw


func request_spawn_zombies(count: int) -> void:
	var lp := get_local_player()
	var center: Vector3 = lp.global_position if lp != null else Vector3.ZERO
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_spawn_zombies(center, count)
	else:
		_rpc_req_spawn_zombies.rpc_id(1, center, count)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_spawn_zombies(center: Vector3, count: int) -> void:
	if multiplayer.is_server():
		_server_spawn_zombies(center, clampi(count, 1, 40))


func _server_spawn_zombies(center: Vector3, count: int) -> void:
	for i in range(count):
		_z_seq += 1
		var ang: float = (float(i) / float(maxi(1, count))) * TAU + randf_range(-0.2, 0.2)
		var rad: float = randf_range(16.0, 36.0)
		var pos := center + Vector3(cos(ang) * rad, 0.3, sin(ang) * rad)
		_rpc_spawn_zombie.rpc("z%d" % _z_seq, pos, randf_range(0.84, 1.18))


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_zombie(zid: String, pos: Vector3, pitch: float) -> void:
	if zombies_root.has_node("Z_%s" % zid):
		return
	var z := Zombie3D.new()
	z.setup(zid, self, pitch)
	zombies_root.add_child(z)
	z.global_position = pos


func request_load_real_city(lat: float, lng: float, km2: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_rpc_load_real_city.rpc(lat, lng, km2)
	else:
		_rpc_req_real_city.rpc_id(1, lat, lng, km2)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_real_city(lat: float, lng: float, km2: float) -> void:
	if multiplayer.is_server():
		_rpc_load_real_city.rpc(lat, lng, km2)


@rpc("authority", "call_local", "reliable")
func _rpc_load_real_city(lat: float, lng: float, km2: float) -> void:
	_set_status("Baixando cidade real OSM (%.4f, %.4f)..." % [lat, lng])
	map_loader.load_real_city(lat, lng, km2)


func request_fire_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_process_shot(shooter_pid, muzzle_pos, dir, profile)
	else:
		_rpc_req_shot.rpc_id(1, shooter_pid, muzzle_pos, dir, profile)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String) -> void:
	if multiplayer.is_server():
		_server_process_shot(shooter_pid, muzzle_pos, dir, profile)


func _server_process_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String) -> void:
	var n_dir: Vector3 = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	var end_pos: Vector3 = muzzle_pos + n_dir * 220.0
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, end_pos)
	var shooter := get_player_by_peer(shooter_pid)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end_pos = hit["position"]
		var col: Object = hit["collider"]
		if col is Zombie3D:
			var z := col as Zombie3D
			var is_head: bool = end_pos.y > z.global_position.y + 1.40
			z.apply_server_damage(120.0 if is_head else 38.0)
		elif col is SurvivorPlayer:
			var tgt := col as SurvivorPlayer
			var same_team: bool = shooter != null and TacticalMapOverlay.should_show_player_on_map(shooter.team_id, tgt.team_id)
			if not same_team:
				tgt.apply_damage(35)

	alert_zombies_in_radius(muzzle_pos, 26.0 if profile == "suppressed" else 115.0)
	_rpc_play_shot.rpc(shooter_pid, profile, muzzle_pos, end_pos)


@rpc("authority", "call_local", "unreliable")
func _rpc_play_shot(shooter_pid: int, profile: String, muzzle_pos: Vector3, end_pos: Vector3) -> void:
	var is_local: bool = (not multiplayer.has_multiplayer_peer()) or (shooter_pid == multiplayer.get_unique_id())
	if audio_3d != null:
		audio_3d.play_gunshot_3d(profile, muzzle_pos, end_pos, is_local)
	_spawn_tracer(muzzle_pos, end_pos)


func _spawn_tracer(from_pos: Vector3, to_pos: Vector3) -> void:
	if is_dedicated:
		return
	var diff: Vector3 = to_pos - from_pos
	var dist: float = diff.length()
	if dist < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, minf(dist, 180.0))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.88, 0.55)
	mi.material_override = mat
	var dir_n: Vector3 = diff.normalized()
	var up_ref: Vector3 = Vector3.UP if absf(dir_n.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(dir_n, up_ref), from_pos.lerp(to_pos, 0.5))
	add_child(mi)
	var t := get_tree().create_timer(0.055)
	t.timeout.connect(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
	)


# ==============================================================================
# HELPERS DE BUSCA
# ==============================================================================
func get_all_players() -> Array[SurvivorPlayer]:
	var arr: Array[SurvivorPlayer] = []
	for c in players_root.get_children():
		if c is SurvivorPlayer:
			arr.append(c)
	return arr


func get_local_player() -> SurvivorPlayer:
	if not multiplayer.has_multiplayer_peer():
		var all := get_all_players()
		return all[0] if not all.is_empty() else null
	return get_player_by_peer(multiplayer.get_unique_id())


func get_player_by_peer(pid: int) -> SurvivorPlayer:
	var n := players_root.get_node_or_null("Player_%d" % pid)
	return n as SurvivorPlayer if n is SurvivorPlayer else null


func get_all_vehicles() -> Array[Vehicle3D]:
	var arr: Array[Vehicle3D] = []
	for c in vehicles_root.get_children():
		if c is Vehicle3D:
			arr.append(c)
	return arr


func get_all_zombies() -> Array[Zombie3D]:
	var arr: Array[Zombie3D] = []
	for c in zombies_root.get_children():
		if c is Zombie3D:
			arr.append(c)
	return arr


func find_nearest_vehicle(pos: Vector3, max_d: float) -> Vehicle3D:
	var best: Vehicle3D = null
	var best_d: float = max_d
	for v in get_all_vehicles():
		var d: float = v.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = v
	return best


func alert_zombies_in_radius(origin: Vector3, radius: float) -> void:
	var r2: float = radius * radius
	for z in get_all_zombies():
		if not z.is_dead and z.global_position.distance_squared_to(origin) <= r2:
			z.alert_by_sound(14.0)
