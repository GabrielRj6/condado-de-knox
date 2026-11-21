extends Control
class_name MinimapHUD

## Minimapa Tatico no canto superior direito (igual ao #minimap-hud do Knox Survival 3D Web).
## Mostra ruas, predios, veiculos, aliados do mesmo time, seta do jogador, bussola e nome da rua.

var world: Node = null
var zoom_scale: float = 1.15
var _draw_timer: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -248
	offset_top = 16
	offset_right = -16
	offset_bottom = 228
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	# Moldura tatica oliva escura (identica ao Web HUD)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.08, 0.06, 0.88), true)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.32, 0.40, 0.28, 0.92), false, 2.0)

	# Cabecalho superior (Nome da rua + Bussola)
	var header_h: float = 24.0
	draw_rect(Rect2(Vector2(1, 1), Vector2(sz.x - 2, header_h)), Color(0.09, 0.12, 0.09, 0.96), true)
	draw_line(Vector2(1, header_h), Vector2(sz.x - 1, header_h), Color(0.28, 0.36, 0.25, 0.85), 1.0)

	var map_rect := Rect2(Vector2(4, header_h + 3), Vector2(sz.x - 8, sz.y - header_h - 7))
	draw_rect(map_rect, Color(0.08, 0.11, 0.08, 1.0), true)

	if world == null:
		return
	var lp: SurvivorPlayer = world.get_local_player()
	var center_w: Vector3 = lp.global_position if lp != null else Vector3.ZERO
	var yaw: float = lp.rotation.y if lp != null else 0.0
	if lp != null and lp.current_vehicle != null:
		yaw = lp.current_vehicle.rotation.y

	var font: Font = ThemeDB.fallback_font
	var street_txt: String = "KNOX COUNTY · RADMIN"
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
				street_txt = str(r["name"]).to_upper().left(20)

	draw_string(font, Vector2(8, 17), street_txt, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 42, 11, Color(0.86, 0.88, 0.80))
	draw_string(font, Vector2(sz.x - 32, 17), _get_compass_label(yaw), HORIZONTAL_ALIGNMENT_RIGHT, 24, 12, Color(0.95, 0.80, 0.42))

	var mc: Vector2 = map_rect.get_center()
	var sc: float = zoom_scale

	# Predios dentro do minimapa
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
				var bcol: Color = Color(0.62, 0.24, 0.24, 0.90) if btype == "hospital" else (Color(0.24, 0.36, 0.58, 0.90) if btype == "police" else Color(0.28, 0.32, 0.27, 0.88))
				draw_rect(clamped, bcol, true)

		# Ruas
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
					draw_line(pa, pb, Color(0.55, 0.57, 0.52, 0.82), 3.0)

	# Veiculos (amarelo/laranja)
	for v in world.get_all_vehicles():
		var vp: Vector2 = mc + Vector2(v.global_position.x - center_w.x, v.global_position.z - center_w.z) * sc
		if map_rect.has_point(vp):
			draw_circle(vp, 3.2, Color(0.96, 0.72, 0.22) if v.is_moto else Color(0.95, 0.86, 0.38))

	# Aliados do mesmo time (azul ciano)
	var my_team: String = lp.team_id if lp != null else ""
	for p in world.get_all_players():
		if p == lp:
			continue
		if not TacticalMapOverlay.should_show_player_on_map(my_team, p.team_id):
			continue
		var pp: Vector2 = mc + Vector2(p.global_position.x - center_w.x, p.global_position.z - center_w.z) * sc
		if map_rect.has_point(pp):
			draw_circle(pp, 4.0, Color(0.25, 0.86, 1.0))

	# Seta do jogador local no centro apontando para frente
	var fwd := Vector2(-sin(yaw), -cos(yaw)).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = mc + fwd * 8.0
	var base_l: Vector2 = mc - fwd * 5.0 - right * 5.0
	var base_r: Vector2 = mc - fwd * 5.0 + right * 5.0
	draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), Color(0.28, 0.96, 0.42))
