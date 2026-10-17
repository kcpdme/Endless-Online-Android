extends "res://tests/mobile_network_live.gd"

func tap_control(control: Control) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 75
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

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
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Fixture enter: " + c.last_error): return
	await create_timer(.25).timeout
	game.menu.show()
	var entry: Button
	for child: Node in game.menu.get_child(0).get_children():
		if child is Button and child.text == "Redeem Code": entry = child
	if not check(entry != null, "Missing hamburger redeem entry"): return
	await tap_control(entry)
	await create_timer(.25).timeout
	var ui: RefCounted = game.redeem_ui
	if not check(ui.panel.visible and not game.menu.visible and game._modal_open(), "Redeem must open as an input-blocking modal"): return
	ui.code.text = "BOGUS123"
	await tap_control(ui.submit)
	if not check(await wait_for(func() -> bool: return not ui.submitting and c.session.is_idle()), "Invalid code response missing"): return
	if not check(ui.status.text.contains("not valid") and amount(375) == 0, "Invalid code changed bag"): return
	await create_timer(1.1).timeout
	var gold: int = amount(1)
	ui.code.text = "kcpd108"
	ui.confirm()
	ui.confirm()
	if not check(ui.submitting and ui.submit.disabled and not ui.code.editable, "Duplicate submission not blocked"): return
	if not check(amount(375) == 0, "Bag changed before native acknowledgement"): return
	if not check(await wait_for(func() -> bool: return not ui.submitting and c.session.is_idle()), "Redeem acknowledgement missing: " + c.last_error): return
	if not check(amount(375) == 1000 and amount(1) == gold + 50000 and amount(421) == 1, "Actual rewards absent from inventory"): return
	if not check(ui.status.text.contains("Rewards claimed") and ui.code.text.is_empty(), "Claim confirmation missing"): return
	var sends: int = 0
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "redeem_code": sends += 1
	if not check(sends == 2, "Double tap sent duplicate claim"): return
	await create_timer(1.1).timeout
	ui.code.text = "KCPD108"
	await tap_control(ui.submit)
	if not check(await wait_for(func() -> bool: return not ui.submitting and c.session.is_idle()), "Duplicate response missing"): return
	if not check(ui.status.text.contains("already redeemed") and amount(375) == 1000, "Repeat claim changed bag"): return
	game._handle_back()
	if not check(not ui.panel.visible, "Back did not close redeem dialog"): return
	game._toggle_inventory()
	if not check(game.inventory.visible, "Bag cannot reopen after redemption"): return
	var report: Dictionary = {"result": "passed", "hamburger_entry_touch": true, "modal_blocks_world": true, "invalid_code_feedback": true, "double_submission_blocked": true, "native_rewards_in_bag": true, "duplicate_rejected_without_inventory_change": true, "android_back_closes": true}
	print("REWARDS LIVE PASS: ", JSON.stringify(report))
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  ") + "\n")
	c.session.close()
	game.started = false
	game.queue_free()
	quit(0)
