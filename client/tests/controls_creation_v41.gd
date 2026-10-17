extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op": op, "fields": fields.duplicate()})
		return calls.size()
var failed: bool = false
var checks: int = 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(reason)
func _initialize() -> void: call_deferred("run")
func touch(point: Vector2, pressed: bool, pointer: int = 71) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point; event.pressed = pressed; event.index = pointer
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	root.size = Vector2i(1544, 720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame
	game.set_process(false); game.music.stop(); game.welcome.hide(); game.started = true
	var attack: Vector2 = game.attack_button.get_global_rect().get_center()
	game.enemy_health = 100; game.enemy_tile = game.player_tile + Vector2i(0, 1)
	await touch(attack, true); await touch(attack, false)
	check(not game.auto_attack and game.attack_touch_id == -1, "Short tap must remain manual")
	game.attack_clock = 0.0; game._process(.01)
	check(game.attack_clock == 0.0, "Manual release must stop repetition")
	for i: int in range(3):
		await touch(attack, true); await touch(attack, false)
		check(not game.auto_attack, "Repeated taps must never toggle auto on")
	await touch(attack, true)
	game.attack_held_at -= 700; game._process(.01)
	check(game.auto_attack and game.attack_button.automatic, "Long hold latches and marks AUTO")
	await touch(attack, false)
	check(game.auto_attack and game.attack_touch_id == -1, "Auto must survive finger release")
	game.attack_clock = 0.0; game._process(.01)
	check(game.attack_clock > 0.0, "Released auto continues attacks")
	await touch(attack, true); await touch(attack, false)
	check(not game.auto_attack and not game.attack_button.automatic, "Next weapon tap returns to manual")
	await touch(attack, true); game.attack_held_at -= 700; game._process(.01); await touch(attack, false)
	game._toggle_inventory()
	check(not game.auto_attack, "Opening a modal cancels auto")
	game.inventory.hide()
	await touch(attack, true); game.attack_held_at -= 700; game._process(.01); await touch(attack, false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.auto_attack, "Background/focus loss cancels auto")
	# Mouse uses the same hold latch; Android's emulated mouse cannot toggle it.
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT; mouse.position = attack; mouse.pressed = true
	Input.parse_input_event(mouse); await process_frame
	game.attack_held_at -= 700; game._process(.01)
	mouse = mouse.duplicate(); mouse.pressed = false
	Input.parse_input_event(mouse); await process_frame
	check(game.auto_attack, "Physical mouse hold also survives release")
	mouse = mouse.duplicate(); mouse.pressed = true; mouse.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(mouse); await process_frame
	check(game.auto_attack, "Emulated Android mouse cannot cancel native auto mode")
	mouse = mouse.duplicate(); mouse.pressed = false
	Input.parse_input_event(mouse); await process_frame
	game._cancel_controls(true)
	check(not game.auto_attack, "Forced death/warp/disconnect cancellation clears auto")
	for width: int in [1280, 1544]:
		root.size = Vector2i(width, 720); await process_frame
		var controls: Array = [game.attack_button, game.bag_button, game.sit_button, game.online.loot_button] + game.quick_items.buttons + game.skills_ui.buttons.slice(0, 2)
		for control: Control in controls:
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()), "Combat group stays inside viewport")
		check(is_equal_approx(game.attack_button.offset_left, -260) and is_equal_approx(game.attack_button.offset_top, -288), "Attack moves together with combat group")
	var online: Node = game.online; online.session.queue_free()
	var wire: Capture = Capture.new(); online.add_child(wire); wire.set_process(false); online.session = wire
	online.panel.show(); online.creation_panel.show(); online.character_name_field.text = "devcreator"
	online.body_choice.select(0); online.skin_choice.select(3); online.hair_choice.select(19); online.color_choice.select(9)
	online._update_creation_preview(); await process_frame
	var expected: Dictionary = {"gender": 0, "race": 3, "hairstyle": 20, "haircolor": 9}
	check(online.character_preview.appearance == expected, "Preview must use selected original appearance")
	for gender: int in [0, 1]:
		for skin: int in range(4):
			for hair: int in range(1, 21):
				var graphic: Dictionary = online.character_graphic({"gender":gender,"race":skin,"hairstyle":hair,"haircolor":9,"equipment_graphics":[0,0,0,0,0,0,0,0,0]})
				check((graphic.get("layers", []) as Array).size() == 2, "Every offered body/skin/hair uses real layers")
	var create_button: Button
	for child: Node in online.creation_panel.get_child(0).get_children():
		if child is Button and child.text == "Create character": create_button = child
	await touch(create_button.get_global_rect().get_center(), true, 73); await touch(create_button.get_global_rect().get_center(), false, 73)
	check(wire.calls.size() == 1 and wire.calls[0].op == "create_character", "Actual Create button must send one native creation request")
	if not wire.calls.is_empty():
		expected.name = "devcreator"
		check(wire.calls[0].fields == expected, "Creation request must send all selected appearance fields")
	game._handle_back(); check(not online.creation_panel.visible and online.panel.visible, "Back returns to character selection")
	if OS.get_environment("EO_V41_SCREENSHOT") != "":
		online.creation_panel.show(); await process_frame; await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(OS.get_environment("EO_V41_SCREENSHOT"))
	game.started = false; game.queue_free(); await process_frame
	if not failed: print("CONTROLS CREATION V41 PASS: ", checks, " checks")
	quit(1 if failed else 0)
