extends RefCounted
class_name ProceduralTextures

## Gerador de texturas procedurais 1:1 portadas do Knox Survival 3D (Web -> Godot 4).
## Cria texturas de grama, asfalto com faixas, calcada, tijolo, estuque, vidro espelhado,
## telhado, jaqueta xadrez vinho (Omni), camisa, rosto humano e rosto de zumbi.

static var _cache: Dictionary = {}


static func _make_tex(key: String, w: int, h: int, draw_fn: Callable) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	draw_fn.call(img, w, h)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _make_mat(key: String, tex: Texture2D, rough: float = 0.9, metal: float = 0.0, triplanar: bool = false, uv_scale: Vector3 = Vector3.ONE, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var mkey := "mat_" + key
	if _cache.has(mkey):
		return _cache[mkey]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	m.uv1_scale = uv_scale
	_cache[mkey] = m
	return m


static func get_grass_mat() -> StandardMaterial3D:
	if _cache.has("mat_grass_pbr"):
		return _cache["mat_grass_pbr"]
	var alb_path: String = "res://demo/assets/textures/ground037_alb_ht.png"
	var nrm_path: String = "res://demo/assets/textures/ground037_nrm_rgh.png"
	if ResourceLoader.exists(alb_path):
		var alb := ResourceLoader.load(alb_path)
		if alb is Texture2D:
			var m := StandardMaterial3D.new()
			m.albedo_texture = alb as Texture2D
			m.albedo_color = Color.html("#9eb08a")
			m.roughness = 0.92
			m.uv1_scale = Vector3(175.0, 175.0, 1.0)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if ResourceLoader.exists(nrm_path):
				var nrm := ResourceLoader.load(nrm_path)
				if nrm is Texture2D:
					m.normal_enabled = true
					m.normal_texture = nrm as Texture2D
					m.normal_scale = 0.65
			_cache["mat_grass_pbr"] = m
			return m

	var tex := _make_tex("grass", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#3c472f"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 101
		for _i in range(2200):
			var r: float = rng.randf()
			var c: Color = Color.html("#313b26") if r < 0.35 else (Color.html("#475338") if r < 0.78 else Color.html("#564e3a"))
			img.fill_rect(Rect2i(rng.randi_range(0, w - 2), rng.randi_range(0, h - 2), 2, 2), c)
	)
	return _make_mat("grass", tex, 0.96, 0.0, false, Vector3(240.0, 240.0, 1.0))


static func get_asphalt_mat() -> StandardMaterial3D:
	var tex := _make_tex("asphalt", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#252729"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 202
		for _i in range(2200):
			var g: float = float(28 + rng.randi_range(0, 22)) / 255.0
			img.fill_rect(Rect2i(rng.randi_range(0, w - 2), rng.randi_range(0, h - 2), 2, 2), Color(g, g, g + 0.008))
		# Faixas brancas laterais
		img.fill_rect(Rect2i(6, 0, 3, h), Color(0.84, 0.84, 0.80, 0.85))
		img.fill_rect(Rect2i(w - 9, 0, 3, h), Color(0.84, 0.84, 0.80, 0.85))
		# Faixa amarela central tracejada
		img.fill_rect(Rect2i(w / 2 - 2, 10, 4, 48), Color(0.90, 0.74, 0.22, 0.92))
		img.fill_rect(Rect2i(w / 2 - 2, 74, 4, 44), Color(0.90, 0.74, 0.22, 0.92))
	)
	return _make_mat("asphalt", tex, 0.90, 0.0, false, Vector3(1.0, 1.0, 1.0))


static func get_sidewalk_mat() -> StandardMaterial3D:
	var tex := _make_tex("sidewalk", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#8b8b84"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 303
		for _i in range(1400):
			var g: float = float(118 + rng.randi_range(0, 30)) / 255.0
			img.fill_rect(Rect2i(rng.randi_range(0, w - 2), rng.randi_range(0, h - 2), 2, 2), Color(g, g, g - 0.02))
		var line_c := Color(0.28, 0.29, 0.27)
		for p in range(0, w, 32):
			img.fill_rect(Rect2i(0, p, w, 2), line_c)
			img.fill_rect(Rect2i(p, 0, 2, h), line_c)
	)
	return _make_mat("sidewalk", tex, 0.88, 0.0, true, Vector3(0.35, 0.35, 0.35))


static func get_brick_mat() -> StandardMaterial3D:
	var tex := _make_tex("brick", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#857d73"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 404
		for r in range(8):
			var off: int = (r % 2) * 16
			for c in range(-1, 5):
				var d: int = rng.randi_range(-10, 10)
				var col := Color(float(124 + d) / 255.0, float(62 + d / 2) / 255.0, float(50 + d / 2) / 255.0)
				var bx: int = maxi(0, c * 32 + off + 2)
				var bx2: int = mini(w, c * 32 + off + 30)
				if bx2 > bx:
					img.fill_rect(Rect2i(bx, r * 16 + 2, bx2 - bx, 12), col)
	)
	return _make_mat("brick", tex, 0.90, 0.02, true, Vector3(0.38, 0.38, 0.38))


static func get_stucco_mat(variant_key: String = "warm", tint: Color = Color.html("#d8cebc")) -> StandardMaterial3D:
	var tex := _make_tex("stucco", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#ddd9cf"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 505
		for _i in range(1800):
			var v: float = float(205 + rng.randi_range(0, 26)) / 255.0
			img.fill_rect(Rect2i(rng.randi_range(0, w - 2), rng.randi_range(0, h - 2), 2, 2), Color(v, v - 0.01, v - 0.025))
		img.fill_rect(Rect2i(0, h - 2, w, 2), Color(0.55, 0.54, 0.50))
	)
	return _make_mat("stucco_" + variant_key, tex, 0.86, 0.04, true, Vector3(0.30, 0.30, 0.30), tint)


static func get_modern_panel_mat() -> StandardMaterial3D:
	var tex := _make_tex("modern_panel", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#7c8995"))
		for r in range(4):
			for c in range(2):
				var shade: float = float(168 + ((r + c) % 2) * 14) / 255.0
				img.fill_rect(Rect2i(c * 64 + 2, r * 32 + 2, 60, 28), Color(shade, shade + 0.02, shade + 0.04))
				img.fill_rect(Rect2i(c * 64, r * 32, 64, 2), Color(0.16, 0.20, 0.24))
				img.fill_rect(Rect2i(c * 64, r * 32, 2, 32), Color(0.16, 0.20, 0.24))
	)
	return _make_mat("modern_panel", tex, 0.44, 0.32, true, Vector3(0.28, 0.28, 0.28))


static func get_facade_glass_mat() -> StandardMaterial3D:
	var tex := _make_tex("facade_glass", 128, 128, func(img: Image, w: int, h: int) -> void:
		for y in range(h):
			var t: float = float(y) / float(h)
			var c: Color = Color.html("#3a5970").lerp(Color.html("#527892"), 1.0 - absf(t * 2.0 - 1.0))
			img.fill_rect(Rect2i(0, y, w, 1), c)
		# Reflexo diagonal sutil do ceu
		for d in range(56):
			img.fill_rect(Rect2i(0, d, 56 - d, 1), Color(0.68, 0.82, 0.92, 1.0))
		# Caixilhos metalicos
		for x in range(0, w, 32):
			img.fill_rect(Rect2i(x, 0, 3, h), Color.html("#1f2830"))
		for y in range(0, h, 64):
			img.fill_rect(Rect2i(0, y, w, 4), Color.html("#1f2830"))
	)
	return _make_mat("facade_glass", tex, 0.18, 0.58, true, Vector3(0.32, 0.32, 0.32))


static func get_tile_roof_mat() -> StandardMaterial3D:
	var tex := _make_tex("tile_roof", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#8b3d24"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 606
		for r in range(8):
			for c in range(8):
				var d: int = rng.randi_range(-10, 10)
				img.fill_rect(Rect2i(c * 16 + 1, r * 16 + 1, 14, 13), Color(float(156 + d) / 255.0, float(74 + d / 2) / 255.0, float(46 + d / 2) / 255.0))
				img.fill_rect(Rect2i(c * 16, r * 16 + 14, 16, 2), Color(0.25, 0.10, 0.06))
	)
	return _make_mat("tile_roof", tex, 0.85, 0.0, true, Vector3(0.45, 0.45, 0.45))


static func get_omni_jacket_mat() -> StandardMaterial3D:
	var tex := _make_tex("omni_jacket", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#200f22"))
		for i in range(0, w, 24):
			img.fill_rect(Rect2i(i, 0, 11, h), Color.html("#341838"))
			img.fill_rect(Rect2i(0, i, w, 11), Color.html("#341838"))
			img.fill_rect(Rect2i(i + 4, 0, 2, h), Color.html("#4c2352"))
			img.fill_rect(Rect2i(0, i + 4, w, 2), Color.html("#4c2352"))
			img.fill_rect(Rect2i(i + 14, 0, 5, h), Color.html("#130816"))
			img.fill_rect(Rect2i(0, i + 14, w, 5), Color.html("#130816"))
	)
	return _make_mat("omni_jacket", tex, 0.88, 0.0)


static func get_omni_shirt_mat() -> StandardMaterial3D:
	var tex := _make_tex("omni_shirt", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#a8a5aa"))
		for i in range(6, w, 18):
			img.fill_rect(Rect2i(i, 0, 6, h), Color.html("#8e8a92"))
			img.fill_rect(Rect2i(0, i, w, 6), Color.html("#8e8a92"))
		img.fill_rect(Rect2i(w / 2 - 4, 8, 8, h - 16), Color.html("#bab7bc"))
		for by in range(22, h - 18, 22):
			img.fill_rect(Rect2i(w / 2 - 2, by, 4, 4), Color.html("#ece9ee"))
	)
	return _make_mat("omni_shirt", tex, 0.84, 0.0)


static func get_omni_face_mat() -> StandardMaterial3D:
	var tex := _make_tex("omni_face", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#c89679"))
		# Sobrancelhas
		img.fill_rect(Rect2i(22, 32, 26, 5), Color.html("#583c2e"))
		img.fill_rect(Rect2i(w - 48, 32, 26, 5), Color.html("#583c2e"))
		# Sombras dos olhos
		img.fill_rect(Rect2i(22, 38, 28, 12), Color.html("#8f624c"))
		img.fill_rect(Rect2i(w - 50, 38, 28, 12), Color.html("#8f624c"))
		# Bigode / cavanhaque leve estilo sobrevivente
		img.fill_rect(Rect2i(40, 84, 48, 7), Color.html("#5a3b2c"))
		img.fill_rect(Rect2i(46, 94, 36, 4), Color.html("#5c3326"))
		img.fill_rect(Rect2i(50, 102, 28, 10), Color.html("#5a3b2c"))
	)
	return _make_mat("omni_face", tex, 0.74, 0.0)


static func get_zombie_face_mat() -> StandardMaterial3D:
	var tex := _make_tex("zombie_face", 128, 128, func(img: Image, w: int, h: int) -> void:
		img.fill(Color.html("#6f7c63"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 909
		for _i in range(45):
			var col: Color = Color.html("#4a201c") if rng.randi() % 3 == 0 else Color.html("#424b3a")
			img.fill_rect(Rect2i(rng.randi_range(0, w - 10), rng.randi_range(0, h - 10), 8, 8), col)
		# Olheiras fundas e olhos palidos
		img.fill_rect(Rect2i(20, 32, 30, 18), Color.html("#1b1d18"))
		img.fill_rect(Rect2i(w - 50, 32, 30, 18), Color.html("#1b1d18"))
		img.fill_rect(Rect2i(31, 38, 8, 8), Color.html("#c8cc9c"))
		img.fill_rect(Rect2i(w - 39, 38, 8, 8), Color.html("#c8cc9c"))
		img.fill_rect(Rect2i(34, 41, 3, 3), Color.html("#241816"))
		img.fill_rect(Rect2i(w - 36, 41, 3, 3), Color.html("#241816"))
		# Boca ensanguentada e dentes
		img.fill_rect(Rect2i(36, 82, 56, 20), Color.html("#3c100e"))
		img.fill_rect(Rect2i(42, 86, 44, 12), Color.html("#180606"))
		for tx in range(44, 84, 8):
			img.fill_rect(Rect2i(tx, 84, 4, 5), Color.html("#c4b898"))
			img.fill_rect(Rect2i(tx, 94, 4, 5), Color.html("#c4b898"))
		img.fill_rect(Rect2i(46, 102, 36, 18), Color.html("#6e1210"))
	)
	return _make_mat("zombie_face", tex, 0.84, 0.0)


static func get_chrome_mat() -> StandardMaterial3D:
	if _cache.has("mat_chrome"):
		return _cache["mat_chrome"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.80, 0.83, 0.86)
	m.metallic = 0.88
	m.roughness = 0.22
	_cache["mat_chrome"] = m
	return m


static func get_car_glass_mat() -> StandardMaterial3D:
	if _cache.has("mat_car_glass"):
		return _cache["mat_car_glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.72, 0.82, 0.34)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.10
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["mat_car_glass"] = m
	return m
