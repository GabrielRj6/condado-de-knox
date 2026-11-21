extends Node3D
class_name RealWorldMapLoader

## Carregador assincrono de cidades reais (OpenStreetMap / Overpass API) em Godot 4.
## Constroi ruas, predios com colisao StaticBody3D e postes de luz (Forward+ sem travar a noite!).
## Inclui geracao instantanea de quarteiroes urbanos caso esteja offline.

signal map_loaded(summary: String)

var roads: Array = []      # Array de { "name": String, "points": Array[Vector3] }
var buildings: Array = []  # Array de { "center": Vector3, "size": Vector2, "height": float }
var streetlights: Array[OmniLight3D] = []

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
		map_loaded.emit("Offline — cidade local gerada")


func _on_overpass_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_loading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		build_fallback_city(260.0)
		map_loaded.emit("OSM indisponivel — cidade local gerada")
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("elements"):
		build_fallback_city(260.0)
		map_loaded.emit("Dados OSM vazios — cidade local gerada")
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
			nodes_map[nid] = Vector3(wx, 0.05, wz)

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
			roads.append({ "name": str(tags.get("name", "Via Real")), "points": pts })
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
			var sx: float = clampf(max_x - min_x, 4.0, 52.0)
			var sz: float = clampf(max_z - min_z, 4.0, 52.0)
			var levels: float = float(str(tags.get("building:levels", "0")).to_int())
			var h: float = levels * 3.4 if levels > 0.0 else rng.randf_range(7.0, 22.0)
			buildings.append({
				"center": Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5),
				"size": Vector2(sx, sz),
				"height": clampf(h, 5.0, 42.0)
			})

	if roads.is_empty() and buildings.is_empty():
		build_fallback_city(260.0)
		map_loaded.emit("Area sem ruas OSM — cidade local gerada")
		return

	_rebuild_geometry()
	map_loaded.emit("Mapa real carregado: %d ruas · %d predios" % [roads.size(), buildings.size()])


func build_fallback_city(half_m: float) -> void:
	_clear_city()
	var span: float = minf(half_m, 260.0)
	var step: float = 64.0
	var x: float = -span
	while x <= span:
		roads.append({
			"name": "Av. N-S %.0f" % x,
			"points": [Vector3(x, 0.05, -span), Vector3(x, 0.05, span)]
		})
		x += step
	var z: float = -span
	while z <= span:
		roads.append({
			"name": "Rua L-O %.0f" % z,
			"points": [Vector3(-span, 0.05, z), Vector3(span, 0.05, z)]
		})
		z += step

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var bx: float = -span + step * 0.5
	while bx < span:
		var bz: float = -span + step * 0.5
		while bz < span:
			if absf(bx) > 36.0 or absf(bz) > 36.0:
				buildings.append({
					"center": Vector3(bx, 0.0, bz),
					"size": Vector2(rng.randf_range(14.0, 26.0), rng.randf_range(14.0, 26.0)),
					"height": rng.randf_range(7.0, 24.0)
				})
			bz += step
		bx += step

	_rebuild_geometry()


func _clear_city() -> void:
	roads.clear()
	buildings.clear()
	streetlights.clear()
	if _city_root != null and is_instance_valid(_city_root):
		_city_root.queue_free()
	_city_root = Node3D.new()
	_city_root.name = "CityGeometry"
	add_child(_city_root)


func _rebuild_geometry() -> void:
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.13, 0.13, 0.14)
	road_mat.roughness = 0.92

	var bld_mat := StandardMaterial3D.new()
	bld_mat.albedo_color = Color(0.34, 0.32, 0.30)
	bld_mat.roughness = 0.88

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.16, 0.17, 0.19)

	# Ruas + Postes de Luz (Forward+ suporta dezenas de luzes dinamicas a noite sem engasgar!)
	var lamp_count: int = 0
	for road in roads:
		var pts: Array = road["points"]
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var diff: Vector3 = b - a
			var length: float = diff.length()
			if length < 1.0:
				continue
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(7.6, 0.08, length + 0.5)
			seg.mesh = bm
			var flat_dir: Vector3 = Vector3(diff.x, 0.0, diff.z)
			if flat_dir.length_squared() > 0.0001:
				seg.transform = Transform3D(Basis.looking_at(flat_dir.normalized(), Vector3.UP), (a + b) * 0.5)
			else:
				seg.position = (a + b) * 0.5
			seg.material_override = road_mat
			_city_root.add_child(seg)

			# Postes espacados em vias principais (maximo 36 luzes ativas para FPS alto)
			if lamp_count < 36 and i % 2 == 0 and length > 18.0:
				lamp_count += 1
				var pole_pos: Vector3 = a.lerp(b, 0.5) + Vector3(4.5, 0.0, 0.0)
				var pole := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.09
				pm.bottom_radius = 0.12
				pm.height = 6.2
				pole.mesh = pm
				pole.position = pole_pos + Vector3(0.0, 3.1, 0.0)
				pole.material_override = pole_mat
				_city_root.add_child(pole)

				var light := OmniLight3D.new()
				light.position = pole_pos + Vector3(0.0, 6.0, 0.0)
				light.light_color = Color(1.0, 0.84, 0.56)
				light.light_energy = 4.0
				light.omni_range = 20.0
				light.shadow_enabled = false
				light.visible = false
				_city_root.add_child(light)
				streetlights.append(light)

	# Predios com colisao solida StaticBody3D
	var max_b: int = mini(buildings.size(), 420)
	for i in range(max_b):
		var bd: Dictionary = buildings[i]
		var sz: Vector2 = bd["size"]
		var h: float = bd["height"]
		var c: Vector3 = bd["center"]

		var sb := StaticBody3D.new()
		sb.position = Vector3(c.x, h * 0.5, c.z)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(sz.x, h, sz.y)
		col.shape = shape
		sb.add_child(col)

		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(sz.x, h, sz.y)
		mesh.mesh = box
		mesh.material_override = bld_mat
		sb.add_child(mesh)
		_city_root.add_child(sb)


func set_night_streetlights(enabled: bool) -> void:
	for l in streetlights:
		if is_instance_valid(l):
			l.visible = enabled
