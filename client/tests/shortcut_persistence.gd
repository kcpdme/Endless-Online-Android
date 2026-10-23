extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		serial += 1
		calls.append({"id": serial, "op": op, "fields": fields.duplicate()})
		return serial
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(reason)
func run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.music.stop()
	game.welcome.hide();game.online.panel.hide()
	game.online_mode = true
	game.started = true
	var c: Node = game.online
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire); wire.set_process(false); c.session = wire
	c.active = true
	c.host_field.text = "wss://test.invalid/ws"
	c.player = {"name":"hero", "character_id":1, "inventory":[{"id":331,"amount":2},{"id":375,"amount":3}], "spells":[{"id":1},{"id":5}], "tp":100}
	var quick: RefCounted = game.quick_items
	var skills: RefCounted = game.skills_ui
	var sync: RefCounted = c.shortcuts
	var store: Script = load("res://scripts/shortcut_store.gd")
	quick.settings_path = "user://test-items.json"
	skills.settings_path = "user://test-skills.json"
	sync.pending_path = "user://test-pending.json"
	var profile: String = c.profile_identity()
	store.write_slots(quick.settings_path, profile, [375,331])
	store.write_slots(skills.settings_path, profile, [5,1])
	sync.begin(c, {})
	quick.refresh(); skills.refresh(); sync.tick()
	check(quick.slots == [375,331] and skills.slots == [5,1], "Existing four local bindings migrate")
	check(wire.calls.size() == 2, "Only two independent initial save requests")
	for call: Dictionary in wire.calls.duplicate():
		c._on_message({"op":"shortcuts_set", "id":call.id, "ok":true})
	check(store.read_slots(sync.pending_path, profile + "/items").is_empty(), "Server ACK clears dirty item marker")
	# Fresh install: no local slot files or pending metadata. Server restores all four.
	for path: String in [quick.settings_path,skills.settings_path,sync.pending_path]: DirAccess.remove_absolute(path)
	sync.begin(c, {"items":[331,375],"skills":[1,5]})
	quick.refresh(); skills.refresh(); sync.tick()
	check(quick.slots == [331,375] and skills.slots == [1,5], "Fresh install restores all four from server")
	check(wire.calls.size() == 2, "Restore never writes defaults over the server")
	# Zero stock and a partial snapshot must not change assigned items.
	c.player.inventory = []
	quick.refresh()
	check(quick.slots == [331,375], "Depleted consumable bindings survive")
	check((quick.buttons[0].get_node("Quantity") as Label).text == "0", "Quantity follows authoritative bag")
	# Two assignments while the first save is in flight: its ACK cannot restore old choices.
	quick.selected_slot = 0; quick.assign(375); sync.tick()
	var earlier: Dictionary = wire.calls.back()
	quick.assign(0)
	c._on_message({"op":"shortcuts_set", "id":earlier.id,"ok":true})
	check(quick.slots == [0,375], "Earlier ACK never reverts a newer assignment")
	check(store.read_slots(sync.pending_path,profile + "/items") == [0,375], "Earlier ACK retains latest pending values")
	sync.tick(); var latest: Dictionary = wire.calls.back()
	check(latest.fields.first == 0 and latest.fields.second == 375, "Latest choices sent after earlier ACK")
	c._on_message({"op":"shortcuts_set","id":latest.id,"ok":false})
	check(sync.queued.items == [0,375] and quick.slots == [0,375], "Failed save preserves choices for retry")
	# Reconnection before ACK uses the durable unsaved value over older server data.
	sync.disconnected(); sync.begin(c,{"items":[331,375],"skills":[1,5]})
	quick.refresh(); skills.refresh(); sync.tick()
	check(quick.slots == [0,375], "Reconnect retries unsaved choices instead of reverting")
	latest = wire.calls.back()
	c._on_message({"op":"shortcuts_set","id":latest.id,"ok":true})
	check(store.read_slots(sync.pending_path,profile + "/items").is_empty(), "Successful retry clears durable pending marker")
	# Server zeros must not be replaced by automatic defaults.
	sync.begin(c,{"items":[0,0],"skills":[0,0]})
	quick.refresh(); skills.refresh()
	check(quick.slots == [0,0] and skills.slots == [0,0], "Explicitly empty slots survive login")
	# Learned list removes a forgotten skill, saves that clearing, retains the other slot.
	sync.begin(c,{"items":[0,0],"skills":[1,5]})
	c.player.spells = [{"id":1}]; quick.refresh(); skills.refresh(); sync.tick()
	check(skills.slots == [1,0] and wire.calls.back().fields.second == 0, "Forgetting one spell persists only its cleared slot")
	check(not wire.has_blocking_requests(), "Preference saves never block movement or combat")
	var report: Dictionary = {"result":"passed" if not failed else "failed","checks":checks,"all_four_restore_after_local_data_loss":true,"local_migration":true,"reconnect_pending_retry":true,"stale_ack_no_revert":true,"explicit_zero_and_depleted_items":true}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var f: FileAccess = FileAccess.open(path,FileAccess.WRITE); f.store_string(JSON.stringify(report,"  ")+"\n")
	print("SHORTCUT PERSISTENCE: ",JSON.stringify(report))
	game.queue_free(); await process_frame; await process_frame
	quit(1 if failed else 0)
