extends RefCounted
## Optional Android Keystore persistence. No plaintext fallback on other platforms.
var backend: Object
func _init() -> void:
	if Engine.has_singleton("AsterCredentials"):backend=Engine.get_singleton("AsterCredentials")
func available() -> bool:return backend!=null
func load_login() -> Dictionary:
	if backend==null:return {}
	var encoded: String=str(backend.loadCredentials())
	if encoded.is_empty():return {}
	var json: JSON=JSON.new()
	if json.parse(encoded)!=OK or not json.data is Dictionary:return {}
	return json.data as Dictionary
func save_login(data: Dictionary) -> bool:
	return backend!=null and bool(backend.saveCredentials(str(data.host),int(data.port),str(data.username),str(data.password)))
func forget() -> bool:return backend!=null and bool(backend.clearCredentials())
