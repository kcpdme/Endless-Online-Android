extends "res://tests/mobile_network_live.gd"
func key(code: int, pressed: bool, physical: bool = true) -> void:
	var event: InputEventKey = InputEventKey.new()
	if physical: event.physical_keycode = code
	else: event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func pad(point: Vector2, pressed: bool, index: int = 41) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
func _run() -> void:
	root.size = Vector2i(1544, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game._begin_play()
	game.set_process(false)
	for pair: Array in [[KEY_W,Vector2i.UP],[KEY_A,Vector2i.LEFT],[KEY_S,Vector2i.DOWN],[KEY_D,Vector2i.RIGHT],[KEY_UP,Vector2i.UP],[KEY_LEFT,Vector2i.LEFT],[KEY_DOWN,Vector2i.DOWN],[KEY_RIGHT,Vector2i.RIGHT]]:
		for physical: bool in [true,false]:
			key(int(pair[0]),true,physical)
			await process_frame
			if not check(game._input_direction() == pair[1], "Physical/logical key mapping wrong"): return
			key(int(pair[0]),false,physical)
			await process_frame
			if not check(game._input_direction() == Vector2i.ZERO, "Key release retained movement"): return
	key(KEY_W,true)
	key(KEY_D,true)
	await process_frame
	if not check(game._input_direction() == Vector2i.RIGHT, "Newest held direction must win without diagonal alternation"): return
	key(KEY_D,false)
	await process_frame
	if not check(game._input_direction() == Vector2i.UP, "Releasing newest key must resume remaining held direction"): return
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not check(game._input_direction() == Vector2i.ZERO, "Focus loss left a held keyboard direction"): return
	key(KEY_W,false)
	game.online_mode = true
	game.online.active = true
	game.chat_ui.tick()
	game.chat_ui.quick_entry.grab_focus()
	key(KEY_A,true)
	await process_frame
	if not check(game._input_direction() == Vector2i.ZERO and game.movement_keys.is_empty(), "Typing must not walk"): return
	key(KEY_A,false)
	game.chat_ui.blur_quick()
	game.chat_ui.quick_channel.grab_focus()
	key(KEY_UP,true,false)
	await process_frame
	var repeat: InputEventKey = InputEventKey.new()
	repeat.keycode = KEY_UP
	repeat.pressed = true
	repeat.echo = true
	Input.parse_input_event(repeat)
	await process_frame
	if not check(not game.chat_ui.quick_channel.get_popup().visible and game._input_direction() == Vector2i.UP, "Arrow repeat must not activate a focused HUD dropdown"): return
	key(KEY_UP,false,false)
	await process_frame
	var center: Vector2 = game._joystick_zone().get_center()
	for direction: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
		pad(center,true)
		await process_frame
		if not check(game.stick == Vector2.ZERO, "First touch must not move before dragging"): return
		var movement: InputEventScreenDrag = InputEventScreenDrag.new()
		movement.index = 41
		movement.position = center + direction * 84
		Input.parse_input_event(movement)
		await process_frame
		if not check(game.stick == direction and game._input_direction() == Vector2i(direction), "Joystick drag must select one native direction"): return
		pad(Vector2(1100,300),false)
		await process_frame
		if not check(game.stick == Vector2.ZERO and game.touch_move_id == -1, "Release outside pad must stop future steps"): return
	# Put real NPC sprite geometry under the dynamic joystick, with a spell armed.
	var at: Vector2 = game._screen_to_world(center)
	game.online.npcs.assign([{"id":2,"index":9999,"x":0,"y":0,"direction":0}])
	game.online.remote_motion["npc:9999"] = {"from":at+Vector2(0,8),"to":at+Vector2(0,8),"start":0.0}
	if not check(not game.online.map_entity_target(at).is_empty(), "NPC overlap fixture must hit real sprite geometry"): return
	game.skills_ui.armed = 1
	pad(center,true)
	await process_frame
	if not check(game.touch_move_id == 41 and game.stick == Vector2.ZERO and game.skills_ui.armed == 1 and game.online.interaction.is_empty(), "NPC/armed skill stole pad press"): return
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 41
	drag.position = Vector2(1100,300)
	Input.parse_input_event(drag)
	await process_frame
	if not check(game.touch_move_id == 41 and game.stick.length() > 0.9 and root.get_visible_rect().encloses(game.joystick.get_global_rect()), "Long drag must retain capture and keep its base inside the screen"): return
	pad(drag.position,false)
	await process_frame
	game.skills_ui.armed = 0
	game.menu.show()
	pad(center,true)
	await process_frame
	if not check(game.touch_move_id == -1, "Pad must respect open dialogs"): return
	pad(center,false)
	game.menu.hide()
	if not check(game.joystick.z_index > 0 and game.joystick.radius >= 125, "Joystick must be large and above world graphics"): return
	print("MOVEMENT CONTROLS PASS: WASD/arrows physical+logical, newest held key, release/focus/typing, dynamic stick without arrows, NPC overlap, armed skill priority, captured outside drag, modal protection")
	game.started = false
	game.queue_free()
	quit()
