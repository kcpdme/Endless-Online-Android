extends RefCounted
## Separate, opt-in character packs. Original manifest and map art are never edited.
const PACK_PATH: String = "res://art_packs/painted_v1/pack.json"
var settings_path: String = "user://graphics.cfg"
var mode: String = "classic"
var classic: Dictionary = {}
var replacements: Dictionary = {}
var appearances: Dictionary = {}
var pack_root: String = "res://art_packs/painted_v1/"
var validated: Dictionary = {}
var selections: Dictionary = {}
var texture_sizes: Dictionary = {}

func configure(manifest: Dictionary) -> void:
	classic = ((manifest.get("characters", {}) as Dictionary).get("equipment_layers", {}) as Dictionary).get("layers", {}) as Dictionary
	load_pack(PACK_PATH)
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) == OK:
		mode = "enhanced" if config.get_value("graphics", "characters", "classic") == "enhanced" else "classic"

func load_pack(path: String) -> bool:
	replacements.clear(); appearances.clear(); validated.clear(); selections.clear(); texture_sizes.clear()
	pack_root = path.get_base_dir() + "/"
	if not FileAccess.file_exists(path): return false
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary: return false
	var data: Dictionary = json.data
	if data.get("schema", 0) != 1 or data.get("status", "draft") != "ready" or not data.get("layers") is Dictionary: return false
	replacements = data.layers
	if data.get("appearances", {}) is Dictionary: appearances = data.get("appearances", {})
	return ready()

func ready() -> bool:
	return not replacements.is_empty() or not appearances.is_empty()

func matching_appearance(record: Dictionary) -> String:
	var equipment: Array = record.get("equipment_graphics", []) as Array
	if equipment.size() != 9: return ""
	var actual: Dictionary = {"gender":int(record.get("gender",1)),"race":int(record.get("race",0)),"hairstyle":int(record.get("hairstyle",1)),"haircolor":int(record.get("haircolor",0)),"boots":int(equipment[0]),"armor":int(equipment[4]),"hat":int(equipment[6]),"shield":int(equipment[7]),"weapon":int(equipment[8])}
	for id: String in appearances:
		var entry: Variant = appearances[id]
		if not entry is Dictionary or not entry.get("match") is Dictionary: continue
		var matches: bool = true
		for key: String in actual:
			if not entry.match.has(key) or int(entry.match[key]) != int(actual[key]): matches = false; break
		if matches: return id
	return ""

func appearance(record: Dictionary) -> Dictionary:
	if mode != "enhanced": return {}
	var id: String = matching_appearance(record)
	if id.is_empty(): return {}
	var cache_key: String = "appearance:" + id
	if not validated.has(cache_key): validated[cache_key] = valid_appearance(appearances[id].get("character"))
	return appearances[id].character as Dictionary if bool(validated[cache_key]) else {}

func valid_appearance(character: Variant) -> bool:
	if not character is Dictionary: return false
	var states: Dictionary = {"idle":1,"frames":4,"attack":2,"cast":1,"ranged_attack":2,"sit_chair":1,"sit_floor":1}
	for state: String in states:
		if not character.get(state) is Dictionary: return false
		for direction: String in ["south","east","north","west"]:
			var raw: Variant = character[state].get(direction)
			var frames: Array = [raw] if raw is Dictionary else raw if raw is Array else []
			if frames.size() != int(states[state]): return false
			for frame: Variant in frames:
				if not valid_layer({"path":"","region":[0,0,192,192],"offset":[0,8]},frame): return false
	return true

func select_mode(value: String, persist: bool = true) -> bool:
	if value not in ["classic", "enhanced"] or (value == "enhanced" and not ready()): return false
	mode = value; selections.clear()
	if persist:
		var config: ConfigFile = ConfigFile.new()
		config.set_value("graphics", "characters", mode)
		return config.save(settings_path) == OK
	return true

func required_keys(record: Dictionary) -> Array[String]:
	var equipment: Array = record.get("equipment_graphics", []) as Array
	if equipment.size() != 9: return []
	var female: String = "f:" if int(record.get("gender", 1)) == 0 else ""
	var race: int = clampi(int(record.get("race", 0)), 0, 6)
	var hair: int = clampi(int(record.get("hairstyle", 1)), 0, 20)
	var color: int = clampi(int(record.get("haircolor", 0)), 0, 9)
	var keys: Array[String] = ["skin:%s0" % female + (":%d" % race if race > 0 else "")]
	for pair: Array in [["boots", 0], ["armor", 4], ["head", 6], ["offhand", 7], ["weapon_back", 8], ["weapon_front", 8]]:
		if int(equipment[pair[1]]) > 0: keys.append("%s:%s%d" % [pair[0], female, equipment[pair[1]]])
	var head: Dictionary = classic.get("head:%s%d" % [female, equipment[6]], {}) as Dictionary
	if hair > 0 and str(head.get("mask_mode", "")) != "hide":
		keys.append("hair:%s0" % female + (":%d:%d" % [hair, color] if [hair, color] != [1, 0] else ""))
	var result: Array[String] = []
	for key: String in keys:
		if classic.has(key): result.append(key)
	return result

func definitions(record: Dictionary) -> Dictionary:
	if mode != "enhanced" or not ready(): return classic
	var keys: Array[String] = required_keys(record)
	var cache_key: String = ";".join(keys)
	if selections.has(cache_key): return selections[cache_key] as Dictionary
	# A whole appearance switches together; unfinished clothes never mix with a new body.
	for key: String in keys:
		if not validated.has(key): validated[key] = replacements.has(key) and valid_layer(classic[key], replacements[key])
		if not bool(validated[key]): selections[cache_key] = classic; return classic
	var result: Dictionary = classic.duplicate()
	for key: String in keys: result[key] = replacements[key]
	selections[cache_key] = result
	return result

func valid_layer(original: Variant, candidate: Variant) -> bool:
	if original is Dictionary:
		if not candidate is Dictionary: return false
		if original.has("path") and original.has("region"):
			var path: String = str(candidate.get("path", ""))
			var scale: float = float(candidate.get("pixel_scale", 1))
			var region: Variant = candidate.get("region", [])
			if scale not in [1.0, 2.0, 3.0, 4.0] or not path.begins_with(pack_root + "releases/") or ".." in path: return false
			if not region is Array or region.size() != 4: return false
			var offset: Variant = candidate.get("offset",[0,0])
			var original_offset: Array = original.get("offset",[0,0])
			if not offset is Array or offset.size() != 2: return false
			for i: int in range(2):
				if not (offset[i] is int or offset[i] is float) or float(offset[i]) != float(original_offset[i]): return false
			for value: Variant in region:
				if not (value is int or value is float) or float(value) != floorf(float(value)): return false
			if float(region[0]) < 0 or float(region[1]) < 0 or float(region[2]) <= 0 or float(region[3]) <= 0: return false
			if candidate.has("logical_canvas"):
				var canvas: Variant = candidate.logical_canvas
				if not canvas is Array or canvas.size() != 2: return false
				for i: int in range(2):
					if not (canvas[i] is int or canvas[i] is float) or float(canvas[i]) != float(original.region[i+2]): return false
				var trim: Variant = candidate.get("trim_offset", [])
				if not trim is Array or trim.size() != 2: return false
				for value: Variant in trim:
					if not (value is int or value is float) or float(value) < 0: return false
				if float(trim[0]) + float(region[2])/scale > float(original.region[2]) or float(trim[1]) + float(region[3])/scale > float(original.region[3]): return false
			elif float(region[2]) != float(original.region[2])*scale or float(region[3]) != float(original.region[3])*scale: return false
			if not ResourceLoader.exists(path): return false
			if not texture_sizes.has(path):
				var texture: Texture2D = load(path) as Texture2D
				texture_sizes[path] = texture.get_size() if texture != null else Vector2.ZERO
			var size: Vector2 = texture_sizes[path]
			return float(region[0]) + float(region[2]) <= size.x and float(region[1]) + float(region[3]) <= size.y
		for key: Variant in original:
			if not candidate.has(key) or not valid_layer(original[key], candidate[key]): return false
		return true
	if original is Array:
		if not candidate is Array or original.size() != candidate.size(): return false
		for index: int in range(original.size()):
			if not valid_layer(original[index], candidate[index]): return false
		return true
	return original == candidate
