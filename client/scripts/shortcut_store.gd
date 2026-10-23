extends RefCounted
## Character names persist; EO's numeric character IDs are allocated each login.
static func read_slots(path: String, identity: String) -> Array:
	if identity.is_empty() or not FileAccess.file_exists(path): return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return []
	var raw: Variant = data.get(identity, [])
	if not raw is Array or raw.size() != 2: return []
	return [maxi(0, int(raw[0])), maxi(0, int(raw[1]))]

static func write_slots(path: String, identity: String, slots: Array) -> void:
	if identity.is_empty() or slots.size() != 2: return
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Dictionary: data = raw
	data[identity] = slots.duplicate()
	_write(path, data)

static func clear_slots(path: String, identity: String) -> void:
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		data.erase(identity)
		_write(path, data)

static func _write(path: String, data: Dictionary) -> void:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	DirAccess.rename_absolute(temporary, path)
