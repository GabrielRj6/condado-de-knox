extends Control
class_name TacticalMapOverlay

## Mapa Tatico Completo [M]:
## - Botoes (+) e (-) de zoom + scroll do mouse + arrastar
## - Clique esquerdo para marcar locais, direito para remover
## - Rota GPS automatica quando o jogador esta de carro ou moto
## - Visibilidade ESTRITA por time: jogadores so aparecem um para o outro se forem do MESMO time!

var world: Node = null
var zoom: float = 1.0
var center_world: Vector2 = Vector2.ZERO
var markers: Array[Vector2] = []
var route_enabled: bool = false

var _dragging: bool = false
var _drag_moved: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_origin_world: Vector2 = Vector2.ZERO

var _bar: HBoxContainer
var _zoom_lbl: Label
var _route_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_bar = HBoxContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -54.0
	_bar.offset_bottom = -12.0
	_bar.offset_left = 24.0
	_bar.offset_right = -24.0
	_bar.add_theme_constant_override("separation", 10)
	add_child(_bar)

	var btn_minus := Button.new()
	btn_minus.text = "  −  "
	btn_minus.pressed.connect(func() -> void: _adjust_zoom(1.0 / 1.3))
	_bar.add_child(btn_minus)

	_zoom_lbl = Label.new()
	_zoom_lbl.text = "1.0x"
	_bar.add_child(_zoom_lbl)

	var btn_plus := Button.new()
	btn_plus.text = "  +  "
	btn_plus.pressed.connect(func() -> void: _adjust_zoom(1.3))
	_bar.add_child(btn_plus)

	_route_btn = Button.new()
	_route_btn.text = "ROTA GPS: OFF"
	_route_btn.pressed.connect(func() -> void:
		route_enabled = not route_enabled
		_refresh_buttons()
		queue_redraw()
	)
	_bar.add_child(_route_btn)

	var btn_clear := Button.new()
	btn_clear.text = "LIMPAR MARCADORES"
	btn_clear.pressed.connect(func() -> void:
		markers.clear()
		route_enabled = false
		_refresh_buttons()
		queue_redraw()
	)
	_bar.add_child(btn_clear)

	var btn_center := Button.new()
	btn_center.text = "CENTRALIZAR EM MIM"
	btn_center.pressed.connect(center_on_local)
	_bar.add_child(btn_center)

	var btn_close := Button.new()
	btn_close.text = "FECHAR [M]"
	btn_close.pressed.connect(func() -> void:
		if world != null:
			world.toggle_full_map(false)
	)
	_bar.add_child(btn_close)


func open_map() -> void:
	center_on_local()
	var local: SurvivorPlayer = world.get_local_player() if world != null else null
	if local != null and local.current_vehicle != null and not markers.is_empty():
		route_enabled = true
	_refresh_buttons()
	visible = true
	queue_redraw()


func close_map() -> void:
	visible = false


func center_on_local() -> void:
	if world == null:
		return
	var local: SurvivorPlayer = world.get_local_player()
	if local != null:
		center_world = Vector2(local.global_position.x, local.global_position.z)
	queue_redraw()


func _adjust_zoom(mult: float) -> void:
	zoom = clampf(zoom * mult, 0.35, 6.0)
	_refresh_buttons()
	queue_redraw()


func _refresh_buttons() -> void:
	if _zoom_lbl != null:
		_zoom_lbl.text = "%.1fx" % zoom
	if _route_btn != null:
		_route_btn.text = "ROTA GPS: ATIVA" if route_enabled else "ROTA GPS: OFF"


static func should_show_player_on_map(local_team: String, other_team: String) -> bool:
	var a: String = local_team.strip_edges().to_upper()
	var b: String = other_team.strip_edges().to_upper()
	return (not a.is_empty()) and (a == b)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_adjust_zoom(1.18)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_adjust_zoom(1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not markers.is_empty():
				markers.pop_back()
				queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start = mb.position
				_drag_origin_world = center_world
			else:
				if _dragging and not _drag_moved:
					markers.append(_screen_to_world(mb.position))
					var local: SurvivorPlayer = world.get_local_player() if world != null else null
					if local != null and local.current_vehicle != null:
						route_enabled = true
						_refresh_buttons()
					queue_redraw()
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta_px: Vector2 = mm.position - _drag_start
		if delta_px.length() > 5.0:
			_drag_moved = true
		if _drag_moved:
			var ppm: float = _pixels_per_meter()
			center_world = _drag_origin_world - delta_px / maxf(0.01, ppm)
			queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _pixels_per_meter() -> float:
	return (size.y / 380.0) * zoom


func _world_to_screen(wp: Vector2) -> Vector2:
	var ppm: float = _pixels_per_meter()
	return size * 0.5 + (wp - center_world) * ppm


func _screen_to_world(sp: Vector2) -> Vector2:
	var ppm: float = _pixels_per_meter()
	return center_world + (sp - size * 0.5) / maxf(0.01, ppm)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.07, 0.94))
	var font: Font = ThemeDB.fallback_font

	# Titulo
	draw_string(font, Vector2(24, 34), "MAPA TATICO [M] — CLIQUE ESQ: MARCAR LOCAL | DIR: REMOVER | SOMENTE ALIADOS DO MESMO TIME VISIVEIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.90, 0.88, 0.78))

	if world != null and world.map_loader != null:
		var ppm: float = _pixels_per_meter()
		# Predios
		for bd in world.map_loader.buildings:
			var c: Vector3 = bd["center"]
			var sz: Vector2 = bd["size"]
			var sp: Vector2 = _world_to_screen(Vector2(c.x, c.z))
			var rw: float = maxf(2.0, sz.x * ppm)
			var rh: float = maxf(2.0, sz.y * ppm)
			draw_rect(Rect2(sp - Vector2(rw, rh) * 0.5, Vector2(rw, rh)), Color(0.28, 0.30, 0.28, 0.85))
		# Ruas
		for road in world.map_loader.roads:
			var pts: Array = road["points"]
			for i in range(pts.size() - 1):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[i + 1]
				draw_line(_world_to_screen(Vector2(a.x, a.z)), _world_to_screen(Vector2(b.x, b.z)), Color(0.46, 0.48, 0.44, 0.8), 2.2)

	var local: SurvivorPlayer = world.get_local_player() if world != null else null

	# Rota GPS (linha ciano ate o marcador de destino)
	if local != null and not markers.is_empty() and (route_enabled or local.current_vehicle != null):
		var from_sp: Vector2 = _world_to_screen(Vector2(local.global_position.x, local.global_position.z))
		var target_w: Vector2 = markers[markers.size() - 1]
		var to_sp: Vector2 = _world_to_screen(target_w)
		draw_line(from_sp, to_sp, Color(0.22, 0.86, 1.0, 0.95), 3.2)
		var dist_m: float = Vector2(local.global_position.x, local.global_position.z).distance_to(target_w)
		draw_string(font, (from_sp + to_sp) * 0.5 + Vector2(8, -8), "GPS %.0fm" % dist_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.94, 1.0))

	# Marcadores taticos
	for i in range(markers.size()):
		var mp: Vector2 = _world_to_screen(markers[i])
		draw_circle(mp, 6.0, Color(1.0, 0.62, 0.14))
		draw_string(font, mp + Vector2(9, 4), "PIN #%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.82, 0.45))

	# Jogador local + SOMENTE jogadores do MESMO TIME!
	if world != null:
		var local_team: String = local.team_id if local != null else ""
		for p in world.get_all_players():
			var is_self: bool = (p == local)
			if not is_self and not should_show_player_on_map(local_team, p.team_id):
				continue
			var sp: Vector2 = _world_to_screen(Vector2(p.global_position.x, p.global_position.z))
			var col: Color = Color(1.0, 0.90, 0.25) if is_self else Color(0.42, 0.95, 0.46)
			draw_circle(sp, 6.5 if is_self else 5.5, col)
			var tag: String = "%s (VOCE)" % p.nick if is_self else "◆ %s" % p.nick
			draw_string(font, sp + Vector2(9, 4), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
