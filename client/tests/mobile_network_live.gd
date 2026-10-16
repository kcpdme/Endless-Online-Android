extends SceneTree
var messages: Array[Dictionary] = []
var game: Node
func _initialize() -> void: call_deferred("_run")
func wait_for(predicate: Callable, seconds: float = 25.0) -> bool:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call(): return true
		await process_frame
	return false
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	quit(1)
	return false
func amount(id: int) -> int:
	for item: Dictionary in game.online.inventory_items():
		if int(item.id) == id: return int(item.amount)
	return 0
func touch(position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 17
	event.position = position
	event.pressed = pressed
	game._input(event)
func _run() -> void:
	root.size = Vector2i(1544, 720)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = OS.get_environment("ASTER_VALE_TEST_USERNAME")
	c.password_field.text = OS.get_environment("ASTER_VALE_TEST_PASSWORD")
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Fixture login: " + c.last_error): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming), "Fixture enter: " + c.last_error): return
	var gaps: Array[int] = []
	for i: int in range(8):
		if not check(await wait_for(func() -> bool: return c.can_issue_walk() and not game.moving), "Walk not ready"): return
		var before: Vector2i = game.player_tile
		var center: Vector2 = game._joystick_zone().get_center()
		var start: int = Time.get_ticks_msec()
		touch(center, true)
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 17
		drag.position = center + (Vector2(50, 50) if i % 2 == 0 else Vector2(-50, -50))
		game._input(drag)
		if not check(await wait_for(func() -> bool: return game.player_tile != before, 2), "Touch drag did not predict a step"): return
		gaps.append(Time.get_ticks_msec() - start)
		await create_timer(0.12).timeout
		touch(drag.position, false)
		if not check(game.stick == Vector2.ZERO and game.moving, "Release must clear input but finish its committed tile"): return
		if not check(await wait_for(func() -> bool: return c.pending_inputs.is_empty() and not game.moving, 4), "Native walk not confirmed"): return
		if not check(game.player_world.distance_to(game.tile_position(game.player_tile)) < 0.01, "Sprite frozen between tiles"): return
	for message: Dictionary in messages:
		var data: Dictionary = message.get("data", {}) as Dictionary
		if bool(data.get("correction", false)) and str(message.get("op", "")) != "enter": print("CORRECTION TRACE: ", JSON.stringify({"seq": data.get("position_seq"), "x": (data.get("player", {}) as Dictionary).get("x"), "y": (data.get("player", {}) as Dictionary).get("y")}))
	if not check(int(c.network_metrics.corrections) == 0, "Unexpected corrections on valid touch steps"): return
	if not check(await wait_for(func() -> bool: return c.loot_button.visible), "Rat Tail pickup control did not appear"): return
	var before: int = amount(249)
	var control: Vector2 = c.loot_button.get_global_rect().get_center()
	touch(control, true)
	touch(control, false)
	if not check(await wait_for(func() -> bool: return amount(249) == before + 1 and int(c.network_metrics.pickups) > 0), "Touch pickup did not increase Rat Tail count: " + c.last_error): return
	if not check(game.toast_label.text.contains("Picked up Rat Tail"), "Native pickup success feedback missing"): return
	game._toggle_inventory()
	game._select_item("item:249")
	var items: Array[Dictionary] = c.inventory_items()
	var bag_visible: bool = false
	for i: int in range(items.size()):
		if int(items[i].id) == 249:
			bag_visible = game.bag_slots[i].icon != null and (game.bag_slots[i].get_node("Quantity") as Label).text == str(before + 1)
	if not check(bag_visible and game.item_title.text == "Rat Tail", "Picked Rat Tail must be visible with its quantity in the inventory bag"): return
	game.inventory.hide()
	await create_timer(11.0).timeout
	c.session.request("diagnostics")
	if not check(await wait_for(func() -> bool:
		for message: Dictionary in messages:
			if str(message.get("op", "")) == "diagnostics": return true
		return false
	), "Diagnostics response missing"): return
	var diagnostics: Dictionary = {}
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "diagnostics": diagnostics = message.data as Dictionary
	if not check(int(diagnostics.get("refreshes", -1)) == 0 and int(diagnostics.get("corrections", -1)) == 0, "Idle/movement introduced extra full refresh/correction: " + str(diagnostics)): return
	var report: Dictionary = {"touch_steps": 8, "first_prediction_ms": gaps, "client": c.network_metrics, "server": diagnostics, "rat_tail_touch_pickup": true, "rat_tail_visible_in_bag_with_quantity": true, "idle_full_refresh_timer_removed": true, "result": "passed"}
	print("MOBILE NETWORK LIVE PASS: ", JSON.stringify(report))
	var report_path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  ") + "\n")
	game.started = false
	c.session.close()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
