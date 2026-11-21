extends RefCounted
class_name WeaponArsenal

## Arsenal REAL do Knox Survival 3D importado dos modelos 3D (.obj) e icones HUD (.png) do jogo!
## Coordenadas dos .obj da Forja 3D: +X = cano (muzzle), +Y = cima, +Z = direita, centro Y = 0.96.
## Rotacionando +90 graus em Y no Godot, o cano aponta exatamente para -Z (frente)!
## grip_offset posiciona a empunhadura exatamente na palma da mao direita do personagem.

const WEAPONS: Array[Dictionary] = [
	{
		"id": "kbar",
		"code": "K-BAR",
		"name": "FACA TATICA K-BAR",
		"cal": "MELEE · LAMINA",
		"melee": true,
		"two_hand": false,
		"auto": false,
		"dmg": 60.0,
		"pellets": 1,
		"spread": 0.0,
		"ads_spread": 0.0,
		"cooldown": 0.38,
		"mag_size": 0,
		"reload_time": 0.0,
		"range": 2.7,
		"recoil": 0.015,
		"ads_fov": 68.0,
		"sound": "pistol",
		"noise": 8.0,
		"mesh": "res://assets/weapons/kbar.obj",
		"icon": "res://assets/weapons/kbar_icon.png",
		"scale": 0.17,
		"color": Color(0.26, 0.28, 0.30),
		"muzzle_z": -0.22,
		"grip_offset": Vector3(0.0, 0.02, -0.08),
		"foregrip_offset": Vector3(-0.14, -0.02, -0.10)
	},
	{
		"id": "p9k",
		"code": "P9-K",
		"name": "PISTOLA P9-K 9MM",
		"cal": "9x19mm · SEMI",
		"melee": false,
		"two_hand": false,
		"auto": false,
		"dmg": 30.0,
		"pellets": 1,
		"spread": 0.014,
		"ads_spread": 0.0038,
		"cooldown": 0.17,
		"mag_size": 15,
		"reload_time": 1.4,
		"range": 145.0,
		"recoil": 0.022,
		"ads_fov": 58.0,
		"sound": "pistol",
		"noise": 85.0,
		"mesh": "res://assets/weapons/p9k.obj",
		"icon": "res://assets/weapons/p9k_icon.png",
		"scale": 0.18,
		"color": Color(0.18, 0.19, 0.21),
		"muzzle_z": -0.24,
		"grip_offset": Vector3(0.0, 0.04, -0.06),
		"foregrip_offset": Vector3(-0.02, -0.03, -0.03)
	},
	{
		"id": "mag44",
		"code": "MAG-44",
		"name": "REVOLVER MAG-44",
		"cal": ".44 MAGNUM · SEMI",
		"melee": false,
		"two_hand": false,
		"auto": false,
		"dmg": 68.0,
		"pellets": 1,
		"spread": 0.013,
		"ads_spread": 0.0028,
		"cooldown": 0.44,
		"mag_size": 6,
		"reload_time": 2.0,
		"range": 180.0,
		"recoil": 0.056,
		"ads_fov": 56.0,
		"sound": "rifle",
		"noise": 125.0,
		"mesh": "res://assets/weapons/mag44.obj",
		"icon": "res://assets/weapons/mag44_icon.png",
		"scale": 0.20,
		"color": Color(0.46, 0.48, 0.50),
		"muzzle_z": -0.28,
		"grip_offset": Vector3(0.0, 0.04, -0.08),
		"foregrip_offset": Vector3(-0.02, -0.03, -0.04)
	},
	{
		"id": "vx9",
		"code": "VX-9",
		"name": "SMG VX-9 TATICA",
		"cal": "9mm · AUTO",
		"melee": false,
		"two_hand": true,
		"auto": true,
		"dmg": 25.0,
		"pellets": 1,
		"spread": 0.022,
		"ads_spread": 0.007,
		"cooldown": 0.075,
		"mag_size": 32,
		"reload_time": 1.65,
		"range": 150.0,
		"recoil": 0.016,
		"ads_fov": 55.0,
		"sound": "pistol",
		"noise": 92.0,
		"mesh": "res://assets/weapons/vx9.obj",
		"icon": "res://assets/weapons/vx9_icon.png",
		"scale": 0.24,
		"color": Color(0.19, 0.20, 0.22),
		"muzzle_z": -0.36,
		"grip_offset": Vector3(0.0, 0.03, -0.10),
		"foregrip_offset": Vector3(-0.02, -0.02, -0.24)
	},
	{
		"id": "sg12",
		"code": "SG-12",
		"name": "ESCOPETA SG-12",
		"cal": "12 GAUGE · PUMP",
		"melee": false,
		"two_hand": true,
		"auto": false,
		"dmg": 24.0,
		"pellets": 6,
		"spread": 0.052,
		"ads_spread": 0.032,
		"cooldown": 0.66,
		"mag_size": 8,
		"reload_time": 2.15,
		"range": 78.0,
		"recoil": 0.068,
		"ads_fov": 56.0,
		"sound": "rifle",
		"noise": 140.0,
		"mesh": "res://assets/weapons/sg12.obj",
		"icon": "res://assets/weapons/sg12_icon.png",
		"scale": 0.30,
		"color": Color(0.22, 0.23, 0.25),
		"muzzle_z": -0.52,
		"grip_offset": Vector3(0.0, 0.02, -0.12),
		"foregrip_offset": Vector3(-0.02, -0.02, -0.34)
	},
	{
		"id": "m41t",
		"code": "M41-T",
		"name": "FUZIL M41-T 5.56",
		"cal": "5.56 NATO · AUTO",
		"melee": false,
		"two_hand": true,
		"auto": true,
		"dmg": 36.0,
		"pellets": 1,
		"spread": 0.014,
		"ads_spread": 0.0032,
		"cooldown": 0.095,
		"mag_size": 30,
		"reload_time": 1.85,
		"range": 260.0,
		"recoil": 0.020,
		"ads_fov": 48.0,
		"sound": "rifle",
		"noise": 122.0,
		"mesh": "res://assets/weapons/m41t.obj",
		"icon": "res://assets/weapons/m41t_icon.png",
		"scale": 0.30,
		"color": Color(0.17, 0.18, 0.20),
		"muzzle_z": -0.54,
		"grip_offset": Vector3(0.0, 0.02, -0.12),
		"foregrip_offset": Vector3(-0.02, -0.02, -0.35)
	},
	{
		"id": "ak74m",
		"code": "AK-74M",
		"name": "RIFLE AK-74M",
		"cal": "7.62x39mm · AUTO",
		"melee": false,
		"two_hand": true,
		"auto": true,
		"dmg": 46.0,
		"pellets": 1,
		"spread": 0.019,
		"ads_spread": 0.0052,
		"cooldown": 0.118,
		"mag_size": 30,
		"reload_time": 2.05,
		"range": 270.0,
		"recoil": 0.030,
		"ads_fov": 50.0,
		"sound": "rifle",
		"noise": 135.0,
		"mesh": "res://assets/weapons/ak74m.obj",
		"icon": "res://assets/weapons/ak74m_icon.png",
		"scale": 0.31,
		"color": Color(0.28, 0.22, 0.17),
		"muzzle_z": -0.56,
		"grip_offset": Vector3(0.0, 0.02, -0.12),
		"foregrip_offset": Vector3(-0.02, -0.02, -0.36)
	},
	{
		"id": "sr76",
		"code": "SR-76",
		"name": "SNIPER SR-76 .50",
		"cal": ".50 BMG · BOLT",
		"melee": false,
		"two_hand": true,
		"auto": false,
		"dmg": 125.0,
		"pellets": 1,
		"spread": 0.016,
		"ads_spread": 0.0005,
		"cooldown": 1.05,
		"mag_size": 5,
		"reload_time": 2.55,
		"range": 500.0,
		"recoil": 0.082,
		"ads_fov": 20.0,
		"sound": "sniper",
		"noise": 185.0,
		"mesh": "res://assets/weapons/sr76.obj",
		"icon": "res://assets/weapons/sr76_icon.png",
		"scale": 0.34,
		"color": Color(0.22, 0.25, 0.21),
		"muzzle_z": -0.68,
		"grip_offset": Vector3(0.0, 0.02, -0.14),
		"foregrip_offset": Vector3(-0.02, -0.02, -0.40)
	},
	{
		"id": "katana",
		"code": "KAT-0",
		"name": "KATANA TATICA",
		"cal": "MELEE · KATANA",
		"melee": true,
		"two_hand": true,
		"auto": false,
		"dmg": 95.0,
		"pellets": 1,
		"spread": 0.0,
		"ads_spread": 0.0,
		"cooldown": 0.52,
		"mag_size": 0,
		"reload_time": 0.0,
		"range": 3.4,
		"recoil": 0.018,
		"ads_fov": 68.0,
		"sound": "pistol",
		"noise": 6.0,
		"mesh": "res://assets/weapons/katana.obj",
		"icon": "res://assets/weapons/katana_icon.png",
		"scale": 0.34,
		"color": Color(0.74, 0.78, 0.82),
		"muzzle_z": -0.48,
		"grip_offset": Vector3(0.0, 0.02, -0.22),
		"foregrip_offset": Vector3(-0.02, -0.03, -0.05)
	}
]

static var _mesh_cache: Dictionary = {}
static var _icon_cache: Dictionary = {}


static func get_weapon(idx: int) -> Dictionary:
	var clamped: int = clampi(idx, 0, WEAPONS.size() - 1)
	return WEAPONS[clamped]


static func get_weapon_icon(idx: int) -> Texture2D:
	var w: Dictionary = get_weapon(idx)
	var path: String = str(w["icon"])
	if _icon_cache.has(path):
		return _icon_cache[path]
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			_icon_cache[path] = res
			return res
	return null


static func build_weapon_node(idx: int, suppressed: bool = false, scale_mult: float = 1.0) -> Node3D:
	var w: Dictionary = get_weapon(idx)
	var root := Node3D.new()
	var sc: float = float(w["scale"]) * scale_mult
	var path: String = str(w["mesh"])
	var grip_off: Vector3 = (w["grip_offset"] as Vector3) * scale_mult

	var mi := MeshInstance3D.new()
	var loaded_mesh: Mesh = null
	if _mesh_cache.has(path):
		loaded_mesh = _mesh_cache[path]
	elif ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Mesh:
			loaded_mesh = res
			_mesh_cache[path] = res

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = w["color"]
	gun_mat.metallic = 0.64
	gun_mat.roughness = 0.32

	if loaded_mesh != null:
		mi.mesh = loaded_mesh
		mi.scale = Vector3.ONE * sc
		# +X do OBJ vira -Z (frente no Godot); compensa centro Y=0.96 e alinha a empunhadura no pivot
		mi.rotation.y = PI * 0.5
		mi.position = Vector3(grip_off.x, -0.96 * sc + grip_off.y, grip_off.z)
	else:
		var fallback := BoxMesh.new()
		fallback.size = Vector3(0.06, 0.11, 0.65 * scale_mult)
		mi.mesh = fallback
		mi.position = Vector3(0.0, 0.0, -0.25 * scale_mult)

	mi.material_override = gun_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)

	# Silenciador acoplavel na ponta do cano [X]
	if suppressed and not bool(w["melee"]):
		var sup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.019 * scale_mult
		cm.bottom_radius = 0.019 * scale_mult
		cm.height = 0.19 * scale_mult
		sup.mesh = cm
		sup.rotation.x = PI * 0.5
		sup.position = Vector3(grip_off.x, grip_off.y + 0.025 * scale_mult, grip_off.z + float(w["muzzle_z"]) * scale_mult - 0.06 * scale_mult)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.11, 0.12, 0.13)
		smat.metallic = 0.74
		smat.roughness = 0.28
		sup.material_override = smat
		root.add_child(sup)

	return root
