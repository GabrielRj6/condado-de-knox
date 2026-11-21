extends Node3D
class_name MainWorld

## Cena principal Knox Survival 3D (Godot 4 Forward+ Vulkan GPU + CPU multi-core + Radmin VPN).
## - Conexao Radmin VPN (Host, Cliente, Solo Teste, Servidor Dedicado --dedicated)
## - Nome do sobrevivente, Time, IP e Draw Distance salvos automaticamente
## - Busca de cidades reais pelo nome (OpenStreetMap Nominatim + Overpass) sincronizada para todos
## - Arsenal 6 armas, Hitmarker, Carros/Motos (Piloto+Garupa), Zumbis no Servidor, Audio 3D e Mapa [M]

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
var _geocode_http: HTTPRequest

var local_nick: String = "Sobrevivente"
var local_team: String = ""
var target_ip: String = "127.0.0.1"
var server_port: int = 7777
var draw_distance: float = 550.0
var is_dedicated: bool = false
var time_hours: float = 11.5
var storm_mode: bool = false
var active_city_lat: float = -23.5614
var active_city_lng: float = -46.6559
var active_city_km2: float = 1.0
var has_custom_city: bool = false

var _menu_open: bool = true
var _hud_layer: CanvasLayer
var _menu_panel: PanelContainer
var _status_lbl: Label
var _hud_info_lbl: Label
var _weapon_lbl: Label
var _hitmarker: ColorRect
var _hitmarker_t: float = 0.0
var _nick_inp: LineEdit
var _team_inp: LineEdit
var _ip_inp: LineEdit
var _city_inp: LineEdit
var _draw_dist_lbl: Label

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

	_geocode_http = HTTPRequest.new()
	_geocode_http.timeout = 12.0
	add_child(_geocode_http)
	_geocode_http.request_completed.connect(_on_geocode_completed)

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
		draw_distance = clampf(float(cfg.get_value("profile", "draw_dist", 550.0)), 150.0, 1000.0)


func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "nick", local_nick)
	cfg.set_value("profile", "team", local_team)
	cfg.set_value("profile", "ip", target_ip)
	cfg.set_value("profile", "draw_dist", draw_distance)
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
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = draw_distance * 0.45
	env.fog_depth_end = draw_distance * 0.96
	_world_env.environment = env
	add_child(_world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1400.0, 1.0, 1400.0)
	col.shape = shape
	col.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(col)

	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
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

	# Mira central
	var cross := ColorRect.new()
	cross.color = Color(1.0, 1.0, 1.0, 0.88)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -2
	cross.offset_top = -2
	cross.offset_right = 2
	cross.offset_bottom = 2
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(cross)

	# Hitmarker central (pisca vermelho em headshot/kill, branco no corpo)
	_hitmarker = ColorRect.new()
	_hitmarker.color = Color(1.0, 0.25, 0.20, 0.95)
	_hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker.offset_left = -8
	_hitmarker.offset_top = -8
	_hitmarker.offset_right = 8
	_hitmarker.offset_bottom = 8
	_hitmarker.visible = false
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_hitmarker)

	# HUD inferior esquerdo (vida, veiculo e controles)
	_hud_info_lbl = Label.new()
	_hud_info_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud_info_lbl.offset_left = 18
	_hud_info_lbl.offset_top = -42
	_hud_info_lbl.offset_right = 920
	_hud_info_lbl.offset_bottom = -10
	_hud_info_lbl.text = "[TAB] Menu Radmin · [M] Mapa Tatico · [E] Carro/Moto · [G] Garupa · [1..6] Armas"
	_hud_layer.add_child(_hud_info_lbl)

	# HUD inferior direito (Arma ativa + Municao + Silenciador)
	_weapon_lbl = Label.new()
	_weapon_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_lbl.offset_left = -400
	_weapon_lbl.offset_top = -46
	_weapon_lbl.offset_right = -18
	_weapon_lbl.offset_bottom = -10
	_weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_lbl.text = "RIFLE M4A1 [30/30] · [R] Recarregar · [X] Silenciador"
	_hud_layer.add_child(_weapon_lbl)

	# Mapa Tatico Completo [M]
	tactical_map = TacticalMapOverlay.new()
	tactical_map.world = self
	_hud_layer.add_child(tactical_map)

	# Menu Radmin / Multiplayer [TAB]
	_menu_panel = PanelContainer.new()
	_menu_panel.position = Vector2(18, 18)
	_menu_panel.custom_minimum_size = Vector2(420, 620)
	_hud_layer.add_child(_menu_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(408, 608)
	_menu_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	vbox.add_child(_mk_lbl("KNOX SURVIVAL 3D — GODOT 4 (GPU VULKAN + RADMIN VPN)"))

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

	var conn_row := HBoxContainer.new()
	vbox.add_child(conn_row)
	var btn_host := Button.new()
	btn_host.text = "CRIAR HOST (UDP 7777)"
	btn_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_host.pressed.connect(start_host_game)
	conn_row.add_child(btn_host)

	var btn_join := Button.new()
	btn_join.text = "ENTRAR (RADMIN IP)"
	btn_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_join.pressed.connect(func() -> void: start_client_game(_ip_inp.text))
	conn_row.add_child(btn_join)

	var btn_resume := Button.new()
	btn_resume.text = "VOLTAR A PARTIDA [TAB]"
	btn_resume.pressed.connect(func() -> void:
		if get_local_player() == null:
			start_host_game()
		else:
			toggle_menu(false)
	)
	vbox.add_child(btn_resume)

	# Distancia de Visao (GPU Frustum Culling global ja oculta tudo atras da camera!)
	_draw_dist_lbl = _mk_lbl("Distancia de Visao (frente): %dm" % int(draw_distance))
	vbox.add_child(_draw_dist_lbl)
	var dd_slider := HSlider.new()
	dd_slider.min_value = 150.0
	dd_slider.max_value = 1000.0
	dd_slider.step = 25.0
	dd_slider.value = draw_distance
	dd_slider.value_changed.connect(func(val: float) -> void:
		_apply_draw_distance(val)
	)
	vbox.add_child(dd_slider)

	# Horario do dia sincronizado para todos
	vbox.add_child(_mk_lbl("Horario Global (sincronizado para TODOS):"))
	var h_row := HBoxContainer.new()
	vbox.add_child(h_row)
	for pair in [["Dia 11h", 11.5], ["Tarde 17h", 17.5], ["Noite 22h", 22.5]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k: int = sp_item[1]
		b.pressed.connect(func() -> void: request_spawn_vehicle(k))
		s_row.add_child(b)

	var btn_z := Button.new()
	btn_z.text = "+ SPAWNAR 10 ZUMBIS (SINCRONIZADO P/ TODOS)"
	btn_z.pressed.connect(func() -> void: request_spawn_zombies(10))
	vbox.add_child(btn_z)

	# Busca de cidade real pelo nome (OpenStreetMap)
	vbox.add_child(_mk_lbl("Buscar Cidade / Bairro Real (OpenStreetMap):"))
	var city_row := HBoxContainer.new()
	vbox.add_child(city_row)
	_city_inp = LineEdit.new()
	_city_inp.placeholder_text = "Ex: Avenida Paulista, Sao Paulo"
	_city_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_search := Button.new()
	btn_search.text = "BUSCAR"
	btn_search.pressed.connect(_search_real_city_by_name)
	city_row.add_child(_city_inp)
	city_row.add_child(btn_search)

	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	for cp in [["Paulista SP", -23.5614, -46.6559], ["Copacabana RJ", -22.9711, -43.1822], ["Curitiba", -25.4284, -49.2733]]:
		var b := Button.new()
		b.text = cp[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var plat: float = cp[1]
		var plng: float = cp[2]
		b.pressed.connect(func() -> void: request_load_real_city(plat, plng, 1.0))
		preset_row.add_child(b)

	var btn_disc := Button.new()
	btn_disc.text = "SAIR / ENCERRAR CONEXAO"
	btn_disc.pressed.connect(disconnect_network)
	vbox.add_child(btn_disc)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.text = "Pronto! Clique em CRIAR HOST (ou ENTRAR com IP do Radmin VPN)."
	vbox.add_child(_status_lbl)


func _mk_lbl(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	return l


func _set_status(msg: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg
	print("[Knox] ", msg)


func _apply_draw_distance(meters: float) -> void:
	draw_distance = clampf(meters, 150.0, 1000.0)
	_save_profile()
	if _draw_dist_lbl != null:
		_draw_dist_lbl.text = "Distancia de Visao (frente): %dm" % int(draw_distance)
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.fog_depth_begin = draw_distance * 0.45
		_world_env.environment.fog_depth_end = draw_distance * 0.96
	var lp := get_local_player()
	if lp != null:
		lp.set_draw_distance(draw_distance)


func _search_real_city_by_name() -> void:
	var q: String = _city_inp.text.strip_edges() if _city_inp != null else ""
	if q.length() < 2:
		_set_status("Digite o nome de uma cidade ou rua para buscar.")
		return
	_set_status("Buscando '%s' no OpenStreetMap..." % q)
	var url: String = "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" + q.uri_encode()
	var headers := PackedStringArray(["User-Agent: KnoxSurvival3D-Godot/1.0"])
	_geocode_http.request(url, headers)


func _on_geocode_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_status("Erro ao buscar local — tente um dos botoes rapidos acima.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).is_empty():
		_set_status("Local nao encontrado — tente incluir cidade e estado.")
		return
	var item: Dictionary = (parsed as Array)[0]
	var lat: float = float(str(item.get("lat", "-23.5614")))
	var lng: float = float(str(item.get("lon", "-46.6559")))
	_set_status("Encontrado: %s" % str(item.get("display_name", "")).left(52))
	request_load_real_city(lat, lng, 1.0)


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


func _process(delta: float) -> void:
	if is_dedicated:
		return
	if _hitmarker_t > 0.0:
		_hitmarker_t -= delta
		if _hitmarker_t <= 0.0 and _hitmarker != null:
			_hitmarker.visible = false

	var lp := get_local_player()
	if lp != null:
		if _hud_info_lbl != null:
			if lp.current_vehicle != null:
				var kmh: int = int(roundf(absf(lp.current_vehicle.speed_mps) * 3.6))
				var seat_name: String = "PILOTO" if (lp.current_vehicle.is_moto and lp.current_seat == 0) else ("GARUPA" if lp.current_vehicle.is_moto else ("MOTORISTA" if lp.current_seat == 0 else "PASSAGEIRO"))
				_hud_info_lbl.text = "HP: %d/200  |  %s (%s) — %d km/h  |  [E] Sair · [G] Trocar Assento · [H] Buzina · [F] Farol · [M] Mapa GPS" % [lp.hp, lp.current_vehicle.label, seat_name, kmh]
			else:
				_hud_info_lbl.text = "HP: %d/200  |  Time: %s  |  [TAB] Menu Radmin · [M] Mapa · [E] Carro/Moto · [V] 1P/3P · [F] Lanterna" % [lp.hp, local_team if not local_team.is_empty() else "SOLO"]

		if _weapon_lbl != null:
			var w: Dictionary = lp.get_active_weapon_def()
			var sup_tag: String = " [SILENCIADOR]" if (lp.suppressed and not bool(w["melee"])) else ""
			if bool(w["melee"]):
				_weapon_lbl.text = "[%d] %s" % [lp.active_weapon_idx + 1, str(w["name"])]
			elif lp.reloading:
				_weapon_lbl.text = "[%d] %s — RECARREGANDO..." % [lp.active_weapon_idx + 1, str(w["name"])]
			else:
				_weapon_lbl.text = "[%d] %s%s  %d/%d  |  [R] Recarregar · [X] Silenc." % [lp.active_weapon_idx + 1, str(w["name"]), sup_tag, lp.get_active_mag(), int(w["mag_size"])]


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
	_server_spawn_vehicle(Vector3(6.5, 0.2, -6.0), 0.0, 0)
	_server_spawn_vehicle(Vector3(-5.0, 0.2, -6.0), 0.4, 1)
	_server_spawn_vehicle(Vector3(-8.5, 0.2, -6.0), -0.3, 2)
	_server_spawn_zombies(Vector3(0.0, 0.0, -32.0), 10)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[KnoxServer] Jogador conectado: peer ", id)
	_rpc_apply_time.rpc_id(id, time_hours, storm_mode)
	if has_custom_city:
		_rpc_load_real_city.rpc_id(id, active_city_lat, active_city_lng, active_city_km2)
	for p in get_all_players():
		_rpc_spawn_player.rpc_id(id, p.peer_id, p.global_position, p.nick, p.team_id)
	for v in get_all_vehicles():
		var kind: int = 2 if v.moto_style == "street" else (1 if v.is_moto else 0)
		_rpc_spawn_vehicle.rpc_id(id, v.vehicle_id, v.global_position, v.rotation.y, kind)
	for z in get_all_zombies():
		if not z.is_dead:
			_rpc_spawn_zombie.rpc_id(id, z.zombie_id, z.global_position, z.vocal_pitch)

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
	if is_me:
		p.set_draw_distance(draw_distance)
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
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.fog_light_color = Color(0.05, 0.07, 0.12) if is_night else Color(0.64, 0.74, 0.84)
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
	active_city_lat = lat
	active_city_lng = lng
	active_city_km2 = km2
	has_custom_city = true
	_set_status("Baixando cidade real OSM (%.4f, %.4f)..." % [lat, lng])
	map_loader.load_real_city(lat, lng, km2)


func request_fire_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String, dmg: float = 36.0, rng_m: float = 220.0, noise_r: float = 115.0, play_audio: bool = true) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_process_shot(shooter_pid, muzzle_pos, dir, profile, dmg, rng_m, noise_r, play_audio)
	else:
		_rpc_req_shot.rpc_id(1, shooter_pid, muzzle_pos, dir, profile, dmg, rng_m, noise_r, play_audio)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String, dmg: float, rng_m: float, noise_r: float, play_audio: bool) -> void:
	if multiplayer.is_server():
		_server_process_shot(shooter_pid, muzzle_pos, dir, profile, dmg, rng_m, noise_r, play_audio)


func _server_process_shot(shooter_pid: int, muzzle_pos: Vector3, dir: Vector3, profile: String, dmg: float, rng_m: float, noise_r: float, play_audio: bool) -> void:
	var n_dir: Vector3 = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	var end_pos: Vector3 = muzzle_pos + n_dir * clampf(rng_m, 2.0, 520.0)
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, end_pos)
	var shooter := get_player_by_peer(shooter_pid)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_confirm: int = 0 # 0=miss, 1=body, 2=head/kill
	if not hit.is_empty():
		end_pos = hit["position"]
		var col: Object = hit["collider"]
		if col is Zombie3D:
			var z := col as Zombie3D
			var is_head: bool = end_pos.y > z.global_position.y + 1.40
			var killed: bool = z.apply_server_damage(dmg * (3.2 if is_head else 1.0))
			hit_confirm = 2 if (is_head or killed) else 1
		elif col is SurvivorPlayer:
			var tgt := col as SurvivorPlayer
			var same_team: bool = shooter != null and TacticalMapOverlay.should_show_player_on_map(shooter.team_id, tgt.team_id)
			if not same_team:
				tgt.apply_damage(int(dmg))
				hit_confirm = 1

	if play_audio:
		var eff_noise: float = noise_r * (0.24 if profile == "suppressed" else 1.0)
		alert_zombies_in_radius(muzzle_pos, eff_noise)
	_rpc_play_shot.rpc(shooter_pid, profile, muzzle_pos, end_pos, play_audio)
	if hit_confirm > 0:
		if multiplayer.has_multiplayer_peer() and shooter_pid != 1:
			_rpc_show_hitmarker.rpc_id(shooter_pid, hit_confirm == 2)
		else:
			_show_hitmarker(hit_confirm == 2)


@rpc("authority", "call_local", "reliable")
func _rpc_show_hitmarker(is_crit: bool) -> void:
	_show_hitmarker(is_crit)


func _show_hitmarker(is_crit: bool) -> void:
	if _hitmarker == null:
		return
	_hitmarker.color = Color(1.0, 0.22, 0.18, 0.95) if is_crit else Color(1.0, 1.0, 1.0, 0.92)
	_hitmarker.visible = true
	_hitmarker_t = 0.14


@rpc("authority", "call_local", "unreliable")
func _rpc_play_shot(shooter_pid: int, profile: String, muzzle_pos: Vector3, end_pos: Vector3, play_audio: bool) -> void:
	var is_local: bool = (not multiplayer.has_multiplayer_peer()) or (shooter_pid == multiplayer.get_unique_id())
	if play_audio and audio_3d != null:
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
