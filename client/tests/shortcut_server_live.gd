extends SceneTree
var game: Node
var received: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func wait_for(predicate: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
	return false
func check(ok: bool, reason: String) -> bool:
	if not ok:
		push_error(reason)
		quit(1)
	return ok
func run() -> void:
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SHORTCUT_FIXTURE")))
	var mode: String = OS.get_environment("ASTER_VALE_SHORTCUT_MODE")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame; await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: received.append(message))
	c.show_login(); c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = f.username; c.password_field.text = f.password; c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Native login failed: " + c.last_error): return
	for index: int in range(c.selected_characters.size()):
		if c.selected_characters[index].name == f.character_name: c.character_list.select(index)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle() and c.shortcuts.queued.is_empty()), "Native entry/sync failed: " + c.last_error): return
	var quick: RefCounted = game.quick_items
	var skills: RefCounted = game.skills_ui
	var bag_before: String = JSON.stringify(c.player.inventory)
	var spells_before: String = JSON.stringify(c.player.spells)
	if mode == "seed":
		quick.selected_slot = 0; quick.assign(375)
		quick.selected_slot = 1; quick.assign(331)
		for slot: int in range(2):
			skills.selected = 5 if slot == 0 else 1
			var pressed: bool = false
			for button: Node in skills.panel.find_children("*", "Button", true, false):
				if button.text == "Set slot %d" % (slot + 1): button.pressed.emit(); pressed = true
			if not check(pressed, "Skill assignment UI button missing"): return
		if not check(await wait_for(func() -> bool: return c.session.is_idle() and c.shortcuts.queued.is_empty() and c.shortcuts.inflight.is_empty()), "Assignment not acknowledged"): return
	if not check(quick.slots == [375,331] and skills.slots == [5,1], "Four assignments did not " + mode): return
	if not check(JSON.stringify(c.player.inventory) == bag_before and JSON.stringify(c.player.spells) == spells_before, "Assignment changed native items/spells"): return
	var save_acks: int = 0
	for message: Dictionary in received:
		if message.get("op") == "shortcuts_set":
			save_acks += 1
			if not check(bool(message.ok), "Server rejected shortcut"): return
	if mode == "restore" and not check(save_acks == 0, "Fresh install overwrote saved server values"): return
	print("SHORTCUT SERVER LIVE PASS: ", JSON.stringify({"mode":mode,"four_slots":true,"save_acknowledgements":save_acks,"native_inventory_and_spells_unchanged":true,"fresh_user_directory":true}))
	c.session.close(); game.started = false; game.queue_free()
	await process_frame; await process_frame; quit(0)
