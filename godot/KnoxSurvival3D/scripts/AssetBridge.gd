extends RefCounted
class_name AssetBridge

## Ponte automatica para Assets da Godot Asset Store / Modelos 3D / Animacoes / Sons locais!
## Permite soltar arquivos .glb/.gltf/.tscn em res://assets/characters/, res://assets/animations/,
## res://assets/audio/ ou plugins em res://addons/ (Sky3D, Terrain3D, TerraBrush, RoadGenerator)
## sem quebrar o jogo caso nao existam ainda.

const PLAYER_MODEL_CANDIDATES: PackedStringArray = [
	"res://assets/characters/player.glb",
	"res://assets/characters/survivor.glb",
	"res://assets/characters/swat.glb",
	"res://assets/characters/player.tscn",
	"res://assets/characters/survivor.tscn"
]

const ZOMBIE_MODEL_CANDIDATES: PackedStringArray = [
	"res://assets/characters/zombie.glb",
	"res://assets/characters/zombie.tscn"
]

const ANIM_DIRS: PackedStringArray = [
	"res://assets/animations",
	"res://assets/characters/animations",
	"res://addons"
]

const AUDIO_DIRS: PackedStringArray = [
	"res://assets/audio",
	"res://assets/sounds",
	"res://assets/sfx"
]


static func try_instantiate_character(is_zombie: bool = false) -> Node3D:
	var candidates: PackedStringArray = ZOMBIE_MODEL_CANDIDATES if is_zombie else PLAYER_MODEL_CANDIDATES
	for path in candidates:
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path)
			if res is PackedScene:
				var inst := (res as PackedScene).instantiate()
				if inst is Node3D:
					return inst as Node3D

	# Busca generica em res://assets/characters/ caso o usuario tenha usado outro nome
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
					if ResourceLoader.exists(full_p):
						var res := ResourceLoader.load(full_p)
						if res is PackedScene:
							var inst := (res as PackedScene).instantiate()
							if inst is Node3D:
								dir.list_dir_end()
								return inst as Node3D
			fname = dir.get_next()
		dir.list_dir_end()
	return null


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


static func merge_external_animations(anim_player: AnimationPlayer) -> int:
	## Mescla automaticamente clips de animacao (.glb/.gltf/.tres/.res) colocados em res://assets/animations/
	## dentro do AnimationPlayer do personagem!
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
					var ps := ResourceLoader.load(full_p)
					if ps is PackedScene:
						var temp := (ps as PackedScene).instantiate()
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
	return added


static func find_best_anim_name(anim_player: AnimationPlayer, keywords: PackedStringArray) -> String:
	if anim_player == null:
		return ""
	var all_anims: PackedStringArray = anim_player.get_animation_list()
	for kw in keywords:
		var kl: String = kw.to_lower()
		for an in all_anims:
			if kl in an.to_lower():
				return an
	return ""


static func attach_node_to_right_hand(skeleton: Skeleton3D, weapon_node: Node3D) -> bool:
	if skeleton == null or weapon_node == null:
		return false
	var hand_idx: int = -1
	for i in range(skeleton.get_bone_count()):
		var bn: String = skeleton.get_bone_name(i).to_lower()
		if ("righthand" in bn or "hand_r" in bn or "hand.r" in bn or "r_hand" in bn) and not ("thumb" in bn or "index" in bn or "middle" in bn or "ring" in bn or "pinky" in bn):
			hand_idx = i
			break
	if hand_idx < 0:
		return false
	var ba := BoneAttachment3D.new()
	ba.name = "RightHandWeaponBone"
	ba.bone_name = skeleton.get_bone_name(hand_idx)
	skeleton.add_child(ba)
	weapon_node.position = Vector3(0.0, 0.04, 0.02)
	weapon_node.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	ba.add_child(weapon_node)
	return true


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
