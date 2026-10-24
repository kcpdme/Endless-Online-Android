extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1544, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.welcome.hide()
	game.online.panel.hide()
	game.started = true
	game.online_mode = true
	game.online.active = true
	game.shop_ui.open({"name": "Shop Bob", "trade": [], "craft": []})
	await process_frame
	await create_timer(.25).timeout
	var close_button: Button
	for child: Node in game.shop_ui.panel.get_child(0).get_children():
		if child is Button and child.text == "×": close_button = child
	var at: Vector2 = root.get_final_transform()*close_button.get_global_rect().get_center()
	print("CLOSE / CHAT OVERLAP: ", close_button.get_global_rect().intersection(game.chat_button.get_global_rect()))
	# Android can deliver emulated mouse and native touch for a single gesture.
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse.duplicate())
	await process_frame
	mouse.pressed = false
	Input.parse_input_event(mouse.duplicate())
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 84
	touch.position = at
	touch.pressed = true
	Input.parse_input_event(touch.duplicate())
	touch.pressed = false
	Input.parse_input_event(touch.duplicate())
	await process_frame
	await process_frame
	print("CLOSE RESULT: shop=",game.shop_ui.panel.visible," chat=",game.chat_ui.panel.visible)
	assert(not game.shop_ui.panel.visible, "Shop must close")
	assert(not game.chat_ui.panel.visible, "Shop close gesture must not open conversation")
	await create_timer(.3).timeout
	# A fresh deliberate chat gesture must still work after the close gesture.
	touch.position = root.get_final_transform()*game.chat_button.get_global_rect().get_center()
	touch.pressed = true
	Input.parse_input_event(touch.duplicate())
	touch.pressed = false
	Input.parse_input_event(touch.duplicate())
	await process_frame
	assert(game.chat_ui.panel.visible, "Intentional later chat tap must work")
	print("SHOP CLOSE REGRESSION PASS: synthetic mouse + native touch closes only shop, later chat works")
	game.started = false
	game.queue_free()
	quit(0)
