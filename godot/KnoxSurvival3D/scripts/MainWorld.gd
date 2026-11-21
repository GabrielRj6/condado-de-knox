extends Node3D
class_name MainWorld

## Cena principal Knox Survival 3D — Godot 4 (Forward+ Vulkan GPU + Multi-Core CPU + Radmin VPN).
## - HUD completo 1:1 do Condado de Knox (Web -> Godot 4):
##   * Relogio Tatico Superior Esquerdo (Hora + Rede + Zumbis + Abates + Botao DEV [F1])
##   * Faixa Superior Central de Atalhos
##   * Painel de Status Inferior Esquerdo com Silhueta Corporal colorida por HP + Postura + Vitais
##   * Card de Arma Ativa elevado (icone grande, nome, calibre, municao, silenciador) + Hotbar [1..9]
##   * Minimapa Tatico no Canto Inferior Direito com zoom [- / +] + Mapa Completo [M]
##   * HUD de Veiculo acima do Minimapa com Diagrama Superior (Carro 4 rodas / Moto 2 rodas), KM/H e DRIFT
##   * Painel DEV [F1] completo (God Mode, Municao Infinita, Horario + 6 presets, Spawns, Curar, TP)
## - Compatibilidade automatica com plugins da Godot Asset Store (Sky3D, Terrain3D, TerraBrush, RoadGenerator)

const PROFILE_PATH: String = "user://knox_profile.cfg"

var audio_3d: SpatialAudio3D
var map_loader: RealWorldMapLoader
var tactical_map: TacticalMapOverlay
var minimap_hud: MinimapHUD

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
var _dev_open: bool = false
var _hud_layer: CanvasLayer
var _menu_backdrop: ColorRect
var _menu_panel: PanelContainer
var _dev_panel: PanelContainer
var _status_lbl: Label
var _prompt_lbl: Label

# HUD Condado de Knox — Top-Left Watch Widget
var _clock_lbl: Label
var _net_badge_lbl: Label
var _watch_sub_lbl: Label
var _addons_lbl: Label

# HUD Condado de Knox — Bottom-Left Status Panel + Silhueta Corporal
var _body_diagram: KnoxHUDDiagrams
var _posture_lbl: Label
var _hp_val_lbl: Label
var _stamina_val_lbl: Label
var _limbs_lbl: Label
var _hp_bar: ProgressBar
var _stamina_bar: ProgressBar
var _hunger_bar: ProgressBar
var _thirst_bar: ProgressBar

# HUD Condado de Knox — Bottom-Center Weapon Callout + Hotbar 9 slots
var _active_wp_icon: TextureRect
var _active_wp_name: Label
var _active_wp_cal: Label
var _active_wp_ammo: Label
var _active_wp_badge: Label
var _hotbar_slots: Array[PanelContainer] = []
var _slot_style_normal: StyleBoxFlat
var _slot_style_active: StyleBoxFlat
var _last_hotbar_idx: int = -1

# HUD Condado de Knox — Right-Side Vehicle HUD (acima do minimapa)
var _veh_panel: PanelContainer
var _veh_diagram: KnoxHUDDiagrams
var _veh_name_lbl: Label
var _veh_seat_lbl: Label
var _veh_speed_lbl: Label
var _veh_drift_lbl: Label
var _veh_lights_lbl: Label
var _veh_hp_bar: ProgressBar

# DEV Panel Controls
var _dev_god_chk: CheckButton
var _dev_ammo_chk: CheckButton
var _dev_time_slider: HSlider
var _dev_time_val_lbl: Label

# Mira / Scope / Hitmarker / Inputs
var _crosshair_root: Control
var _scope_overlay: Control
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
	# Se o usuario ja colocou um Sky3D ou WorldEnvironment customizado na cena Main.tscn, respeita!
	var existing_env := get_node_or_null("WorldEnvironment")
	var existing_sky := get_node_or_null("Sky3D")
	if existing_env == null and existing_sky == null:
		_world_env = WorldEnvironment.new()
		var env := Environment.new()
		_sky_mat = ProceduralSkyMaterial.new()
		var sky := Sky.new()
		sky.sky_material = _sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.88
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = true
		env.glow_intensity = 0.25
		env.glow_bloom = 0.08
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = draw_distance * 0.45
		env.fog_depth_end = draw_distance * 0.96
		_world_env.environment = env
		add_child(_world_env)

		_sun = DirectionalLight3D.new()
		_sun.shadow_enabled = true
		add_child(_sun)

	# Se o usuario ja adicionou Terrain3D ou TerraBrush na cena Main.tscn, nao cria o plano padrao por cima
	var has_custom_terrain: bool = (get_node_or_null("Terrain3D") != null) or (get_node_or_null("TerraBrush") != null)
	if not has_custom_terrain:
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
		mesh.material_override = ProceduralTextures.get_grass_mat()
		ground.add_child(mesh)
		add_child(ground)


func _make_panel_style(bg: Color, border: Color, pad: int = 10, radius: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _style_btn(b: Button, bg_hex: String = "#1e291d", hover_hex: String = "#2c3d2a", border_hex: String = "#556b49") -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _make_panel_style(Color.html(bg_hex), Color.html(border_hex), 6))
	b.add_theme_stylebox_override("hover", _make_panel_style(Color.html(hover_hex), Color.html("#8ca878"), 6))
	b.add_theme_stylebox_override("pressed", _make_panel_style(Color.html("#141c13"), Color.html("#a6c48a"), 6))
	b.add_theme_color_override("font_color", Color.html("#f2ead8"))
	b.add_theme_font_size_override("font_size", 11)


func _build_ui() -> void:
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)

	# 1. OVERLAY DE MIRA SNIPER SR-76
	_scope_overlay = Control.new()
	_scope_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_overlay.visible = false
	_scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_scope_overlay)
	var hline := ColorRect.new()
	hline.color = Color(0.0, 0.0, 0.0, 0.85)
	hline.anchor_left = 0.0
	hline.anchor_right = 1.0
	hline.anchor_top = 0.5
	hline.anchor_bottom = 0.5
	hline.offset_top = -1
	hline.offset_bottom = 1
	_scope_overlay.add_child(hline)
	var vline := ColorRect.new()
	vline.color = Color(0.0, 0.0, 0.0, 0.85)
	vline.anchor_left = 0.5
	vline.anchor_right = 0.5
	vline.anchor_top = 0.0
	vline.anchor_bottom = 1.0
	vline.offset_left = -1
	vline.offset_right = 1
	_scope_overlay.add_child(vline)

	# 2. MIRA TATICA 4 LINHAS + HITMARKER
	_crosshair_root = Control.new()
	_crosshair_root.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_crosshair_root)
	for rect_def in [[-11, -1, -4, 1], [4, -1, 11, 1], [-1, -11, 1, -4], [-1, 4, 1, 11]]:
		var cr := ColorRect.new()
		cr.color = Color(0.95, 0.96, 0.90, 0.88)
		cr.offset_left = rect_def[0]
		cr.offset_top = rect_def[1]
		cr.offset_right = rect_def[2]
		cr.offset_bottom = rect_def[3]
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair_root.add_child(cr)

	_hitmarker = ColorRect.new()
	_hitmarker.color = Color(1.0, 0.25, 0.20, 0.95)
	_hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker.offset_left = -7
	_hitmarker.offset_top = -7
	_hitmarker.offset_right = 7
	_hitmarker.offset_bottom = 7
	_hitmarker.visible = false
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_hitmarker)

	# 3. RELOGIO TATICO SUPERIOR ESQUERDO (.watch-widget do Condado de Knox!)
	var watch_panel := PanelContainer.new()
	watch_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	watch_panel.offset_left = 14
	watch_panel.offset_top = 14
	watch_panel.offset_right = 278
	watch_panel.offset_bottom = 104
	watch_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.88), Color(0.32, 0.42, 0.28, 0.92), 8))
	_hud_layer.add_child(watch_panel)

	var w_vbox := VBoxContainer.new()
	w_vbox.add_theme_constant_override("separation", 4)
	watch_panel.add_child(w_vbox)

	var w_top := HBoxContainer.new()
	w_top.add_theme_constant_override("separation", 8)
	w_vbox.add_child(w_top)

	_clock_lbl = Label.new()
	_clock_lbl.text = "11:30"
	_clock_lbl.add_theme_font_size_override("font_size", 20)
	_clock_lbl.add_theme_color_override("font_color", Color.html("#e9f0dc"))
	w_top.add_child(_clock_lbl)

	_net_badge_lbl = Label.new()
	_net_badge_lbl.text = "OFFLINE // SOLO"
	_net_badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_net_badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_net_badge_lbl.add_theme_font_size_override("font_size", 10)
	_net_badge_lbl.add_theme_color_override("font_color", Color.html("#8ec47a"))
	w_top.add_child(_net_badge_lbl)

	_watch_sub_lbl = Label.new()
	_watch_sub_lbl.text = "CONDADO DE KNOX  ·  ZUMBIS: 0  ·  ABATES: 0"
	_watch_sub_lbl.add_theme_font_size_override("font_size", 10)
	_watch_sub_lbl.add_theme_color_override("font_color", Color.html("#a9b89c"))
	w_vbox.add_child(_watch_sub_lbl)

	var w_btns := HBoxContainer.new()
	w_btns.add_theme_constant_override("separation", 6)
	w_vbox.add_child(w_btns)

	var btn_dev := Button.new()
	btn_dev.text = "DEV [F1]"
	btn_dev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_dev, "#24301f", "#33472c", "#74925e")
	btn_dev.pressed.connect(func() -> void: toggle_dev_panel(not _dev_open))
	w_btns.add_child(btn_dev)

	var btn_menu_top := Button.new()
	btn_menu_top.text = "MENU / RADMIN [TAB]"
	btn_menu_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_menu_top, "#1b241c", "#293829", "#4f6647")
	btn_menu_top.pressed.connect(func() -> void: toggle_menu(not _menu_open))
	w_btns.add_child(btn_menu_top)

	# 4. FAIXA SUPERIOR CENTRAL DE DICAS (.top-hints do Condado de Knox)
	var hints_panel := PanelContainer.new()
	hints_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hints_panel.offset_left = -300
	hints_panel.offset_top = 14
	hints_panel.offset_right = 300
	hints_panel.offset_bottom = 40
	hints_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.72), Color(0.26, 0.34, 0.24, 0.70), 4))
	hints_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(hints_panel)

	var hints_lbl := Label.new()
	hints_lbl.text = "[WASD] Mover  ·  [SHIFT] Correr  ·  [C] Agachar  ·  [RMB] Mira  ·  [V] 1P/3P  ·  [Q] Ombro  ·  [M] Mapa  ·  [E] Veiculo"
	hints_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints_lbl.add_theme_font_size_override("font_size", 10)
	hints_lbl.add_theme_color_override("font_color", Color.html("#cfd9c2"))
	hints_panel.add_child(hints_lbl)

	# 5. PROMPT DE INTERACAO CENTRAL INFERIOR ([E])
	_prompt_lbl = Label.new()
	_prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_lbl.offset_left = -260
	_prompt_lbl.offset_top = -176
	_prompt_lbl.offset_right = 260
	_prompt_lbl.offset_bottom = -150
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_lbl.add_theme_color_override("font_color", Color.html("#ffe6a8"))
	_prompt_lbl.add_theme_font_size_override("font_size", 13)
	_prompt_lbl.visible = false
	_hud_layer.add_child(_prompt_lbl)

	# 6. PAINEL DE STATUS INFERIOR ESQUERDO (.status-panel com SILHUETA CORPORAL!)
	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_panel.offset_left = 14
	status_panel.offset_top = -148
	status_panel.offset_right = 312
	status_panel.offset_bottom = -14
	status_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.90), Color(0.32, 0.42, 0.28, 0.92), 8))
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(status_panel)

	var sp_hbox := HBoxContainer.new()
	sp_hbox.add_theme_constant_override("separation", 10)
	status_panel.add_child(sp_hbox)

	_body_diagram = KnoxHUDDiagrams.new()
	_body_diagram.mode = "body"
	_body_diagram.custom_minimum_size = Vector2(64, 114)
	sp_hbox.add_child(_body_diagram)

	var v_box := VBoxContainer.new()
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_box.add_theme_constant_override("separation", 4)
	sp_hbox.add_child(v_box)

	_posture_lbl = Label.new()
	_posture_lbl.text = "EM PE  ·  3A PESSOA  ·  SOLO"
	_posture_lbl.add_theme_font_size_override("font_size", 10)
	_posture_lbl.add_theme_color_override("font_color", Color.html("#d8e4c8"))
	v_box.add_child(_posture_lbl)

	var hp_pair := _add_vital_bar(v_box, "SAUDE", 200.0, Color.html("#4ade80"), "200/200")
	_hp_bar = hp_pair[0]
	_hp_val_lbl = hp_pair[1]

	var st_pair := _add_vital_bar(v_box, "VIGOR", 100.0, Color.html("#60a5fa"), "100%")
	_stamina_bar = st_pair[0]
	_stamina_val_lbl = st_pair[1]

	var needs_row := HBoxContainer.new()
	needs_row.add_theme_constant_override("separation", 6)
	v_box.add_child(needs_row)
	_hunger_bar = _add_mini_bar(needs_row, "FOME", Color.html("#d99a38"))
	_thirst_bar = _add_mini_bar(needs_row, "SEDE", Color.html("#38bdf8"))

	_limbs_lbl = Label.new()
	_limbs_lbl.text = "BRACO: OK  ·  PERNA: OK  ·  [F] LUZ"
	_limbs_lbl.add_theme_font_size_override("font_size", 9)
	_limbs_lbl.add_theme_color_override("font_color", Color.html("#98b08a"))
	v_box.add_child(_limbs_lbl)

	# 7. CARD DE ARMA ATIVA ELEVADO + HOTBAR 9 SLOTS (Centro Inferior, igual ao Knox Web!)
	var hotbar_wrap := VBoxContainer.new()
	hotbar_wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_wrap.offset_left = -318
	hotbar_wrap.offset_top = -146
	hotbar_wrap.offset_right = 318
	hotbar_wrap.offset_bottom = -12
	hotbar_wrap.add_theme_constant_override("separation", 6)
	hotbar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(hotbar_wrap)

	# Active Weapon Callout Card
	var callout_center := HBoxContainer.new()
	callout_center.alignment = BoxContainer.ALIGNMENT_CENTER
	callout_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar_wrap.add_child(callout_center)

	var wp_card := PanelContainer.new()
	wp_card.custom_minimum_size = Vector2(360, 56)
	wp_card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.90), Color(0.45, 0.56, 0.36, 0.94), 6))
	wp_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	callout_center.add_child(wp_card)

	var wp_h := HBoxContainer.new()
	wp_h.add_theme_constant_override("separation", 10)
	wp_card.add_child(wp_h)

	_active_wp_icon = TextureRect.new()
	_active_wp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_active_wp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_active_wp_icon.custom_minimum_size = Vector2(74, 40)
	wp_h.add_child(_active_wp_icon)

	var wp_mid := VBoxContainer.new()
	wp_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wp_mid.add_theme_constant_override("separation", 1)
	wp_h.add_child(wp_mid)

	_active_wp_name = Label.new()
	_active_wp_name.text = "FUZIL M41-T 5.56"
	_active_wp_name.add_theme_font_size_override("font_size", 12)
	_active_wp_name.add_theme_color_override("font_color", Color.html("#f2ead8"))
	wp_mid.add_child(_active_wp_name)

	_active_wp_cal = Label.new()
	_active_wp_cal.text = "5.56 NATO · AUTO"
	_active_wp_cal.add_theme_font_size_override("font_size", 10)
	_active_wp_cal.add_theme_color_override("font_color", Color.html("#9cb38e"))
	wp_mid.add_child(_active_wp_cal)

	_active_wp_badge = Label.new()
	_active_wp_badge.text = "[R] Recarregar · [X] Silenciador OFF"
	_active_wp_badge.add_theme_font_size_override("font_size", 9)
	_active_wp_badge.add_theme_color_override("font_color", Color.html("#c8b674"))
	wp_mid.add_child(_active_wp_badge)

	_active_wp_ammo = Label.new()
	_active_wp_ammo.text = "30 / 30"
	_active_wp_ammo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_active_wp_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_active_wp_ammo.custom_minimum_size = Vector2(74, 0)
	_active_wp_ammo.add_theme_font_size_override("font_size", 18)
	_active_wp_ammo.add_theme_color_override("font_color", Color.html("#f5e3a6"))
	wp_h.add_child(_active_wp_ammo)

	# 9-Slot Icon Hotbar
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 5)
	hotbar_wrap.add_child(slots_row)

	_slot_style_normal = _make_panel_style(Color(0.05, 0.07, 0.05, 0.84), Color(0.28, 0.36, 0.25, 0.84), 4)
	_slot_style_active = _make_panel_style(Color(0.18, 0.25, 0.14, 0.96), Color(0.90, 0.80, 0.42, 1.0), 4)
	_hotbar_slots.clear()
	for i in range(WeaponArsenal.WEAPONS.size()):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(62, 52)
		slot.add_theme_stylebox_override("panel", _slot_style_normal)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 1)
		slot.add_child(sv)

		var num_l := Label.new()
		num_l.text = "%d · %s" % [i + 1, str(WeaponArsenal.WEAPONS[i]["code"])]
		num_l.add_theme_font_size_override("font_size", 9)
		num_l.add_theme_color_override("font_color", Color.html("#b9c4ad"))
		sv.add_child(num_l)

		var icon_tex: Texture2D = WeaponArsenal.get_weapon_icon(i)
		if icon_tex != null:
			var tr := TextureRect.new()
			tr.texture = icon_tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(52, 28)
			sv.add_child(tr)

		slots_row.add_child(slot)
		_hotbar_slots.append(slot)

	# 8. MINIMAPA TATICO NO CANTO INFERIOR DIREITO (#minimap-hud)
	minimap_hud = MinimapHUD.new()
	minimap_hud.world = self
	_hud_layer.add_child(minimap_hud)

	# 9. HUD DE VEICULO COM DIAGRAMA SUPERIOR (logo acima do Minimapa no canto direito!)
	_veh_panel = PanelContainer.new()
	_veh_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_veh_panel.offset_left = -286
	_veh_panel.offset_top = -352
	_veh_panel.offset_right = -14
	_veh_panel.offset_bottom = -234
	_veh_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.90), Color(0.42, 0.54, 0.35, 0.95), 8))
	_veh_panel.visible = false
	_hud_layer.add_child(_veh_panel)

	var vh := HBoxContainer.new()
	vh.add_theme_constant_override("separation", 10)
	_veh_panel.add_child(vh)

	_veh_diagram = KnoxHUDDiagrams.new()
	_veh_diagram.mode = "vehicle"
	_veh_diagram.custom_minimum_size = Vector2(66, 98)
	vh.add_child(_veh_diagram)

	var vv := VBoxContainer.new()
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.add_theme_constant_override("separation", 2)
	vh.add_child(vv)

	_veh_name_lbl = Label.new()
	_veh_name_lbl.text = "VIATURA KNOX PD"
	_veh_name_lbl.add_theme_font_size_override("font_size", 11)
	_veh_name_lbl.add_theme_color_override("font_color", Color.html("#f2ead8"))
	vv.add_child(_veh_name_lbl)

	_veh_seat_lbl = Label.new()
	_veh_seat_lbl.text = "MOTORISTA · 1/4"
	_veh_seat_lbl.add_theme_font_size_override("font_size", 9)
	_veh_seat_lbl.add_theme_color_override("font_color", Color.html("#9cb38e"))
	vv.add_child(_veh_seat_lbl)

	var spd_row := HBoxContainer.new()
	spd_row.add_theme_constant_override("separation", 6)
	vv.add_child(spd_row)

	_veh_speed_lbl = Label.new()
	_veh_speed_lbl.text = "0 KM/H"
	_veh_speed_lbl.add_theme_font_size_override("font_size", 19)
	_veh_speed_lbl.add_theme_color_override("font_color", Color.html("#f5e3a6"))
	spd_row.add_child(_veh_speed_lbl)

	_veh_drift_lbl = Label.new()
	_veh_drift_lbl.text = "DRIFT"
	_veh_drift_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_veh_drift_lbl.add_theme_font_size_override("font_size", 11)
	_veh_drift_lbl.add_theme_color_override("font_color", Color.html("#f59e0b"))
	_veh_drift_lbl.visible = false
	spd_row.add_child(_veh_drift_lbl)

	_veh_lights_lbl = Label.new()
	_veh_lights_lbl.text = "FAROIS: OFF  ·  [H] BUZINA"
	_veh_lights_lbl.add_theme_font_size_override("font_size", 9)
	_veh_lights_lbl.add_theme_color_override("font_color", Color.html("#b9c4ad"))
	vv.add_child(_veh_lights_lbl)

	_veh_hp_bar = _add_mini_bar(vv, "LATARIA", Color.html("#4ade80"))

	var v_hint := Label.new()
	v_hint.text = "[E] Sair · [G] Assento · [F] Farol"
	v_hint.add_theme_font_size_override("font_size", 9)
	v_hint.add_theme_color_override("font_color", Color.html("#8ca07e"))
	vv.add_child(v_hint)

	# 10. PAINEL DEV TOOLS [F1] (Sandbox Condado de Knox)
	_build_dev_panel()

	# 11. MAPA TATICO COMPLETO [M]
	tactical_map = TacticalMapOverlay.new()
	tactical_map.world = self
	_hud_layer.add_child(tactical_map)

	# 12. MENU CENTRALIZADO KNOX SURVIVAL 3D [TAB]
	_build_main_menu()


func _build_dev_panel() -> void:
	_dev_panel = PanelContainer.new()
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dev_panel.offset_left = 14
	_dev_panel.offset_top = 112
	_dev_panel.offset_right = 310
	_dev_panel.offset_bottom = 528
	_dev_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.05, 0.95), Color(0.54, 0.68, 0.42, 0.96), 10))
	_dev_panel.visible = false
	_hud_layer.add_child(_dev_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dev_panel.add_child(scroll)

	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 6)
	scroll.add_child(dv)

	var hdr := HBoxContainer.new()
	dv.add_child(hdr)
	var d_title := Label.new()
	d_title.text = "DEV TOOLS // CONDADO DE KNOX [F1]"
	d_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_title.add_theme_font_size_override("font_size", 11)
	d_title.add_theme_color_override("font_color", Color.html("#f5e3a6"))
	hdr.add_child(d_title)

	var btn_x := Button.new()
	btn_x.text = "X"
	_style_btn(btn_x, "#36201e", "#4d2b28", "#8f4c44")
	btn_x.pressed.connect(func() -> void: toggle_dev_panel(false))
	hdr.add_child(btn_x)

	_dev_god_chk = CheckButton.new()
	_dev_god_chk.text = "Modo Deus (Vida/Vigor Infinitos)"
	_dev_god_chk.add_theme_font_size_override("font_size", 11)
	_dev_god_chk.toggled.connect(func(on: bool) -> void:
		var lp := get_local_player()
		if lp != null:
			lp.god_mode = on
	)
	dv.add_child(_dev_god_chk)

	_dev_ammo_chk = CheckButton.new()
	_dev_ammo_chk.text = "Municao Infinita"
	_dev_ammo_chk.add_theme_font_size_override("font_size", 11)
	_dev_ammo_chk.toggled.connect(func(on: bool) -> void:
		var lp := get_local_player()
		if lp != null:
			lp.infinite_ammo = on
	)
	dv.add_child(_dev_ammo_chk)

	_dev_time_val_lbl = _mk_lbl("Horario Global: 11:30")
	dv.add_child(_dev_time_val_lbl)
	_dev_time_slider = HSlider.new()
	_dev_time_slider.min_value = 0.0
	_dev_time_slider.max_value = 23.95
	_dev_time_slider.step = 0.1
	_dev_time_slider.value = time_hours
	_dev_time_slider.value_changed.connect(func(val: float) -> void:
		request_set_time(val, storm_mode)
	)
	dv.add_child(_dev_time_slider)

	# 6 presets de horario identicos ao Condado de Knox Web
	var tp_grid := GridContainer.new()
	tp_grid.columns = 3
	tp_grid.add_theme_constant_override("h_separation", 4)
	tp_grid.add_theme_constant_override("v_separation", 4)
	dv.add_child(tp_grid)
	for preset in [["05:45", 5.75], ["07:30", 7.5], ["12:00", 12.0], ["17:48", 17.8], ["19:39", 19.65], ["23:00", 23.0]]:
		var b := Button.new()
		b.text = preset[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b)
		var th: float = preset[1]
		b.pressed.connect(func() -> void: request_set_time(th, storm_mode))
		tp_grid.add_child(b)

	dv.add_child(_mk_lbl("Spawn de Veiculos (Global):"))
	var v_grid := GridContainer.new()
	v_grid.columns = 2
	v_grid.add_theme_constant_override("h_separation", 4)
	v_grid.add_theme_constant_override("v_separation", 4)
	dv.add_child(v_grid)
	for sp_item in [["+ Sedan '92", 0], ["+ Viatura PD", 3], ["+ Moto Trail", 1], ["+ Moto Street", 2]]:
		var b := Button.new()
		b.text = sp_item[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b)
		var k: int = sp_item[1]
		b.pressed.connect(func() -> void: request_spawn_vehicle(k))
		v_grid.add_child(b)

	dv.add_child(_mk_lbl("Horda de Zumbis (Global):"))
	var z_row := HBoxContainer.new()
	z_row.add_theme_constant_override("separation", 4)
	dv.add_child(z_row)
	for zc in [["+5", 5], ["+20", 20]]:
		var b := Button.new()
		b.text = zc[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b, "#3b221e", "#522d27", "#995248")
		var cnt: int = zc[1]
		b.pressed.connect(func() -> void: request_spawn_zombies(cnt))
		z_row.add_child(b)
	var btn_clr_z := Button.new()
	btn_clr_z.text = "Limpar"
	btn_clr_z.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_clr_z, "#2a2d24", "#3b4032", "#6c7a5c")
	btn_clr_z.pressed.connect(request_clear_zombies)
	z_row.add_child(btn_clr_z)

	var p_row := HBoxContainer.new()
	p_row.add_theme_constant_override("separation", 4)
	dv.add_child(p_row)
	var btn_heal := Button.new()
	btn_heal.text = "Curar 200 HP"
	btn_heal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_heal, "#213a21", "#2e522e", "#5fa35f")
	btn_heal.pressed.connect(func() -> void:
		var lp := get_local_player()
		if lp != null:
			lp.heal_and_restock()
	)
	p_row.add_child(btn_heal)

	var btn_tp := Button.new()
	btn_tp.text = "TP Centro"
	btn_tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_tp)
	btn_tp.pressed.connect(func() -> void:
		var lp := get_local_player()
		if lp != null and lp.current_vehicle == null:
			lp.global_position = Vector3(0.0, 0.5, 0.0)
	)
	p_row.add_child(btn_tp)

	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 4)
	dv.add_child(weather_row)
	var btn_storm := Button.new()
	btn_storm.text = "Tempestade (Chuva)"
	btn_storm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_storm, "#1d2d3a", "#294154", "#5582a6")
	btn_storm.pressed.connect(func() -> void: request_set_time(time_hours, not storm_mode))
	weather_row.add_child(btn_storm)

	var btn_siren := Button.new()
	btn_siren.text = "Sirene de Alerta"
	btn_siren.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_siren, "#3e221b", "#593026", "#a85642")
	btn_siren.pressed.connect(request_air_raid_siren)
	weather_row.add_child(btn_siren)

	# Indicador de Assets / Plugins Asset Store ativos
	var addons: PackedStringArray = AssetBridge.detect_installed_addons()
	var packs: PackedStringArray = []
	if ResourceLoader.exists(AssetBridge.QUATERNIUS_RIG_PATH):
		packs.append("Quaternius Rig+Anims")
	if ResourceLoader.exists(AssetBridge.SFX_PACK_ROOT + "Hollywood/Titan Handgun.wav"):
		packs.append("SFX Vol.1")
	for ad in addons:
		packs.append(ad)
	_addons_lbl = _mk_lbl("Assets ativos: " + (", ".join(packs) if not packs.is_empty() else "padrao"))
	_addons_lbl.add_theme_color_override("font_color", Color.html("#8da67e"))
	dv.add_child(_addons_lbl)


func _build_main_menu() -> void:
	_menu_backdrop = ColorRect.new()
	_menu_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_backdrop.color = Color(0.03, 0.04, 0.03, 0.58)
	_hud_layer.add_child(_menu_backdrop)

	_menu_panel = PanelContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.offset_left = -280
	_menu_panel.offset_top = -315
	_menu_panel.offset_right = 280
	_menu_panel.offset_bottom = 315
	_menu_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.06, 0.96), Color(0.42, 0.54, 0.36, 0.96), 16))
	_menu_backdrop.add_child(_menu_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "CONDADO DE KNOX — SURVIVAL 3D (GODOT 4)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color.html("#f2ead8"))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Vulkan GPU + Multi-Core CPU · 9 Armas 3D · Carros/Motos · Audio 3D · Radmin VPN"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color.html("#9cb08e"))
	vbox.add_child(sub)

	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", 10)
	vbox.add_child(prof_row)

	var col_nick := VBoxContainer.new()
	col_nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_nick.add_child(_mk_lbl("Nome do Sobrevivente:"))
	_nick_inp = LineEdit.new()
	_nick_inp.text = local_nick
	_nick_inp.text_changed.connect(func(v: String) -> void:
		local_nick = v.strip_edges().left(18) if not v.strip_edges().is_empty() else "Sobrevivente"
		_save_profile()
		var lp := get_local_player()
		if lp != null:
			lp.nick = local_nick
	)
	col_nick.add_child(_nick_inp)
	prof_row.add_child(col_nick)

	var col_team := VBoxContainer.new()
	col_team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_team.add_child(_mk_lbl("Time / Party (Mapa [M]):"))
	_team_inp = LineEdit.new()
	_team_inp.text = local_team
	_team_inp.placeholder_text = "Ex: ALFA (vazio = solo)"
	_team_inp.text_changed.connect(func(v: String) -> void:
		local_team = v.strip_edges().to_upper().left(12)
		_save_profile()
		var lp := get_local_player()
		if lp != null:
			lp.team_id = local_team
	)
	col_team.add_child(_team_inp)
	prof_row.add_child(col_team)

	vbox.add_child(_mk_lbl("IP do Host no Radmin VPN (ex: 26.x.x.x ou 127.0.0.1):"))
	_ip_inp = LineEdit.new()
	_ip_inp.text = target_ip
	vbox.add_child(_ip_inp)

	var conn_row := HBoxContainer.new()
	conn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(conn_row)

	var btn_host := Button.new()
	btn_host.text = "CRIAR HOST / JOGAR (UDP 7777)"
	btn_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_host, "#284222", "#36592e", "#76a366")
	btn_host.pressed.connect(start_host_game)
	conn_row.add_child(btn_host)

	var btn_join := Button.new()
	btn_join.text = "CONECTAR NO RADMIN IP"
	btn_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_btn(btn_join, "#1f3448", "#2b4966", "#5888b0")
	btn_join.pressed.connect(func() -> void: start_client_game(_ip_inp.text))
	conn_row.add_child(btn_join)

	var btn_resume := Button.new()
	btn_resume.text = "VOLTAR A PARTIDA [TAB]"
	_style_btn(btn_resume, "#2d3326", "#3d4534", "#8a9a75")
	btn_resume.pressed.connect(func() -> void:
		if get_local_player() == null:
			start_host_game()
		else:
			toggle_menu(false)
	)
	vbox.add_child(btn_resume)

	_draw_dist_lbl = _mk_lbl("Distancia de Visao (GPU Frustum Culling): %dm" % int(draw_distance))
	vbox.add_child(_draw_dist_lbl)
	var dd_slider := HSlider.new()
	dd_slider.min_value = 150.0
	dd_slider.max_value = 1000.0
	dd_slider.step = 25.0
	dd_slider.value = draw_distance
	dd_slider.value_changed.connect(func(val: float) -> void: _apply_draw_distance(val))
	vbox.add_child(dd_slider)

	vbox.add_child(_mk_lbl("Horario Global (sincronizado para TODOS):"))
	var h_row := HBoxContainer.new()
	h_row.add_theme_constant_override("separation", 6)
	vbox.add_child(h_row)
	for pair in [["Amanhecer 06h", 6.2], ["Dia 12h", 12.0], ["Tarde 17:45", 17.75], ["Noite 23h", 23.0]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b)
		var target_h: float = pair[1]
		b.pressed.connect(func() -> void: request_set_time(target_h, storm_mode))
		h_row.add_child(b)

	vbox.add_child(_mk_lbl("Spawnar para TODOS na sala:"))
	var s_row := HBoxContainer.new()
	s_row.add_theme_constant_override("separation", 6)
	vbox.add_child(s_row)
	for sp_item in [["+ Sedan", 0], ["+ Viatura PD", 3], ["+ Moto Trail", 1], ["+ Moto Street", 2]]:
		var b := Button.new()
		b.text = sp_item[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b)
		var k: int = sp_item[1]
		b.pressed.connect(func() -> void: request_spawn_vehicle(k))
		s_row.add_child(b)

	var btn_z := Button.new()
	btn_z.text = "+ SPAWNAR 10 ZUMBIS (SINCRONIZADO PARA TODOS)"
	_style_btn(btn_z, "#3b221e", "#522d27", "#995248")
	btn_z.pressed.connect(func() -> void: request_spawn_zombies(10))
	vbox.add_child(btn_z)

	vbox.add_child(_mk_lbl("Buscar Cidade / Bairro Real (OpenStreetMap):"))
	var city_row := HBoxContainer.new()
	city_row.add_theme_constant_override("separation", 6)
	vbox.add_child(city_row)
	_city_inp = LineEdit.new()
	_city_inp.placeholder_text = "Ex: Avenida Paulista, Sao Paulo"
	_city_inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_search := Button.new()
	btn_search.text = "BUSCAR"
	_style_btn(btn_search, "#284222", "#36592e", "#76a366")
	btn_search.pressed.connect(_search_real_city_by_name)
	city_row.add_child(_city_inp)
	city_row.add_child(btn_search)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	vbox.add_child(preset_row)
	for cp in [["Paulista SP", -23.5614, -46.6559], ["Copacabana RJ", -22.9711, -43.1822], ["Curitiba", -25.4284, -49.2733]]:
		var b := Button.new()
		b.text = cp[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_btn(b)
		var plat: float = cp[1]
		var plng: float = cp[2]
		b.pressed.connect(func() -> void: request_load_real_city(plat, plng, 1.0))
		preset_row.add_child(b)

	var btn_disc := Button.new()
	btn_disc.text = "SAIR / ENCERRAR CONEXAO"
	_style_btn(btn_disc, "#331b1b", "#4a2424", "#8a4242")
	btn_disc.pressed.connect(disconnect_network)
	vbox.add_child(btn_disc)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", Color.html("#d4e4be"))
	_status_lbl.text = "Pronto! Clique em CRIAR HOST / JOGAR ou conecte via IP do Radmin VPN."
	vbox.add_child(_status_lbl)


func _add_vital_bar(parent: VBoxContainer, caption: String, max_v: float, fill_col: Color, init_val: String) -> Array:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 1)
	parent.add_child(wrap)

	var top := HBoxContainer.new()
	wrap.add_child(top)
	var lbl := Label.new()
	lbl.text = caption
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color.html("#b4c2a8"))
	top.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = init_val
	val_lbl.add_theme_font_size_override("font_size", 9)
	val_lbl.add_theme_color_override("font_color", Color.html("#e9f0dc"))
	top.add_child(val_lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max_v
	bar.value = max_v
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 11)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.13, 0.10, 0.96)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_col
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	wrap.add_child(bar)
	return [bar, val_lbl]


func _add_mini_bar(parent: Control, caption: String, fill_col: Color) -> ProgressBar:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	parent.add_child(col)

	var lbl := Label.new()
	lbl.text = caption
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color.html("#9cb08e"))
	col.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.13, 0.10, 0.96)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_col
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	col.add_child(bar)
	return bar


func _mk_lbl(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color.html("#c8d2bc"))
	return l


func _set_status(msg: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg
	print("[Knox] ", msg)


func _format_clock(h: float) -> String:
	var wrapped: float = fposmod(h, 24.0)
	var hh: int = int(floorf(wrapped))
	var mm: int = int(floorf((wrapped - float(hh)) * 60.0))
	return "%02d:%02d" % [hh, mm]


func _apply_draw_distance(meters: float) -> void:
	draw_distance = clampf(meters, 150.0, 1000.0)
	_save_profile()
	if _draw_dist_lbl != null:
		_draw_dist_lbl.text = "Distancia de Visao (GPU Frustum Culling): %dm" % int(draw_distance)
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
	return _menu_open or _dev_open or (tactical_map != null and tactical_map.visible)


func toggle_menu(open_state: bool) -> void:
	_menu_open = open_state
	if _menu_backdrop != null:
		_menu_backdrop.visible = open_state
	if open_state:
		_dev_open = false
		if _dev_panel != null:
			_dev_panel.visible = false
		if tactical_map != null:
			tactical_map.close_map()
	if audio_3d != null:
		audio_3d.play_ui_sfx("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_ui_blocking() else Input.MOUSE_MODE_CAPTURED


func toggle_dev_panel(open_state: bool) -> void:
	_dev_open = open_state
	if _dev_panel != null:
		_dev_panel.visible = open_state
	if open_state:
		_menu_open = false
		if _menu_backdrop != null:
			_menu_backdrop.visible = false
		if tactical_map != null:
			tactical_map.close_map()
	if audio_3d != null:
		audio_3d.play_ui_sfx("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_ui_blocking() else Input.MOUSE_MODE_CAPTURED


func toggle_full_map(open_state: bool) -> void:
	if tactical_map == null:
		return
	if open_state:
		_menu_open = false
		_dev_open = false
		if _menu_backdrop != null:
			_menu_backdrop.visible = false
		if _dev_panel != null:
			_dev_panel.visible = false
		tactical_map.open_map()
	else:
		tactical_map.close_map()
	if audio_3d != null:
		audio_3d.play_ui_sfx("map")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_ui_blocking() else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_dedicated:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_TAB or kc == KEY_ESCAPE:
			if _dev_open:
				toggle_dev_panel(false)
			elif tactical_map != null and tactical_map.visible:
				toggle_full_map(false)
			else:
				toggle_menu(not _menu_open)
		elif kc == KEY_F1:
			toggle_dev_panel(not _dev_open)
		elif kc == KEY_M:
			toggle_full_map(tactical_map != null and not tactical_map.visible)
		elif kc == KEY_MINUS and minimap_hud != null:
			minimap_hud.adjust_zoom(-0.22)
		elif kc == KEY_EQUAL and minimap_hud != null:
			minimap_hud.adjust_zoom(0.22)


func _process(delta: float) -> void:
	if is_dedicated:
		return
	if _hitmarker_t > 0.0:
		_hitmarker_t -= delta
		if _hitmarker_t <= 0.0 and _hitmarker != null:
			_hitmarker.visible = false

	# Atualiza Relogio Tatico Superior Esquerdo
	var alive_z: int = 0
	for z in get_all_zombies():
		if not z.is_dead:
			alive_z += 1
	if _clock_lbl != null:
		_clock_lbl.text = _format_clock(time_hours)
	if _net_badge_lbl != null:
		if not multiplayer.has_multiplayer_peer() or (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			_net_badge_lbl.text = "OFFLINE // SOLO"
			_net_badge_lbl.add_theme_color_override("font_color", Color.html("#b0b8a8"))
		elif multiplayer.is_server():
			_net_badge_lbl.text = "HOST // UDP %d" % server_port
			_net_badge_lbl.add_theme_color_override("font_color", Color.html("#4ade80"))
		else:
			_net_badge_lbl.text = "RADMIN // CONECTADO"
			_net_badge_lbl.add_theme_color_override("font_color", Color.html("#38bdf8"))

	var lp := get_local_player()
	if _watch_sub_lbl != null:
		var k_cnt: int = lp.kills if lp != null else 0
		_watch_sub_lbl.text = "CONDADO DE KNOX  ·  ZUMBIS: %d  ·  ABATES: %d" % [alive_z, k_cnt]

	if lp == null:
		return

	# Painel de Status Inferior Esquerdo + Silhueta Corporal
	var hp_ratio: float = clampf(float(lp.hp) / 200.0, 0.0, 1.0)
	if _body_diagram != null:
		_body_diagram.set_body_state(hp_ratio)
	if _hp_bar != null:
		_hp_bar.value = lp.hp
		_stamina_bar.value = lp.stamina
		_hunger_bar.value = lp.hunger
		_thirst_bar.value = lp.thirst
	if _hp_val_lbl != null:
		_hp_val_lbl.text = "%d / 200 HP" % lp.hp
	if _stamina_val_lbl != null:
		_stamina_val_lbl.text = "%d%%" % int(roundf(lp.stamina))
	if _posture_lbl != null:
		var cam_m: String = "1A PESSOA" if lp.is_first_person_mode() else "3A PESSOA"
		var t_tag: String = local_team if not local_team.is_empty() else "SOLO"
		_posture_lbl.text = "%s  ·  %s  ·  %s" % [lp.get_posture_label(), cam_m, t_tag]
	if _limbs_lbl != null:
		var limb_s: String = "OK" if hp_ratio > 0.65 else ("FERIDO" if hp_ratio > 0.30 else "CRITICO")
		var fl_s: String = "ON" if lp.flashlight_on else "OFF"
		_limbs_lbl.text = "BRACO: %s  ·  PERNA: %s  ·  LUZ: %s" % [limb_s, limb_s, fl_s]

	# Sniper Scope vs Crosshair
	var scoped: bool = lp.is_sniper_scoped() and not is_ui_blocking()
	if _scope_overlay != null:
		_scope_overlay.visible = scoped
	if _crosshair_root != null:
		_crosshair_root.visible = (not scoped) and (not is_ui_blocking())

	# HUD de Veiculo com Diagrama Superior (Carro/Moto)
	if _veh_panel != null:
		if lp.current_vehicle != null:
			var veh: Vehicle3D = lp.current_vehicle
			_veh_panel.visible = true
			var kmh: int = int(roundf(absf(veh.speed_mps) * 3.6))
			var seat_n: String = "PILOTO" if (veh.is_moto and lp.current_seat == 0) else ("GARUPA" if veh.is_moto else ("MOTORISTA" if lp.current_seat == 0 else "PASSAGEIRO"))
			_veh_name_lbl.text = veh.label
			_veh_seat_lbl.text = "%s  ·  %d/%d OCUP." % [seat_n, veh.get_occupied_count(), veh.seats.size()]
			_veh_speed_lbl.text = "%d KM/H" % kmh
			_veh_drift_lbl.visible = veh.drift_alpha > 0.25
			_veh_lights_lbl.text = "FAROIS: %s  ·  [H] BUZINA" % ("ON" if veh.lights_on else "OFF")
			var v_ratio: float = clampf(veh.hp / maxf(1.0, veh.max_hp), 0.0, 1.0)
			_veh_hp_bar.value = v_ratio * 100.0
			_veh_diagram.set_vehicle_state(v_ratio, veh.is_moto, veh.is_police, veh.lights_on, veh.steer_smooth)
		else:
			_veh_panel.visible = false

	# Prompt contextual de interacao ([E])
	if _prompt_lbl != null:
		var p_txt: String = ""
		if lp.current_vehicle == null and not is_ui_blocking():
			if _find_nearest_loot_crate(lp.global_position, 3.2) != null:
				p_txt = "[E] Coletar Caixa de Suprimentos (Vida + Fome + Municao)"
			else:
				var nv := find_nearest_vehicle(lp.global_position, 4.6)
				if nv != null:
					p_txt = "[E] Subir em %s  ·  [Shift+E] Garupa/Passageiro" % nv.label
		_prompt_lbl.text = p_txt
		_prompt_lbl.visible = not p_txt.is_empty()

	# Active Weapon Callout + Hotbar das 9 armas
	var w: Dictionary = lp.get_active_weapon_def()
	if _active_wp_name != null:
		_active_wp_name.text = str(w["name"])
		_active_wp_cal.text = str(w["cal"])
		if bool(w["melee"]):
			_active_wp_ammo.text = "∞"
			_active_wp_badge.text = "CORPO A CORPO  ·  [CLIQUE ESQ.] GOLPE"
		elif lp.reloading:
			_active_wp_ammo.text = "..."
			_active_wp_badge.text = "RECARREGANDO..."
		else:
			var ammo_txt: String = "∞" if lp.infinite_ammo else ("%d / %d" % [lp.get_active_mag(), int(w["mag_size"])])
			_active_wp_ammo.text = ammo_txt
			var sup_s: String = "SILENCIADOR ON [X]" if lp.suppressed else "[R] Recarregar · [X] Silenciador OFF"
			_active_wp_badge.text = sup_s

	if lp.active_weapon_idx != _last_hotbar_idx:
		_last_hotbar_idx = lp.active_weapon_idx
		if _active_wp_icon != null:
			_active_wp_icon.texture = WeaponArsenal.get_weapon_icon(lp.active_weapon_idx)
		for i in range(_hotbar_slots.size()):
			_hotbar_slots[i].add_theme_stylebox_override("panel", _slot_style_active if i == lp.active_weapon_idx else _slot_style_normal)


func _find_nearest_loot_crate(pos: Vector3, max_d: float) -> Node3D:
	if map_loader == null:
		return null
	var best: Node3D = null
	var best_d: float = max_d
	for c in map_loader.loot_crates:
		if is_instance_valid(c) and c.visible:
			var d: float = pos.distance_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
	return best


func try_pickup_nearest_loot(player: SurvivorPlayer, max_d: float) -> bool:
	var c := _find_nearest_loot_crate(player.global_position, max_d)
	if c == null:
		return false
	c.visible = false
	player.heal_and_restock()
	if audio_3d != null:
		audio_3d.play_ui_sfx("loot")
	_set_status("Suprimentos coletados: +Vida, +Fome/Sede e Municao cheia!")
	return true


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
	_server_spawn_vehicle(Vector3(6.0, 0.12, -7.0), 0.15, 3)   # Viatura Policial Knox PD
	_server_spawn_vehicle(Vector3(-4.8, 0.12, -6.5), 0.35, 1)  # Moto Trail 450
	_server_spawn_vehicle(Vector3(-8.2, 0.12, -6.5), -0.25, 2) # Moto Street 600
	_server_spawn_vehicle(Vector3(10.5, 0.12, -11.0), -0.4, 0) # Knox Sedan '92
	_server_spawn_zombies(Vector3(0.0, 0.0, -34.0), 12)


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
		var kind: int = 3 if v.is_police else (2 if v.moto_style == "street" else (1 if v.is_moto else 0))
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
		if _dev_god_chk != null:
			p.god_mode = _dev_god_chk.button_pressed
		if _dev_ammo_chk != null:
			p.infinite_ammo = _dev_ammo_chk.button_pressed
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
	if _dev_time_slider != null:
		_dev_time_slider.set_value_no_signal(time_hours)
	if _dev_time_val_lbl != null:
		_dev_time_val_lbl.text = "Horario Global: %s" % _format_clock(time_hours)
	_apply_time_of_day()


func _apply_time_of_day() -> void:
	if _sun == null:
		return
	var elev: float = sin(((time_hours - 6.0) / 24.0) * TAU)
	var pitch_deg: float = lerpf(-18.0, -72.0, inverse_lerp(-1.0, 1.0, elev))
	_sun.rotation_degrees = Vector3(pitch_deg, (time_hours / 24.0) * 360.0 - 90.0, 0.0)
	var is_night: bool = elev < 0.04
	var is_golden: bool = elev >= 0.04 and elev < 0.34
	var storm_dim: float = 0.52 if storm_mode else 1.0
	_sun.light_energy = (0.14 if is_night else (lerpf(0.55, 1.15, (elev - 0.04) / 0.30) if is_golden else lerpf(1.15, 1.42, clampf(elev, 0.0, 1.0)))) * storm_dim
	_sun.light_color = Color(0.56, 0.70, 0.96) if (is_night or storm_mode) else (Color(1.0, 0.78, 0.56) if is_golden else Color(1.0, 0.95, 0.87))
	if _sky_mat != null:
		if storm_mode:
			_sky_mat.sky_top_color = Color(0.08, 0.10, 0.14)
			_sky_mat.sky_horizon_color = Color(0.18, 0.21, 0.25)
		elif is_night:
			_sky_mat.sky_top_color = Color(0.03, 0.05, 0.11)
			_sky_mat.sky_horizon_color = Color(0.07, 0.09, 0.16)
		elif is_golden:
			_sky_mat.sky_top_color = Color(0.20, 0.34, 0.58)
			_sky_mat.sky_horizon_color = Color(0.88, 0.58, 0.40)
		else:
			_sky_mat.sky_top_color = Color(0.24, 0.48, 0.82)
			_sky_mat.sky_horizon_color = Color(0.66, 0.76, 0.86)
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.fog_light_color = Color(0.16, 0.19, 0.22) if storm_mode else (Color(0.05, 0.07, 0.12) if is_night else (Color(0.76, 0.58, 0.48) if is_golden else Color(0.64, 0.74, 0.84)))
	if map_loader != null:
		map_loader.set_night_streetlights(is_night or storm_mode)
	if audio_3d != null:
		audio_3d.update_environment_ambience(is_night, storm_mode)


func request_air_raid_siren() -> void:
	var lp := get_local_player()
	var origin: Vector3 = lp.global_position if lp != null else Vector3.ZERO
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		alert_zombies_in_radius(origin, 140.0)
		_rpc_play_siren.rpc(origin)
	else:
		_rpc_req_siren.rpc_id(1, origin)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_siren(origin: Vector3) -> void:
	if multiplayer.is_server():
		alert_zombies_in_radius(origin, 140.0)
		_rpc_play_siren.rpc(origin)


@rpc("authority", "call_local", "reliable")
func _rpc_play_siren(origin: Vector3) -> void:
	if audio_3d != null:
		audio_3d.play_siren_3d(origin)
	_set_status("SIRENE DE ALERTA DO CONDADO DE KNOX ACIONADA!")


func request_spawn_vehicle(kind: int) -> void:
	var lp := get_local_player()
	var pos: Vector3 = Vector3(0.0, 0.15, -6.0)
	var yaw: float = 0.0
	if lp != null:
		var ay: float = lp.get_aim_yaw()
		var fwd := Vector3(-sin(ay), 0.0, -cos(ay))
		pos = lp.global_position + fwd * 5.8 + Vector3(0.0, 0.15, 0.0)
		yaw = ay
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


func request_clear_zombies() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_rpc_clear_zombies.rpc()
	else:
		_rpc_req_clear_zombies.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_clear_zombies() -> void:
	if multiplayer.is_server():
		_rpc_clear_zombies.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_clear_zombies() -> void:
	for z in get_all_zombies():
		z.queue_free()


@rpc("any_peer", "call_local", "reliable")
func _rpc_req_spawn_zombies(center: Vector3, count: int) -> void:
	if multiplayer.is_server():
		_server_spawn_zombies(center, clampi(count, 1, 50))


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
	var hit_confirm: int = 0
	var got_kill: bool = false
	if not hit.is_empty():
		end_pos = hit["position"]
		var col: Object = hit["collider"]
		if col is Zombie3D:
			var z := col as Zombie3D
			var is_head: bool = end_pos.y > z.global_position.y + 1.40
			got_kill = z.apply_server_damage(dmg * (3.2 if is_head else 1.0))
			hit_confirm = 2 if (is_head or got_kill) else 1
		elif col is SurvivorPlayer:
			var tgt := col as SurvivorPlayer
			var same_team: bool = shooter != null and TacticalMapOverlay.should_show_player_on_map(shooter.team_id, tgt.team_id)
			if not same_team:
				tgt.apply_damage(int(dmg))
				hit_confirm = 1

	if play_audio:
		var eff_noise: float = noise_r * (0.24 if profile == "suppressed" else 1.0)
		alert_zombies_in_radius(muzzle_pos, eff_noise)
	_rpc_play_shot.rpc(shooter_pid, profile, muzzle_pos, end_pos, play_audio, hit_confirm > 0)
	if hit_confirm > 0:
		if multiplayer.has_multiplayer_peer() and shooter_pid != 1:
			_rpc_show_hitmarker.rpc_id(shooter_pid, hit_confirm == 2, got_kill)
		else:
			_show_hitmarker(hit_confirm == 2, got_kill)


@rpc("authority", "call_local", "reliable")
func _rpc_show_hitmarker(is_crit: bool, got_kill: bool) -> void:
	_show_hitmarker(is_crit, got_kill)


func _show_hitmarker(is_crit: bool, got_kill: bool) -> void:
	if got_kill:
		var lp := get_local_player()
		if lp != null:
			lp.kills += 1
	if audio_3d != null:
		audio_3d.play_ui_sfx("crit" if (is_crit or got_kill) else "hit")
	if _hitmarker == null:
		return
	_hitmarker.color = Color(1.0, 0.22, 0.18, 0.95) if is_crit else Color(1.0, 1.0, 1.0, 0.92)
	_hitmarker.visible = true
	_hitmarker_t = 0.14


@rpc("authority", "call_local", "unreliable")
func _rpc_play_shot(shooter_pid: int, profile: String, muzzle_pos: Vector3, end_pos: Vector3, play_audio: bool, is_flesh_hit: bool) -> void:
	var is_local: bool = (not multiplayer.has_multiplayer_peer()) or (shooter_pid == multiplayer.get_unique_id())
	if play_audio and audio_3d != null:
		audio_3d.play_gunshot_3d(profile, muzzle_pos, end_pos, is_local)
	_spawn_tracer(muzzle_pos, end_pos)
	if is_flesh_hit:
		_spawn_blood_burst(end_pos)


func _spawn_blood_burst(pos: Vector3) -> void:
	if is_dedicated:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.08, 0.06)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	var t := get_tree().create_timer(0.11)
	t.timeout.connect(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
	)


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
