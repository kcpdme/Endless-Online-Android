extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
var checks: int = 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true;push_error(reason)
func _initialize() -> void: call_deferred("run")
func tap(control: Control, index: int) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index;event.position = control.get_global_rect().get_center();event.pressed = true
	Input.parse_input_event(event);await process_frame
	event = event.duplicate();event.pressed = false
	Input.parse_input_event(event);await process_frame
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.set_process(false);game.music.stop();game.welcome.hide();game.online_mode = true;game.started = true
	var c: Node = game.online;c.set_process(false);c.session.queue_free()
	var wire: Capture = Capture.new();c.add_child(wire);wire.set_process(false);c.session = wire;c.active = true;c.streaming = true
	c.host_field.text = "wss://test.invalid/ws"
	c.player = {"name":"pairedfixture","character_id":1,"player_id":100,"map_id":5,"x":40,"y":40,"hp":100,"maxhp":100,"tp":100,"maxtp":100,"gender":1,"level":120,"inventory":[],"equipment":{},"stats":{"class_id":6,"strength":3000,"intelligence":3000,"wisdom":3000,"agility":3000,"constitution":3000,"charisma":3000}}
	for row: Array in [[41,"ring1","ring2"],[39,"armlet1","armlet2"],[54,"bracer1","bracer2"]]:
		var id: int = int(row[0]);var first: String = str(row[1]);var second: String = str(row[2])
		c.player.inventory = [{"id":id,"amount":1}];c.player.equipment = {first:id}
		game.inventory.show();game.character_panel.hide();game._select_item("item:%d" % id);game._refresh_ui();await process_frame
		check(not game.equip_button.disabled, "Bag copy must enable Equip for " + first)
		var before: int = wire.calls.size()
		await tap(game.equip_button, 81)
		check(wire.calls.size() == before + 1, "ACTUAL Equip button tap must send second-slot request for " + first)
		if wire.calls.size() > before:
			check(wire.calls.back().op == "equip" and int(wire.calls.back().fields.item_id) == id and int(wire.calls.back().fields.subloc) == 1, "Second copy must Add to alternate slot without removing first")
		check(c.player.equipment == {first:id} and c.bag_amount(id) == 1, "Client cannot mutate equipped items or inventory before ACK")
		# Model native ACK: both copies are worn and the bag copy is gone.
		c.player.equipment = {first:id,second:id};c.player.inventory = [];game._refresh_ui()
		check(game.equip_button.disabled, "No remaining bag copy means Equip is disabled")
		game.inventory.hide();game.character_panel.show();game._refresh_ui();await process_frame
		check((game.paperdoll.slots[first] as Button).icon != null and (game.paperdoll.slots[second] as Button).icon != null, "Both original paperdoll spaces must visibly contain the item")
		before = wire.calls.size()
		await tap(game.paperdoll.slots[second],82);await tap(game.paperdoll.slots[second],83)
		await create_timer(.3).timeout
		check(wire.calls.size() == before + 1 and wire.calls.back().op == "unequip" and int(wire.calls.back().fields.subloc) == 1, "Real double tap must remove secondary slot only")
		check(not game.stats_ui.item_panel.visible, "Double tap cannot open item details")
		game.character_panel.hide()
	# Consuming a potion through the same button must still use the server item flow.
	c.player.equipment = {};c.player.inventory = [{"id":375,"amount":2}];c.player.hp = 50
	game.inventory.show();game._select_item("item:375");game._refresh_ui();await process_frame
	var before: int = wire.calls.size();await tap(game.equip_button,84)
	check(wire.calls.size() == before+1 and wire.calls.back().op == "potion_use", "Bag Use must keep working for consumables")
	game.started = false;game.queue_free();await process_frame
	if not failed: print("PAIRED EQUIPMENT V38 PASS: ",checks," actual UI checks")
	quit(1 if failed else 0)
