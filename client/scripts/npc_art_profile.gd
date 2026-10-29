extends RefCounted
## Small optional NPC atlas pack; the original manifest stays available in memory.
const PACK_PATH: String = "res://content/characters/npc_enhanced/pack.json"
const ROOT_PATH: String = "res://content/characters/npc_enhanced/"
var settings_path: String = "user://graphics.cfg"
var enabled: bool = true
var classic: Dictionary = {}
var enhanced: Dictionary = {}
var target: Dictionary = {}
var sizes: Dictionary = {}

func configure(manifest: Dictionary) -> void:
	target = (manifest.get("characters", {}) as Dictionary).get("npcs", {}) as Dictionary
	classic = target.duplicate(true)
	enhanced.clear(); sizes.clear()
	if FileAccess.file_exists(PACK_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_PATH))
		if data is Dictionary and int(data.get("schema", 0)) == 1 and data.get("graphics", {}) is Dictionary:
			for key: String in data.get("graphics", {}):
				var candidate: Variant = data.graphics[key]
				if candidate is Dictionary and classic.has(key) and valid(classic[key], candidate): enhanced[key] = candidate
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) == OK: enabled = bool(config.get_value("graphics", "enhanced_npcs", true))
	apply()

func ready() -> bool:
	return not enhanced.is_empty()

func select(value: bool, persist: bool = true) -> bool:
	enabled = value
	apply()
	if not persist: return true
	var config: ConfigFile = ConfigFile.new()
	config.load(settings_path)
	config.set_value("graphics", "enhanced_npcs", enabled)
	return config.save(settings_path) == OK

func apply() -> void:
	for key: String in enhanced: target[key] = enhanced[key] if enabled else classic[key]

func valid(original: Variant, candidate: Variant) -> bool:
	if original is Dictionary:
		if not candidate is Dictionary: return false
		if original.has("path") and original.has("region"):
			var path: String = str(candidate.get("path", ""))
			var raw_scale: Variant = candidate.get("pixel_scale", 1)
			if not (raw_scale is int or raw_scale is float): return false
			var scale: float = float(raw_scale)
			var region: Variant = candidate.get("region", [])
			if scale != 2.0 or not path.begins_with(ROOT_PATH) or ".." in path or not region is Array or region.size() != 4: return false
			if candidate.get("offset", []) != original.get("offset", []): return false
			for value: Variant in region:
				if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0: return false
			if float(region[2]) != float(original.region[2])*scale or float(region[3]) != float(original.region[3])*scale: return false
			var before: Array = original.get("visible_bounds", [])
			var after: Variant = candidate.get("visible_bounds", [])
			if not after is Array or before.size() != 4 or after.size() != 4: return false
			for index: int in range(4):
				if not (after[index] is int or after[index] is float): return false
				if float(after[index]) != float(before[index])*scale: return false
			for key:Variant in candidate:
				if key not in ["path","region","visible_bounds","pixel_scale"]:
					if not original.has(key) or candidate[key]!=original[key]: return false
			if not ResourceLoader.exists(path): return false
			if not sizes.has(path):
				var texture: Texture2D = load(path) as Texture2D
				sizes[path] = texture.get_size() if texture != null else Vector2.ZERO
			var size: Vector2 = sizes[path]
			return size.x <= 2048 and size.y <= 2048 and float(region[0])+float(region[2]) <= size.x and float(region[1])+float(region[3]) <= size.y
		for key: Variant in original:
			if not candidate.has(key) or not valid(original[key], candidate[key]): return false
		return true
	if original is Array:
		if not candidate is Array or original.size() != candidate.size(): return false
		for index: int in range(original.size()):
			if not valid(original[index], candidate[index]): return false
		return true
	return original == candidate
