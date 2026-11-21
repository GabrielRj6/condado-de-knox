extends RefCounted
class_name AssetBridge

## Ponte integrada para os Assets da Godot Asset Store sincronizados no projeto:
## 1. Quaternius Universal Animation Library: res://Godot/AnimationLibrary_Godot_Standard.glb
##    (Rig 3D humanoide completo + todas as animacoes + BoneAttachment na mao direita e cabeca!)
## 2. Sound FX Starter Pack Vol. 1: res://Sound FX Starter Pack Vol. 1/
## 3. Terrain3D + Texturas PBR e Rochas 3D: res://addons/terrain_3d/ e res://demo/assets/
## 4. Pastas extras plug-and-play: res://assets/characters/, res://assets/animations/, res://assets/audio/

const QUATERNIUS_RIG_PATH: String = "res://Godot/AnimationLibrary_Godot_Standard.glb"
const SFX_PACK_ROOT: String = "res://Sound FX Starter Pack Vol. 1/"

const PLAYER_MODEL_CANDIDATES: PackedStringArray = [
	"res://assets/characters/player.glb",
	"res://assets/characters/survivor.glb",
	"res://assets/characters/swat.glb",
	"res://assets/characters/player.tscn",
	"res://assets/characters/survivor.tscn",
	QUATERNIUS_RIG_PATH
]

const ZOMBIE_MODEL_CANDIDATES: PackedStringArray = [
	"res://assets/characters/zombie.glb",
	"res://assets/characters/zombie.tscn",
	QUATERNIUS_RIG_PATH
]

const AUDIO_DIRS: PackedStringArray = [
	"res://assets/audio",
	"res://assets/sounds",
	"res://assets/sfx"
]

static var _logged_rig_info: bool = false


static func try_instantiate_character(is_zombie: bool = false) -> Node3D:
	# Primeiro verifica modelos customizados em res://assets/characters/
	var dir := DirAccess.open("res://assets/characters")
	if dir != null:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while not fname.is_empty():
			if not dir.current_is_dir():
				var low: String = fname.to_lower()
				var is_scene: bool = low.ends_with(".glb") or low.ends_with(".gltf") or low.ends_with(".tscn")
				var matches_role: bool = ("zombie" in low or "zumbi" in low) if is_zombie else (not ("zombie" in low or "zumbi" in low))
				if is_scene and matches_role:
					var full_p: String = "res://assets/characters/" + fname
					var inst := _safe_instantiate_scene(full_p)
					if inst != null:
						dir.list_dir_end()
						return inst
			fname = dir.get_next()
		dir.list_dir_end()

	# Depois carrega da lista padrao (incluindo Quaternius AnimationLibrary_Godot_Standard.glb!)
	var candidates: PackedStringArray = ZOMBIE_MODEL_CANDIDATES if is_zombie else PLAYER_MODEL_CANDIDATES
	for path in candidates:
		var inst := _safe_instantiate_scene(path)
		if inst != null:
			# Modelos Quaternius / glTF padrao olham para +Z; gira 180 graus para encarar -Z (frente Godot)
			if path == QUATERNIUS_RIG_PATH:
				inst.rotation.y = PI
				_apply_character_tint(inst, is_zombie)
			return inst
	return null


static func _safe_instantiate_scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		if inst is Node3D:
			return inst as Node3D
		if inst != null:
			inst.queue_free()
	return null


static func _apply_character_tint(root: Node, is_zombie: bool) -> void:
	var mat := StandardMaterial3D.new()
	if is_zombie:
		var z_colors: Array[Color] = [
			Color.html("#526348"), Color.html("#4a5844"),
			Color.html("#5c5a46"), Color.html("#44524b")
		]
		mat.albedo_color = z_colors[randi() % z_colors.size()]
		mat.roughness = 0.88
	else:
		# Visual tatico sobrevivente Condado de Knox (jaqueta vinho escuro / grafite)
		mat.albedo_color = Color.html("#5c3a44")
		mat.roughness = 0.72
		mat.metallic = 0.08
	_override_meshes_recursive(root, mat)


static func _override_meshes_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_override_meshes_recursive(c, mat)


static func find_first_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var found := find_first_animation_player(c)
		if found != null:
			return found
	return null


static func find_first_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for c in root.get_children():
		var found := find_first_skeleton(c)
		if found != null:
			return found
	return null


static func configure_looping_animations(anim_player: AnimationPlayer) -> void:
	## Garante que animacoes continuas (idle, walk, jog, run, sprint, crouch, strafe, sit) rodem em loop infinito!
	if anim_player == null:
		return
	var loop_keywords: PackedStringArray = [
		"loop", "idle", "walk", "jog", "run", "sprint", "strafe", "crouch", "sit", "drive", "aim"
	]
	var one_shot_keywords: PackedStringArray = [
		"death", "die", "attack", "slash", "punch", "shoot", "fire", "reload", "jump_start", "land", "hit"
	]
	var all_names: PackedStringArray = anim_player.get_animation_list()
	for an in all_names:
		var low: String = an.to_lower()
		var anim: Animation = anim_player.get_animation(an)
		if anim == null:
			continue
		var is_one_shot: bool = false
		for okw in one_shot_keywords:
			if okw in low and not ("loop" in low):
				is_one_shot = true
				break
		if is_one_shot:
			anim.loop_mode = Animation.LOOP_NONE
			continue
		for lkw in loop_keywords:
			if lkw in low:
				anim.loop_mode = Animation.LOOP_LINEAR
				break

	if not _logged_rig_info and not all_names.is_empty():
		_logged_rig_info = true
		print("[AssetBridge] Rig 3D animado ativo com %d animacoes: %s" % [all_names.size(), ", ".join(all_names.slice(0, mini(14, all_names.size())))])


static func merge_external_animations(anim_player: AnimationPlayer) -> int:
	if anim_player == null:
		return 0
	var added: int = 0
	var lib: AnimationLibrary = null
	if anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)

	for dir_path in ["res://assets/animations", "res://assets/characters/animations"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while not fname.is_empty():
			if not dir.current_is_dir():
				var low: String = fname.to_lower()
				var full_p: String = dir_path + "/" + fname
				if (low.ends_with(".tres") or low.ends_with(".res")) and ResourceLoader.exists(full_p):
					var r := ResourceLoader.load(full_p)
					if r is Animation:
						var cname: String = fname.get_basename().to_lower()
						if not lib.has_animation(cname):
							lib.add_animation(cname, r)
							added += 1
					elif r is AnimationLibrary:
						var ext_lib := r as AnimationLibrary
						for aname in ext_lib.get_animation_list():
							var key: String = str(aname).to_lower()
							if not lib.has_animation(key):
								lib.add_animation(key, ext_lib.get_animation(aname))
								added += 1
				elif (low.ends_with(".glb") or low.ends_with(".gltf")) and ResourceLoader.exists(full_p):
					var temp := _safe_instantiate_scene(full_p)
					if temp != null:
						var temp_ap := find_first_animation_player(temp)
						if temp_ap != null:
							for aname in temp_ap.get_animation_list():
								var clip := temp_ap.get_animation(aname)
								if clip != null:
									var base_key: String = fname.get_basename().to_lower()
									var final_key: String = base_key if temp_ap.get_animation_list().size() == 1 else str(aname).to_lower()
									if not lib.has_animation(final_key):
										lib.add_animation(final_key, clip.duplicate())
										added += 1
						temp.queue_free()
			fname = dir.get_next()
		dir.list_dir_end()

	configure_looping_animations(anim_player)
	return added


static func find_best_anim_name(anim_player: AnimationPlayer, keywords: PackedStringArray) -> String:
	if anim_player == null:
		return ""
	var all_anims: PackedStringArray = anim_player.get_animation_list()
	for kw in keywords:
		var kl: String = kw.to_lower()
		for an in all_anims:
			var al: String = an.to_lower()
			if al == kl or kl in al:
				return an
	return ""


static func _find_bone_index(skeleton: Skeleton3D, patterns: PackedStringArray, exclude: PackedStringArray = []) -> int:
	if skeleton == null:
		return -1
	for pat in patterns:
		for i in range(skeleton.get_bone_count()):
			var bn: String = skeleton.get_bone_name(i).to_lower()
			if not (pat in bn):
				continue
			var skip: bool = false
			for ex in exclude:
				if ex in bn:
					skip = true
					break
			if not skip:
				return i
	return -1


static func attach_node_to_right_hand(skeleton: Skeleton3D, weapon_node: Node3D) -> bool:
	if skeleton == null or weapon_node == null:
		return false
	var hand_idx: int = _find_bone_index(
		skeleton,
		["hand.r", "hand_r", "righthand", "r_hand", "wrist.r", "wrist_r"],
		["thumb", "index", "middle", "ring", "pinky", "finger", "ik", "ctrl", "target"]
	)
	if hand_idx < 0:
		return false
	var ba := BoneAttachment3D.new()
	ba.name = "RightHandWeaponBone"
	ba.bone_name = skeleton.get_bone_name(hand_idx)
	skeleton.add_child(ba)
	# Alinha a arma 3D saindo da palma da mao direita apontando para frente
	weapon_node.position = Vector3(0.0, 0.08, 0.03)
	weapon_node.rotation = Vector3(deg_to_rad(-88.0), deg_to_rad(180.0), 0.0)
	ba.add_child(weapon_node)
	return true


static func attach_knox_headgear(skeleton: Skeleton3D) -> bool:
	## Acopla o Chapeu Pork-Pie e os Oculos Wayfarer do Condado de Knox no osso da Cabeca do rig 3D!
	if skeleton == null:
		return false
	var head_idx: int = _find_bone_index(skeleton, ["head"], ["top", "end", "ik", "ctrl"])
	if head_idx < 0:
		return false
	var ba := BoneAttachment3D.new()
	ba.name = "KnoxHeadgearBone"
	ba.bone_name = skeleton.get_bone_name(head_idx)
	skeleton.add_child(ba)

	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = Color.html("#181316")
	hat_mat.roughness = 0.88
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color.html("#3a2232")
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color.html("#060709")
	lens_mat.metallic = 0.72
	lens_mat.roughness = 0.12

	# Chapeu Pork-Pie
	var hat := Node3D.new()
	hat.position = Vector3(0.0, 0.18, 0.0)
	ba.add_child(hat)

	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.175
	bm.bottom_radius = 0.180
	bm.height = 0.014
	brim.mesh = bm
	brim.material_override = hat_mat
	hat.add_child(brim)

	var crown := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.108
	cm.bottom_radius = 0.120
	cm.height = 0.088
	crown.mesh = cm
	crown.position = Vector3(0.0, 0.045, 0.0)
	crown.material_override = hat_mat
	hat.add_child(crown)

	var band := MeshInstance3D.new()
	var bdm := CylinderMesh.new()
	bdm.top_radius = 0.119
	bdm.bottom_radius = 0.122
	bdm.height = 0.022
	band.mesh = bdm
	band.position = Vector3(0.0, 0.018, 0.0)
	band.material_override = band_mat
	hat.add_child(band)

	# Oculos Wayfarer na frente do rosto (+Z no rig Quaternius)
	for side in [-1.0, 1.0]:
		var lens := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.062, 0.032, 0.016)
		lens.mesh = lm
		lens.position = Vector3(side * 0.042, 0.105, 0.108)
		lens.material_override = lens_mat
		ba.add_child(lens)
	return true


static func load_sfx_pack_clip(rel_path: String) -> AudioStream:
	var full_p: String = SFX_PACK_ROOT + rel_path
	if ResourceLoader.exists(full_p):
		var res := ResourceLoader.load(full_p)
		if res is AudioStream:
			return res as AudioStream
	return null


static func try_load_custom_audio(base_names: PackedStringArray) -> AudioStream:
	var exts: PackedStringArray = [".wav", ".ogg", ".mp3"]
	for dir_p in AUDIO_DIRS:
		for bn in base_names:
			for ext in exts:
				var full_p: String = dir_p + "/" + bn + ext
				if ResourceLoader.exists(full_p):
					var res := ResourceLoader.load(full_p)
					if res is AudioStream:
						return res as AudioStream
	return null


static func detect_installed_addons() -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open("res://addons")
	if dir == null:
		return found
	dir.list_dir_begin()
	var item: String = dir.get_next()
	while not item.is_empty():
		if dir.current_is_dir() and not item.begins_with("."):
			found.append(item)
		item = dir.get_next()
	dir.list_dir_end()
	return found
