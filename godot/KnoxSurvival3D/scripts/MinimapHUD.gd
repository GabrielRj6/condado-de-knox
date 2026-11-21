extends Control
class_name MinimapHUD

## Minimapa Tatico no canto INFERIOR DIREITO (layout 1:1 do #minimap-hud do Condado de Knox Web).
## Mostra ruas, predios (Hospital vermelho, Delegacia azul), veiculos, aliados do time,
## seta do jogador local, nome da rua, bussola e controles de zoom [- / +].

var world: Node = null
var zoom_scale: float = 1.10
var _draw_timer: float = 0.0
var _btn_minus: Button
var _btn_plus: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -228
	offset_top = -224
	offset_right = -14
	offset_bottom = -14
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Botoes compactos de zoom [- / +] no rodape do minimapa
	_btn_minus = _make_zoom_btn("-", Vector2(6, 186))
	_btn_minus.pressed.connect(func() -> void: adjust_zoom(-0.22))
	add_child(_btn_minus)

	_btn_plus = _make_zoom_btn("+", Vector2(30, 186))
	_btn_plus.pressed.connect(func() -> void: adjust_zoom(0.22))
	add_child(_btn_plus)


func _make_zoom_btn(txt: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = pos
	b.size = Vector2(20, 18)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color.html("#e4ecd8"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.15, 0.11, 0.92)
	sb.border_color = Color(0.34, 0.44, 0.30, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	return b


func adjust_zoom(delta_z: float) -> void:
	zoom_scale = clampf(zoom_scale + delta_z, 0.45, 2.60)
	queue_redraw()


func _process(delta: float) -> void:
	_draw_timer += delta
	if _draw_timer >= 0.05:
		_draw_timer = 0.0
		queue_redraw()


func _get_compass_label(yaw: float) -> String:
	var deg: float = fposmod(rad_to_deg(-yaw), 360.0)
	var dirs: PackedStringArray = ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]
	return dirs[int(roundf(deg / 45.0)) % 8]


func _draw() -> void:
	var sz: Vector2 = size
	# Moldura tatica oliva escura (identica ao HUD Condado de Knox)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.07, 0.05, 0.90), true)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.32, 0.42, 0.28, 0.92), false, 1.8)

	var header_h: float = 22.0
	var footer_h: float = 26.0
	draw_rect(Rect2(Vector2(1, 1), Vector2(sz.x - 2, header_h)), Color(0.08, 0.11, 0.08, 0.96), true)
	draw_line(Vector2(1, header_h), Vector2(sz.x - 1, header_h), Color(0.28, 0.36, 0.25, 0.85), 1.0)

	var map_rect := Rect2(Vector2(4, header_h + 3), Vector2(sz.x - 8, sz.y - header_h - footer_h - 4))
	draw_rect(map_rect, Color(0.07, 0.10, 0.07, 1.0), true)

	if world == null:
		return
	var lp: SurvivorPlayer = world.get_local_player()
	var center_w: Vector3 = lp.global_position if lp != null else Vector3.ZERO
	var yaw: float = lp.get_aim_yaw() if lp != null else 0.0
	if lp != null and lp.current_vehicle != null:
		yaw = lp.current_vehicle.rotation.y

	var font: Font = ThemeDB.fallback_font
	var street_txt: String = "CONDADO DE KNOX"
	if world.map_loader != null and not world.map_loader.roads.is_empty():
		var best_d: float = 99999.0
		for r in world.map_loader.roads:
			var pts: Array = r["points"]
			if pts.is_empty():
				continue
			var mid: Vector3 = pts[pts.size() / 2]
			var d: float = Vector2(mid.x - center_w.x, mid.z - center_w.z).length()
			if d < best_d:
				best_d = d
				street_txt = str(r["name"]).to_upper().left(18)

	draw_string(font, Vector2(8, 15), street_txt, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 42, 10, Color(0.86, 0.90, 0.80))
	draw_string(font, Vector2(sz.x - 32, 15), _get_compass_label(yaw), HORIZONTAL_ALIGNMENT_RIGHT, 24, 11, Color(0.95, 0.80, 0.42))

	var mc: Vector2 = map_rect.get_center()
	var sc: float = zoom_scale

	if world.map_loader != null:
		for bd in world.map_loader.buildings:
			var bc: Vector3 = bd["center"]
			var bs: Vector2 = bd["size"]
			var rel: Vector2 = Vector2(bc.x - center_w.x, bc.z - center_w.z) * sc
			var p: Vector2 = mc + rel
			var half_b: Vector2 = bs * 0.5 * sc
			var brect := Rect2(p - half_b, half_b * 2.0)
			if map_rect.intersects(brect):
				var clamped := brect.intersection(map_rect)
				var btype: String = str(bd.get("kind", "urban"))
				var bcol: Color = Color(0.64, 0.24, 0.24, 0.92) if btype == "hospital" else (Color(0.24, 0.38, 0.62, 0.92) if btype == "police" else Color(0.26, 0.31, 0.26, 0.88))
				draw_rect(clamped, bcol, true)

		for r in world.map_loader.roads:
			var pts: Array = r["points"]
			for i in range(pts.size() - 1):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[i + 1]
				var pa: Vector2 = mc + Vector2(a.x - center_w.x, a.z - center_w.z) * sc
				var pb: Vector2 = mc + Vector2(b.x - center_w.x, b.z - center_w.z) * sc
				if map_rect.has_point(pa) or map_rect.has_point(pb):
					pa = pa.clamp(map_rect.position, map_rect.end)
					pb = pb.clamp(map_rect.position, map_rect.end)
					draw_line(pa, pb, Color(0.54, 0.56, 0.50, 0.84), 2.8)

	# Veiculos
	for v in world.get_all_vehicles():
		var vp: Vector2 = mc + Vector2(v.global_position.x - center_w.x, v.global_position.z - center_w.z) * sc
		if map_rect.has_point(vp):
			draw_circle(vp, 3.0, Color(0.96, 0.72, 0.22) if v.is_moto else Color(0.95, 0.86, 0.38))

	# Aliados do mesmo time
	var my_team: String = lp.team_id if lp != null else ""
	for p in world.get_all_players():
		if p == lp:
			continue
		if not TacticalMapOverlay.should_show_player_on_map(my_team, p.team_id):
			continue
		var pp: Vector2 = mc + Vector2(p.global_position.x - center_w.x, p.global_position.z - center_w.z) * sc
		if map_rect.has_point(pp):
			draw_circle(pp, 3.8, Color(0.25, 0.86, 1.0))

	# Seta do jogador local no centro
	var fwd := Vector2(-sin(yaw), -cos(yaw)).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = mc + fwd * 7.5
	var base_l: Vector2 = mc - fwd * 4.8 - right * 4.6
	var base_r: Vector2 = mc - fwd * 4.8 + right * 4.6
	draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), Color(0.28, 0.96, 0.42))

	# Rodape com escala + atalho [M]
	draw_line(Vector2(1, sz.y - footer_h), Vector2(sz.x - 1, sz.y - footer_h), Color(0.24, 0.32, 0.22, 0.78), 1.0)
	draw_string(font, Vector2(56, sz.y - 8), "MAPA [M] · %.1fx" % zoom_scale, HORIZONTAL_ALIGNMENT_RIGHT, sz.x - 64, 10, Color(0.68, 0.76, 0.62))
