extends RefCounted
## Local cache plus acknowledged server saves. Empty slots are intentional values.
const Store = preload("res://scripts/shortcut_store.gd")
var pending_path: String = "user://shortcut_pending.json"
var online: Node
var available: bool = false
var identity: String = ""
var server_slots: Dictionary = {}
var queued: Dictionary = {}
var inflight: Dictionary = {}
var retry_at: int = 0
var warned: bool = false

func begin(owner_online: Node, saved: Dictionary) -> void:
	online = owner_online
	available = true
	identity = online.profile_identity()
	server_slots = saved.duplicate(true)
	queued.clear()
	inflight.clear()
	retry_at = 0
	warned = false
	online.game.quick_items.identity = ""
	online.game.skills_ui.shortcut_identity = ""

func disconnected() -> void:
	available = false
	inflight.clear()
	queued.clear()

func load_slots(kind: String, path: String, profile: String, defaults: Array) -> Array:
	var local: Array = Store.read_slots(path, profile)
	var result: Array = local if local.size() == 2 else defaults.duplicate()
	if available and profile == identity:
		var pending: Array = Store.read_slots(pending_path, profile + "/" + kind)
		var remote: Array = server_slots.get(kind, []) as Array
		if pending.size() == 2:
			result = pending
			queued[kind] = result.duplicate()
		elif remote.size() == 2:
			result = remote.duplicate()
		else:
			# First login to the upgraded server migrates existing local bindings.
			save_slots(kind, path, profile, result)
	Store.write_slots(path, profile, result)
	return result

func save_slots(kind: String, path: String, profile: String, values: Array) -> void:
	if profile.is_empty(): return
	Store.write_slots(path, profile, values)
	Store.write_slots(pending_path, profile + "/" + kind, values)
	if available and profile == identity:
		queued[kind] = values.duplicate()

func tick() -> void:
	if not available or not online.active or online.profile_identity() != identity or Time.get_ticks_msec() < retry_at: return
	for kind: String in queued.keys():
		var busy: bool = false
		for request: Dictionary in inflight.values():
			if request.kind == kind: busy = true
		if busy: continue
		var values: Array = queued[kind]
		var id: int = online.session.request("shortcuts_set", {"kind": kind, "first": int(values[0]), "second": int(values[1])})
		if id < 0: return
		inflight[id] = {"kind": kind, "slots": values.duplicate()}
		queued.erase(kind)

func response(message: Dictionary) -> void:
	var id: int = int(message.get("id", -1))
	if not inflight.has(id): return
	var request: Dictionary = inflight[id]
	inflight.erase(id)
	var kind: String = request.kind
	if not bool(message.get("ok", false)):
		if not queued.has(kind): queued[kind] = request.slots
		retry_at = Time.get_ticks_msec() + 5000
		if not warned:
			online.game._toast("Shortcut saved on this device. Server save will retry.")
			warned = true
		return
	server_slots[kind] = request.slots.duplicate()
	# An earlier ACK must never erase or visually restore a newer assignment.
	if not queued.has(kind):
		Store.clear_slots(pending_path, identity + "/" + kind)
	warned = false
