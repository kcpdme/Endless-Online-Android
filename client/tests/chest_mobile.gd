extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.online_mode = true
	game.started = true
	game.load_map(53)
	var c: Node = game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session = wire
	c.active = true
	c.streaming = true
	c.player = {"name":"fixture","player_id":100,"character_id":100,"map_id":53,"x":6,"y":23,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"inventory":[{"id":1,"amount":100},{"id":21,"amount":5}]}
	game.player_tile = Vector2i(6,23)
	game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	c._sync_inventory()
	var chest_tile: Vector2i = Vector2i(6,22)
	var hit: Dictionary = c.map_entity_target(game.tile_position(chest_tile)+Vector2(0,-12))
	check(hit.get("kind","") == "chest" and hit.tile == chest_tile,"Chest artwork must target the chest instead of blocked ground")
	c.map_click(chest_tile,"chest")
	c._process_interaction()
	check(wire.calls.back().op == "chest_open" and wire.calls.back().fields == {"x":6,"y":22},"Adjacent chest tap must send original open coordinates")
	var state: Dictionary = {"map_id":53,"x":6,"y":22,"items":[{"id":21,"amount":2},{"id":375,"amount":20}]}
	c._on_message({"op":"chest_open","ok":true,"data":{"chest":state}})
	var ui: RefCounted = game.services_ui
	check(ui.panel.visible and ui.mode == "chest" and ui.right.item_count == 2,"Native chest contents must open a readable loot window")
	ui.right.select(0)
	ui._selected()
	ui._secondary()
	check(wire.calls.back().op == "chest_take" and wire.calls.back().fields.item_id == 21,"Take sends original whole-stack operation")
	check(c.bag_amount(21) == 5,"Bag must not gain items before native acknowledgement")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v33-chest.png")
	c.player.inventory = [{"id":1,"amount":100},{"id":21,"amount":7}]
	c._on_message({"op":"chest_take","ok":true,"data":{"player":c.player.duplicate(true),"chest":{"map_id":53,"x":6,"y":22,"items":[]}}})
	check(c.bag_amount(21) == 7 and ui.right.item_count == 0 and ui.panel.visible,"Native take updates bag and leaves empty chest open")
	ui.left.select(0)
	ui._selected()
	ui.quantity.value = 50
	ui._primary()
	check(wire.calls.back().op == "chest_deposit" and wire.calls.back().fields == {"item_id":1,"amount":50},"Gold can be put in a chest, separately from bank storage")
	check(game.coins == 100,"Deposit cannot spend bag Gold without acknowledgement")
	ui.close()
	check(not ui.panel.visible and wire.calls.back().op == "chest_close","Closing releases only the chest context")
	ui.open("locker",{"items":[]})
	check(ui.title.text == "ITEM LOCKER" and ui.left_rows.size() == 1 and int(ui.left_rows[0].id) == 21 and ui.secondary.text == "Withdraw stack","Locker must retain separate item-only storage behavior")
	ui.close()
	print("CHEST MOBILE ","FAIL" if failed else "PASS",": artwork targeting, adjacent open, native loot rows, whole-stack take, acknowledged bag counts, Gold deposit and close")
	game.started = false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
