extends "res://tests/mobile_network_live.gd"
func _run() -> void:
	root.size = Vector2i(1544, 720)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = OS.get_environment("ASTER_VALE_TEST_USERNAME")
	c.password_field.text = OS.get_environment("ASTER_VALE_TEST_PASSWORD")
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Weapon fixture login: " + c.last_error): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming), "Weapon fixture enter: " + c.last_error): return
	if not check(int(c.player.level) == 50 and game.coins == 1000000, "Native level/gold not reflected in game"): return
	var previous: int = 0
	for id: int in [19, 22, 32, 37, 38, 281]:
		game._select_item("item:%d" % id)
		c.equipment_request("item:%d" % id)
		if not check(await wait_for(func() -> bool: return int((c.player.get("equipment", {}) as Dictionary).get("weapon", 0)) == id and c.session.is_idle()), "Equip/swap failed: " + c.last_error): return
		if not check(amount(id) == 0 and (previous == 0 or amount(previous) == 1), "Swap lost/duplicated a bag item"): return
		var appearance: Dictionary = game._active_hero()
		if not check(not appearance.is_empty() and int((appearance.appearance as Dictionary).weapon_graphic) == int(c.item_info("weapon").doll_graphic), "Original equipped weapon appearance missing"): return
		if not check(game.attack_button.weapon != null, "Equipped weapon attack icon missing"): return
		previous = id
	c.equipment_request("weapon")
	if not check(await wait_for(func() -> bool: return not c.is_equipped("weapon") and c.session.is_idle()), "Final Remove failed"): return
	if not check(amount(281) == 1 and game.coins == 1000000, "Unequip did not restore actual inventory"): return
	print("WEAPONS LIVE PASS: six native equips, five automatic acknowledged swaps, original appearances, bag conservation and Gold")
	game.started = false
	c.session.close()
	game.queue_free()
	await process_frame
	quit(0)
