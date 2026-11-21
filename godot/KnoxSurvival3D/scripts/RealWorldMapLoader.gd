extends Node3D
class_name RealWorldMapLoader

## Carregador de cidade 3D 1:1 portado do Knox Survival 3D (OpenStreetMap + Cidade Local):
## - Ruas com asfalto texturizado, faixas amarelas/brancas, calcadas e faixas de pedestre
## - Predios arquitetonicos com janelas espelhadas, telhados, Hospital (Cruz Vermelha),
##   Delegacia (faixa azul), Torres Corporativas, Predios de Tijolo e Residenciais
## - Pinheiros e arvores (buildTree) + Postes com braco e luminaria + Caixas de Suprimento [E]

signal map_loaded(summary: String)

var roads: Array = []        # { "name": String, "points": Array[Vector3] }
var buildings: Array = []    # { "center": Vector3, "size": Vector2, "height": float, "kind": String }
var streetlights: Array[OmniLight3D] = []
var loot_crates: Array[Node3D] = []

var _city_root: Node3D
var _http: HTTPRequest
var _is_loading: bool = false
var _origin_lat: float = -23.5614
var _origin_lng: float = -46.6559


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 22.0
	add_child(_http)
	_http.request_completed.connect(_on_overpass_completed)
	build_fallback_city(240.0)


func load_real_city(lat: float, lng: float, area_km2: float = 1.0) -> void:
	if _is_loading:
		return
	_is_loading = true
	_origin_lat = lat
	_origin_lng = lng
	var km2: float = clampf(area_km2, 0.25, 4.0)
	var half_m: float = sqrt(km2) * 500.0
	var d_lat: float = half_m / 111320.0
	var d_lng: float = half_m / (111320.0 * maxf(0.1, cos(deg_to_rad(lat))))

	var s: String = "%.6f" % (lat - d_lat)
	var w: String = "%.6f" % (lng - d_lng)
	var n: String = "%.6f" % (lat + d_lat)
	var e: String = "%.6f" % (lng + d_lng)

	var query: String = "[out:json][timeout:18];(way[\"highway\"](%s,%s,%s,%s);way[\"building\"](%s,%s,%s,%s););out body;>;out skel qt;" % [s, w, n, e, s, w, n, e]
	var url: String = "https://overpass-api.de/api/interpreter?data=" + query.uri_encode()
	var err: Error = _http.request(url)
	if err != OK:
		_is_loading = false
		build_fallback_city(half_m)
		map_loaded.emit("Offline — cidade Knox local gerada")


func _on_overpass_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_loading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		build_fallback_city(260.0)
		map_loaded.emit("OSM indisponivel — cidade Knox local gerada")
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("elements"):
		build_fallback_city(260.0)
		map_loaded.emit("Dados OSM vazios — cidade Knox local gerada")
		return

	_clear_city()
	var elements: Array = parsed["elements"]
	var nodes_map: Dictionary = {}
	var cos_lat: float = maxf(0.1, cos(deg_to_rad(_origin_lat)))

	for el in elements:
		if typeof(el) != TYPE_DICTIONARY:
			continue
		if str(el.get("type", "")) == "node":
			var nid: int = int(el.get("id", 0))
			var nlat: float = float(el.get("lat", 0.0))
			var nlon: float = float(el.get("lon", 0.0))
			var wx: float = (nlon - _origin_lng) * 111320.0 * cos_lat
			var wz: float = -((nlat - _origin_lat) * 111320.0)
			nodes_map[nid] = Vector3(wx, 0.03, wz)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(_origin_lat * 10000.0 + _origin_lng * 10000.0))

	for el in elements:
		if typeof(el) != TYPE_DICTIONARY or str(el.get("type", "")) != "way":
			continue
		var tags: Dictionary = el.get("tags", {}) if typeof(el.get("tags", {})) == TYPE_DICTIONARY else {}
		var node_ids: Array = el.get("nodes", []) if typeof(el.get("nodes", [])) == TYPE_ARRAY else []
		var pts: Array[Vector3] = []
		for nid_v in node_ids:
			var nid: int = int(nid_v)
			if nodes_map.has(nid):
				pts.append(nodes_map[nid])
		if pts.size() < 2:
			continue

		if tags.has("highway"):
			roads.append({ "name": str(tags.get("name", "Avenida Real")), "points": pts })
		elif tags.has("building") and pts.size() >= 3:
			var min_x: float = 999999.0
			var max_x: float = -999999.0
			var min_z: float = 999999.0
			var max_z: float = -999999.0
			for p in pts:
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
				min_z = minf(min_z, p.z)
				max_z = maxf(max_z, p.z)
			var sx: float = clampf(max_x - min_x, 6.0, 44.0)
			var sz: float = clampf(max_z - min_z, 6.0, 44.0)
			var levels: float = float(str(tags.get("building:levels", "0")).to_int())
			var h: float = levels * 3.4 if levels > 0.0 else rng.randf_range(7.5, 22.0)
			var bkind: String = _pick_building_kind(tags, rng)
			buildings.append({
				"center": Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5),
				"size": Vector2(sx, sz),
				"height": clampf(h, 6.0, 38.0),
				"kind": bkind
			})

	if roads.is_empty() and buildings.is_empty():
		build_fallback_city(260.0)
		map_loaded.emit("Area sem ruas OSM — cidade Knox local gerada")
		return

	_rebuild_geometry()
	map_loaded.emit("Mapa real carregado: %d ruas · %d predios" % [roads.size(), buildings.size()])


func _pick_building_kind(tags: Dictionary, rng: RandomNumberGenerator) -> String:
	var amen: String = str(tags.get("amenity", "")).to_lower()
	var bval: String = str(tags.get("building", "")).to_lower()
	if amen == "hospital" or bval == "hospital":
		return "hospital"
	if amen == "police":
		return "police"
	var r: float = rng.randf()
	if r < 0.08:
		return "hospital"
	if r < 0.14:
		return "police"
	if r < 0.42:
		return "corporate"
	if r < 0.72:
		return "brick"
	return "urban"


func build_fallback_city(half_m: float) -> void:
	_clear_city()
	var span: float = minf(half_m, 256.0)
	var step: float = 64.0
	var x: float = -span
	while x <= span:
		roads.append({
			"name": "Av. Knox N-S %.0f" % x,
			"points": [Vector3(x, 0.03, -span), Vector3(x, 0.03, span)]
		})
		x += step
	var z: float = -span
	while z <= span:
		roads.append({
			"name": "Rua Estadual %.0f" % z,
			"points": [Vector3(-span, 0.03, z), Vector3(span, 0.03, z)]
		})
		z += step

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var bx: float = -span + step * 0.5
	var idx: int = 0
	while bx < span:
		var bz: float = -span + step * 0.5
		while bz < span:
			if absf(bx) > 30.0 or absf(bz) > 30.0:
				var kind: String = "urban"
				if idx % 9 == 1:
					kind = "hospital"
				elif idx % 11 == 3:
					kind = "police"
				elif idx % 3 == 0:
					kind = "corporate"
				elif idx % 2 == 0:
					kind = "brick"
				buildings.append({
					"center": Vector3(bx, 0.0, bz),
					"size": Vector2(rng.randf_range(15.0, 24.0), rng.randf_range(14.0, 23.0)),
					"height": rng.randf_range(8.5, 22.0),
					"kind": kind
				})
				idx += 1
			bz += step
		bx += step

	_rebuild_geometry()


func _clear_city() -> void:
	roads.clear()
	buildings.clear()
	streetlights.clear()
	loot_crates.clear()
	if _city_root != null and is_instance_valid(_city_root):
		_city_root.queue_free()
	_city_root = Node3D.new()
	_city_root.name = "CityGeometry"
	add_child(_city_root)


func _rebuild_geometry() -> void:
	var asphalt_base: StandardMaterial3D = ProceduralTextures.get_asphalt_mat()
	var sidewalk_mat: StandardMaterial3D = ProceduralTextures.get_sidewalk_mat()
	var brick_mat: StandardMaterial3D = ProceduralTextures.get_brick_mat()
	var modern_mat: StandardMaterial3D = ProceduralTextures.get_modern_panel_mat()
	var glass_mat: StandardMaterial3D = ProceduralTextures.get_facade_glass_mat()
	var stucco_warm: StandardMaterial3D = ProceduralTextures.get_stucco_mat("warm", Color.html("#d8cebc"))
	var stucco_hosp: StandardMaterial3D = ProceduralTextures.get_stucco_mat("hosp", Color.html("#dce2e6"))
	var tile_roof: StandardMaterial3D = ProceduralTextures.get_tile_roof_mat()

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color.html("#22262a")
	pole_mat.metallic = 0.55
	pole_mat.roughness = 0.50

	var crosswalk_mat := StandardMaterial3D.new()
	crosswalk_mat.albedo_color = Color(0.88, 0.88, 0.85)
	crosswalk_mat.roughness = 0.88

	var dark_trim := StandardMaterial3D.new()
	dark_trim.albedo_color = Color.html("#262b30")
	dark_trim.roughness = 0.65

	var red_cross_mat := StandardMaterial3D.new()
	red_cross_mat.albedo_color = Color.html("#c42020")
	red_cross_mat.roughness = 0.45

	var police_blue_mat := StandardMaterial3D.new()
	police_blue_mat.albedo_color = Color.html("#1e4682")
	police_blue_mat.roughness = 0.42

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color.html("#4a3625")
	trunk_mat.roughness = 0.94

	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color.html("#223a22")
	pine_mat.roughness = 0.92

	var oak_mat := StandardMaterial3D.new()
	oak_mat.albedo_color = Color.html("#324c28")
	oak_mat.roughness = 0.90

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# 1. RUAS ASFALTADAS COM FAIXAS + CALCADAS + FAIXAS DE PEDESTRE + POSTES
	var lamp_count: int = 0
	var tree_count: int = 0
	for road in roads:
		var pts: Array = road["points"]
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var diff: Vector3 = b - a
			var length: float = diff.length()
			if length < 1.5:
				continue
			var flat_dir: Vector3 = Vector3(diff.x, 0.0, diff.z)
			if flat_dir.length_squared() < 0.0001:
				continue
			var dir_n: Vector3 = flat_dir.normalized()
			var basis_r := Basis.looking_at(dir_n, Vector3.UP)
			var mid: Vector3 = (a + b) * 0.5

			# Pista de asfalto com textura repetida ao longo do comprimento
			var road_mat: StandardMaterial3D = asphalt_base.duplicate()
			road_mat.uv1_scale = Vector3(1.0, maxf(1.0, length / 12.0), 1.0)
			var seg := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(8.4, length + 0.6)
			seg.mesh = pm
			seg.transform = Transform3D(basis_r, Vector3(mid.x, 0.015, mid.z))
			seg.material_override = road_mat
			_city_root.add_child(seg)

			# Calcadas rebaixadas nas laterais (meio-fio baixo para pneus nao afundarem!)
			var right_v: Vector3 = basis_r.x
			for side in [-1.0, 1.0]:
				var sw := MeshInstance3D.new()
				var swm := BoxMesh.new()
				swm.size = Vector3(2.2, 0.04, length)
				sw.mesh = swm
				sw.transform = Transform3D(basis_r, Vector3(mid.x, 0.02, mid.z) + right_v * (side * 5.3))
				sw.material_override = sidewalk_mat
				_city_root.add_child(sw)

			# Faixa de pedestre proxima ao inicio de segmentos longos
			if length > 24.0:
				for st_i in range(-3, 4):
					var stripe := MeshInstance3D.new()
					var sm := BoxMesh.new()
					sm.size = Vector3(0.55, 0.012, 2.8)
					stripe.mesh = sm
					var cw_pos: Vector3 = a + dir_n * 7.5 + right_v * (float(st_i) * 1.05)
					stripe.transform = Transform3D(basis_r, Vector3(cw_pos.x, 0.022, cw_pos.z))
					stripe.material_override = crosswalk_mat
					_city_root.add_child(stripe)

			# Postes de iluminacao realistas com braco + luminaria
			if lamp_count < 42 and length > 22.0:
				var num_lamps: int = mini(3, int(length / 44.0))
				for li in range(maxi(1, num_lamps)):
					if lamp_count >= 42:
						break
					lamp_count += 1
					var frac: float = (float(li) + 0.5) / float(maxi(1, num_lamps))
					var side_s: float = 1.0 if (lamp_count % 2 == 0) else -1.0
					var p_base: Vector3 = a.lerp(b, frac) + right_v * (side_s * 4.8)
					p_base.y = 0.0
					_spawn_streetlamp(p_base, -right_v * side_s, pole_mat)

			# Pinheiros / Arvores ao longo das calcadas (igual ao print!)
			if tree_count < 95 and length > 26.0:
				var t_slots: int = mini(4, int(length / 36.0))
				for ti in range(t_slots):
					if tree_count >= 95:
						break
					var frac_t: float = rng.randf_range(0.12, 0.88)
					var side_t: float = 1.0 if rng.randf() > 0.5 else -1.0
					var t_pos: Vector3 = a.lerp(b, frac_t) + right_v * (side_t * rng.randf_range(7.2, 11.5))
					t_pos.y = 0.0
					if t_pos.length() > 12.0:
						tree_count += 1
						_spawn_tree(t_pos, rng, trunk_mat, pine_mat, oak_mat)

	# 2. PREDIOS ARQUITETONICOS COM JANELAS, CORNICHAS, TELHADOS E MARCOS (HOSPITAL / POLICIA)
	var max_b: int = mini(buildings.size(), 340)
	for i in range(max_b):
		var bd: Dictionary = buildings[i]
		var sz: Vector2 = bd["size"]
		var h: float = bd["height"]
		var c: Vector3 = bd["center"]
		var kind: String = str(bd.get("kind", "urban"))
		_spawn_architectural_building(c, sz, h, kind, brick_mat, modern_mat, stucco_warm, stucco_hosp, glass_mat, tile_roof, dark_trim, red_cross_mat, police_blue_mat)

	# 3. CAIXAS DE SUPRIMENTOS (LOOT COLETAVEL COM [E])
	var crate_positions: Array[Vector3] = [
		Vector3(3.5, 0.0, -14.0), Vector3(-12.0, 0.0, -24.0),
		Vector3(24.0, 0.0, 12.0), Vector3(-28.0, 0.0, 26.0),
		Vector3(64.0, 0.0, -18.0), Vector3(-64.0, 0.0, 18.0),
		Vector3(18.0, 0.0, -64.0), Vector3(-18.0, 0.0, 64.0)
	]
	for cp in crate_positions:
		_spawn_loot_crate(cp)

	# 4. ROCHAS 3D REAIS DO PACK TERRAIN3D (RockA / RockB / RockC espalhadas nas areas verdes)
	_spawn_terrain_rocks(rng)


func _spawn_terrain_rocks(rng: RandomNumberGenerator) -> void:
	var rock_paths: PackedStringArray = [
		"res://demo/assets/models/RockA.tscn",
		"res://demo/assets/models/RockC.tscn",
		"res://demo/assets/models/RockB.glb"
	]
	var loaded_rocks: Array[PackedScene] = []
	for rp in rock_paths:
		if ResourceLoader.exists(rp):
			var r := ResourceLoader.load(rp)
			if r is PackedScene:
				loaded_rocks.append(r as PackedScene)
	if loaded_rocks.is_empty():
		return

	var placed: int = 0
	var tries: int = 0
	while placed < 34 and tries < 140:
		tries += 1
		var rx: float = rng.randf_range(-210.0, 210.0)
		var rz: float = rng.randf_range(-210.0, 210.0)
		# Evita ruas principais (grade a cada 64m) e centro de spawn
		if Vector2(rx, rz).length() < 18.0:
			continue
		var mod_x: float = absf(fposmod(rx + 32.0, 64.0) - 32.0)
		var mod_z: float = absf(fposmod(rz + 32.0, 64.0) - 32.0)
		if mod_x < 10.5 or mod_z < 10.5:
			continue
		var ps: PackedScene = loaded_rocks[rng.randi() % loaded_rocks.size()]
		var rock := ps.instantiate()
		if rock is Node3D:
			var rn := rock as Node3D
			var sc: float = rng.randf_range(0.32, 0.78)
			rn.position = Vector3(rx, -0.35 * sc, rz)
			rn.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
			rn.scale = Vector3.ONE * sc
			_city_root.add_child(rn)
			placed += 1
		elif rock != null:
			rock.queue_free()


func _spawn_architectural_building(c: Vector3, sz: Vector2, h: float, kind: String, brick_m: Material, modern_m: Material, stucco_m: Material, hosp_m: Material, glass_m: Material, roof_m: Material, trim_m: Material, red_m: Material, blue_m: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = Vector3(c.x, 0.0, c.z)
	_city_root.add_child(sb)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(sz.x, h, sz.y)
	col.shape = shape
	col.position = Vector3(0.0, h * 0.5, 0.0)
	sb.add_child(col)

	var wall_m: Material = stucco_m
	if kind == "hospital":
		wall_m = hosp_m
	elif kind == "corporate":
		wall_m = modern_m
	elif kind == "brick":
		wall_m = brick_m

	# Corpo principal do predio
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sz.x, h, sz.y)
	body.mesh = bm
	body.position = Vector3(0.0, h * 0.5, 0.0)
	body.material_override = wall_m
	sb.add_child(body)

	# Faixas de janelas espelhadas por andar (efeito realista sem pesar Draw Calls!)
	var floors: int = clampi(int(h / 3.4), 2, 7)
	for f in range(1, floors):
		var wy: float = float(f) * 3.3 + 0.5
		if wy + 0.9 >= h:
			break
		var w_band := MeshInstance3D.new()
		var wbm := BoxMesh.new()
		wbm.size = Vector3(sz.x + 0.14, 1.55, sz.y - 1.2)
		w_band.mesh = wbm
		w_band.position = Vector3(0.0, wy, 0.0)
		w_band.material_override = glass_m
		sb.add_child(w_band)

		var w_band2 := MeshInstance3D.new()
		var wbm2 := BoxMesh.new()
		wbm2.size = Vector3(sz.x - 1.2, 1.55, sz.y + 0.14)
		w_band2.mesh = wbm2
		w_band2.position = Vector3(0.0, wy, 0.0)
		w_band2.material_override = glass_m
		sb.add_child(w_band2)

	# Base / Rodape escuro + Cornija no topo
	var plinth := MeshInstance3D.new()
	var plm := BoxMesh.new()
	plm.size = Vector3(sz.x + 0.25, 0.65, sz.y + 0.25)
	plinth.mesh = plm
	plinth.position = Vector3(0.0, 0.32, 0.0)
	plinth.material_override = trim_m
	sb.add_child(plinth)

	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(sz.x + 0.45, 0.55, sz.y + 0.45)
	cap.mesh = cm
	cap.position = Vector3(0.0, h + 0.22, 0.0)
	cap.material_override = roof_m if kind == "brick" else trim_m
	sb.add_child(cap)

	# Equipamento de teto (caixa d'agua / ar-condicionado)
	var ac := MeshInstance3D.new()
	var acm := BoxMesh.new()
	acm.size = Vector3(minf(3.2, sz.x * 0.28), 1.4, minf(3.2, sz.y * 0.28))
	ac.mesh = acm
	ac.position = Vector3(sz.x * 0.18, h + 1.1, -sz.y * 0.14)
	ac.material_override = trim_m
	sb.add_child(ac)

	# Cruz Vermelha no Hospital (igual ao print original!)
	if kind == "hospital":
		var cy: float = h - 1.7
		for z_s in [-1.0, 1.0]:
			var ch := MeshInstance3D.new()
			var chm := BoxMesh.new()
			chm.size = Vector3(2.4, 0.65, 0.14)
			ch.mesh = chm
			ch.position = Vector3(0.0, cy, z_s * (sz.y * 0.5 + 0.08))
			ch.material_override = red_m
			sb.add_child(ch)

			var cv := MeshInstance3D.new()
			var cvm := BoxMesh.new()
			cvm.size = Vector3(0.65, 2.4, 0.14)
			cv.mesh = cvm
			cv.position = Vector3(0.0, cy, z_s * (sz.y * 0.5 + 0.08))
			cv.material_override = red_m
			sb.add_child(cv)
	elif kind == "police":
		var band := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(sz.x + 0.28, 0.85, sz.y + 0.28)
		band.mesh = pbm
		band.position = Vector3(0.0, h - 0.8, 0.0)
		band.material_override = blue_m
		sb.add_child(band)


func _spawn_tree(pos: Vector3, rng: RandomNumberGenerator, trunk_m: Material, pine_m: Material, oak_m: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var sc: float = rng.randf_range(0.88, 1.42)
	sb.scale = Vector3.ONE * sc
	_city_root.add_child(sb)

	var col := CollisionShape3D.new()
	var csh := CylinderShape3D.new()
	csh.radius = 0.28
	csh.height = 2.6
	col.shape = csh
	col.position = Vector3(0.0, 1.3, 0.0)
	sb.add_child(col)

	var tr := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.16
	tm.bottom_radius = 0.26
	tm.height = 2.4
	tm.radial_segments = 8
	tr.mesh = tm
	tr.position = Vector3(0.0, 1.2, 0.0)
	tr.material_override = trunk_m
	sb.add_child(tr)

	if rng.randf() < 0.68:
		# Pinheiro classico de 3 camadas (igual ao print!)
		for ci in range(3):
			var cn := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 1.65 - float(ci) * 0.34
			cm.height = 2.05
			cm.radial_segments = 8
			cn.mesh = cm
			cn.position = Vector3(0.0, 2.75 + float(ci) * 1.25, 0.0)
			cn.material_override = pine_m
			sb.add_child(cn)
	else:
		var cr := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.75
		sm.height = 3.2
		sm.radial_segments = 8
		sm.rings = 5
		cr.mesh = sm
		cr.position = Vector3(0.0, 3.6, 0.0)
		cr.material_override = oak_m
		sb.add_child(cr)


func _spawn_streetlamp(pos: Vector3, arm_dir: Vector3, pole_m: Material) -> void:
	var root := Node3D.new()
	root.position = pos
	_city_root.add_child(root)

	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.11
	pm.height = 6.4
	pm.radial_segments = 8
	pole.mesh = pm
	pole.position = Vector3(0.0, 3.2, 0.0)
	pole.material_override = pole_m
	root.add_child(pole)

	var arm_n: Vector3 = Vector3(arm_dir.x, 0.0, arm_dir.z).normalized()
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.08, 0.08, 1.8)
	arm.mesh = am
	var basis_a := Basis.looking_at(arm_n, Vector3.UP)
	arm.transform = Transform3D(basis_a, Vector3(0.0, 6.3, 0.0) + arm_n * 0.85)
	arm.material_override = pole_m
	root.add_child(arm)

	var bulb_pos: Vector3 = Vector3(0.0, 6.18, 0.0) + arm_n * 1.65
	var bulb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.10, 0.42)
	bulb.mesh = bm
	bulb.position = bulb_pos
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.90, 0.65)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.85, 0.52)
	bmat.emission_energy_multiplier = 1.4
	bulb.material_override = bmat
	root.add_child(bulb)

	var light := OmniLight3D.new()
	light.position = bulb_pos + Vector3(0.0, -0.25, 0.0)
	light.light_color = Color(1.0, 0.84, 0.56)
	light.light_energy = 4.2
	light.omni_range = 22.0
	light.shadow_enabled = false
	light.visible = false
	root.add_child(light)
	streetlights.append(light)


func _spawn_loot_crate(pos: Vector3) -> void:
	var crate := Node3D.new()
	crate.position = pos + Vector3(0.0, 0.28, 0.0)
	_city_root.add_child(crate)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.72, 0.46, 0.52)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html("#3d4d2c")
	mat.roughness = 0.72
	mi.material_override = mat
	crate.add_child(mi)

	var band := MeshInstance3D.new()
	var bdm := BoxMesh.new()
	bdm.size = Vector3(0.75, 0.10, 0.55)
	band.mesh = bdm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color.html("#d4a238")
	bmat.emission_enabled = true
	bmat.emission = Color.html("#d4a238")
	bmat.emission_energy_multiplier = 0.7
	band.material_override = bmat
	crate.add_child(band)

	loot_crates.append(crate)


func set_night_streetlights(enabled: bool) -> void:
	for l in streetlights:
		if is_instance_valid(l):
			l.visible = enabled
