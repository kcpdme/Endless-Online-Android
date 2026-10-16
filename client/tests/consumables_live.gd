extends "res://tests/mobile_network_live.gd"
## Real bag buttons, native Item_Reply and rendered scroll map transition.
func choose_item(id: int) -> bool:
	var items: Array[Dictionary] = game.online.inventory_items()
	for i: int in range(items.size()):
		if int(items[i].id) == id:
			game.online.select_bag_item(i)
			return true
	return false

func capture(label: String) -> void:
	var directory: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

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
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Fixture entry: " + c.last_error): return
	if not check(game.stats_ui.vitals.level_label == "Lv. 2" and game.stats_ui.vitals.experience_fraction > 0.36 and game.stats_ui.vitals.experience_fraction < 0.38, "HUD level/cumulative EXP incorrect"): return
	await capture("v12-level-exp")
	game._toggle_inventory()
	if not check(choose_item(2) and game.equip_button.text.begins_with("Use ") and not game.equip_button.disabled, "Potion must expose an enabled Use action"): return
	await capture("v12-bag-use")
	var hp: int = int(c.player.hp)
	var count: int = amount(2)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(2) == count - 1 and c.session.is_idle()), "Health potion quantity not acknowledged: " + c.last_error): return
	if not check(int(c.player.hp) > hp and game.stats_ui.vitals.hp == int(c.player.hp), "Native potion HP must reach both player and HUD"): return
	if not check(game.inventory.visible, "Drinking a potion should preserve the bag"): return
	if not check(choose_item(3), "Mana potion absent"): return
	var tp: int = int(c.player.tp)
	count = amount(3)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(3) == count - 1 and c.session.is_idle()), "Mana potion not acknowledged"): return
	if not check(int(c.player.tp) > tp and game.stats_ui.vitals.tp == int(c.player.tp), "Native mana potion did not update TP"): return
	if not check(choose_item(375), "Big health potion absent"): return
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return int(c.player.hp) == int(c.player.max_hp) and c.session.is_idle()), "Big potion did not fill HP"): return
	if not check(choose_item(2), "Small health potion absent after use"): return
	count = amount(2)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return c.last_error.contains("already full") and c.session.is_idle()), "Full-HP potion refusal missing"): return
	if not check(amount(2) == count and not game.equip_button.disabled, "Refused potion must preserve its stack and restore the Use control"): return
	if not check(choose_item(62), "Beach scroll absent"): return
	count = amount(62)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return int(game.world.id) == 13 and c.session.is_idle() and amount(62) == count - 1), "Scroll did not complete native warp and map load: " + c.last_error): return
	if not check(game.player_tile == Vector2i(12, 19) and not game.inventory.visible and not c.transition_pending, "Scroll must render the native destination with settled controls"): return
	await capture("v12-scroll-beach")
	game._toggle_inventory()
	choose_item(62)
	count = amount(62)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return c.last_error.contains("already at") and c.session.is_idle()), "Same-destination scroll refusal missing"): return
	if not check(amount(62) == count, "Same-destination scroll was incorrectly consumed"): return
	game.chat_ui.open()
	game.chat_ui.channel.select(0)
	game.chat_ui.entry.text = "Hello nearby"
	game.chat_ui.send_message()
	if not check(not game.chat_ui.panel.visible, "Nearby Send must close the dialog immediately"): return
	if not check(await wait_for(func() -> bool: return c.chat_bubbles.has(int(c.player.player_id)) and c.session.is_idle()), "Native Nearby send must retain the local speech bubble"): return
	game._toggle_inventory()
	choose_item(65)
	count = amount(65)
	game.equip_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return int(game.world.id) == 5 and c.session.is_idle() and amount(65) == count - 1), "Native Recall scroll did not return home: " + c.last_error): return
	var report: Dictionary = {"result": "passed", "real_native_item_use_from_bag": true, "health_and_mana_hp_tp_stack_updates": true, "full_hp_potion_not_consumed": true, "beach_scroll_warp_and_rendered_destination": true, "same_destination_scroll_not_consumed": true, "recall_scroll_native_home_warp": true, "nearby_send_closes_dialog_and_shows_bubble": true, "level_and_next_level_exp_hud": true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("CONSUMABLES LIVE PASS: ", JSON.stringify(report))
	c.session.close()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
