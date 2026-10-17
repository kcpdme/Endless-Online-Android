extends "res://tests/mobile_network_live.gd"
func tap(control: Control, index: int) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index;event.position = control.get_global_rect().get_center();event.pressed = true
	Input.parse_input_event(event);await process_frame
	event = event.duplicate();event.pressed = false
	Input.parse_input_event(event);await process_frame
func _run() -> void:
	root.size = Vector2i(1544,720)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	var fixture: Dictionary = fixtures.actor as Dictionary
	game = load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c: Node = game.online;c.show_login();c.host_field.text = "127.0.0.1";c.port_field.value = 18089
	c.username_field.text = str(fixture.username);c.password_field.text = str(fixture.password);c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible),"Native login failed"): return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()),"Native enter failed"): return
	game.music.stop()
	var classes: Array[String] = []
	for row: Array in [[41,"ring1","ring2"],[39,"armlet1","armlet2"],[54,"bracer1","bracer2"]]:
		var id: int = int(row[0]);var first: String = str(row[1]);var second: String = str(row[2])
		game.character_panel.hide();game.inventory.show();game._select_item("item:%d" % id);game._refresh_ui();await process_frame
		if not check(c.bag_amount(id) == 2,"Native fixture must own TWO actual bag copies"): return
		await tap(game.equip_button,81)
		if not check(await wait_for(func() -> bool: return int(c.player.equipment.get(first,0)) == id and c.bag_amount(id) == 1 and c.session.is_idle()),"First Equip tap was not acknowledged for " + first): return
		game._refresh_ui();await process_frame
		await tap(game.equip_button,82)
		if not check(await wait_for(func() -> bool: return int(c.player.equipment.get(second,0)) == id and c.bag_amount(id) == 0 and c.session.is_idle()),"Second actual Equip tap was not acknowledged for " + second): return
		if not check(int(c.player.equipment.get(first,0)) == id,"Second ring must not remove first"): return
		game._toggle_paperdoll();await process_frame
		if not check((game.paperdoll.slots[first] as Button).icon != null and (game.paperdoll.slots[second] as Button).icon != null,"Native paired items must appear in BOTH paperdoll spaces"): return
		await tap(game.paperdoll.slots[second],83);await tap(game.paperdoll.slots[second],84)
		if not check(await wait_for(func() -> bool: return int(c.player.equipment.get(second,0)) == 0 and c.bag_amount(id) == 1 and c.session.is_idle()),"Native double tap failed to remove second only"): return
		if not check(int(c.player.equipment.get(first,0)) == id,"Removing second must preserve first native copy"): return
		classes.append(first.trim_suffix("1"))
	var report: Dictionary = {"result":"passed","real_native_gateway_and_server":true,"actual_touch_equip_button_used":true,"paired_categories":classes,"identical_bag_copy_can_equip_second_slot":true,"server_ack_updates_bag_quantities":true,"both_original_paperdoll_slots_visible":true,"double_tap_removes_secondary_only":true,"first_copy_preserved":true,"operator_accounts_modified":false}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("PAIRED EQUIPMENT V38 LIVE PASS: ",JSON.stringify(report))
	c.session.close();game.started = false;game.queue_free();await process_frame;quit()
