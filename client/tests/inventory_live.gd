extends "res://tests/shop_details_live.gd"
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SHOP_FIXTURE"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, f), "Inventory fixture login: " + c.last_error): return
	var marble: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 87: marble = npc
	if not check(not marble.is_empty(), "Marble absent"): return
	c.map_click(Vector2i(int(marble.x), int(marble.y)))
	var ui: RefCounted = game.shop_ui
	if not check(await wait_for(func() -> bool: return ui.panel.visible and c.session.is_idle()), "Shop absent"): return
	if not check(choose(360), "War Axe unavailable"): return
	ui.quantity.value = 2
	game.toast_label.hide()
	game.toast_label.text = ""
	ui.action.pressed.emit()
	if not check(not game.toast_label.text.contains("Purchased"), "A queued request must not claim a purchase"): return
	if not check(await wait_for(func() -> bool: return amount(360) == 2 and c.session.is_idle()), "Native buy failed"): return
	if not check(game.toast_label.visible and game.toast_label.z_index > ui.panel.z_index and game.toast_label.text.contains("Purchased War Axe ×2") and game.toast_label.text.contains("bag"), "Confirmed purchase must announce the item and its bag destination above the shop"): return
	await capture("v16-purchase-confirmed")
	game.stats_ui.show_item("item:407")
	await process_frame
	await process_frame
	if not check(game.stats_ui.item_art.texture != null and game.stats_ui.item_art.size == Vector2(240, 330), "Large original artwork preview missing"): return
	await capture("v16-robe-large-preview")
	game.stats_ui.hide()
	ui.mode = "craft"
	ui.refresh()
	if not check(choose(311), "Lotus recipe absent"): return
	await process_frame
	await process_frame
	for row: Control in ui.ingredient_rows:
		var edge: float = row.get_global_rect().end.x
		if not check(edge <= ui.details_scroll.get_global_rect().end.x - 30, "Have / Need too close to scrollbar"): return
	await capture("v16-craft-quantity-margin")
	ui.close()
	game.inventory.show()
	game._select_item("item:407")
	var grid: Control = game.bag_grid
	if not check(grid.dimensions(407) == Vector2i(2, 3) and grid.dimensions(281) == Vector2i(1, 4) and grid.items.size() == c.inventory_items().size(), "Original item footprints or authoritative bag entries missing"): return
	if not check(grid.pages >= 2, "Overflow belongings must remain reachable"): return
	# Reserve a clear page in this deliberately crowded dev fixture, then move by finger.
	if not check(grid.move_item(407, grid.pages, Vector2i.ZERO), "Could not place robe on an additional bag page"): return
	grid.page = int(grid.positions["407"][0])
	grid._layout()
	var from: Vector2i = Vector2i(int(grid.positions["407"][1]), int(grid.positions["407"][2]))
	var destination: Vector2i = Vector2i(-1, -1)
	for y: int in range(4):
		for x: int in range(14):
			if Vector2i(x, y) != from and grid.fits(407, grid.page, Vector2i(x, y)): destination = Vector2i(x, y)
	if not check(destination.x >= 0, "Fixture has no clear robe destination"): return
	var begin: Vector2 = grid.get_global_transform_with_canvas() * (Vector2(from) * 48 + Vector2(20, 20))
	var end: Vector2 = grid.get_global_transform_with_canvas() * (Vector2(destination) * 48 + Vector2(20, 20))
	var touch_event: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_event.index = 72
	touch_event.position = begin
	touch_event.pressed = true
	Input.parse_input_event(touch_event)
	await process_frame
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 72
	drag.position = end
	drag.relative = end - begin
	Input.parse_input_event(drag)
	await process_frame
	touch_event.position = end
	touch_event.pressed = false
	Input.parse_input_event(touch_event)
	await process_frame
	if not check(grid.positions["407"] == [grid.page, destination.x, destination.y], "Native finger drag failed to move the six-cell robe"): return
	var moved: Array = grid.positions["407"].duplicate()
	var coin: Array = grid.positions["1"] as Array
	if not check(not grid.move_item(407, int(coin[0]), Vector2i(int(coin[1]), int(coin[2]))) and grid.positions["407"] == moved, "Overlapping drop must roll back"): return
	grid.profile = ""
	grid.signature = ""
	grid.refresh()
	if not check(grid.positions["407"] == moved and amount(360) == 2 and amount(407) == 1 and amount(1) == 46000, "Layout reload changed inventory or lost positions"): return
	grid.page = int(moved[0])
	grid._layout()
	game.toast_time = 0
	grid._begin(Vector2(destination) * 48 + Vector2(20, 20), 72)
	grid.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not check(grid.drag_id == 0 and not grid.dragging, "Focus loss must cancel a held item"): return
	grid.move_to_next_bag()
	if not check(int(grid.positions["407"][0]) > int(moved[0]), "Move to next bag must preserve and relocate the selected item"): return
	grid.page = 0
	grid._layout()
	await capture("v16-classic-movable-bag")
	game.inventory.hide()
	# Equip on the isolated native character; observe independently, never log into Skylar.
	if int((c.player.equipment as Dictionary).get("armor", 0)) > 0:
		c.session.request("unequip", {"item_id": int(c.player.equipment.armor)})
		if not check(await wait_for(func() -> bool: return int(c.player.equipment.armor) == 0 and c.session.is_idle()), "Fixture armor removal failed"): return
	for id: int in [80, 281]:
		c.session.request("equip", {"item_id": id})
		if not check(await wait_for(func() -> bool: return c.is_equipped("item:%d" % id) and c.session.is_idle()), "Fixture boot/weapon equip failed"): return
	c.session.request("equip", {"item_id": 407})
	if not check(await wait_for(func() -> bool: return int(c.player.equipment.armor) == 407 and c.session.is_idle()), "Native Plaot equip failed"): return
	var appearance: Dictionary = c.character_graphic(c.player)
	if not check(int(appearance.appearance.armor_graphic) == 40 and (appearance.layers as Array).size() >= 4, "Plaot robe did not bind original armor graphic40"): return
	for direction: String in ["south", "west", "north", "east"]:
		for state: String in ["idle", "frames", "attack", "cast"]:
			if not check(not game._frame(appearance, direction, state).is_empty(), "Missing dressed pose"): return
	game.facing = "south"
	await capture("v16-plaot-robes-in-world")
	actor = (load("res://scripts/online_session.gd") as Script).new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void: actor_replies[int(message.get("id", -1))] = message)
	actor.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return actor.connected), "Observer transport failed"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login", {"username": f.observer.username, "password": f.observer.password})
	var entry: Dictionary = await rpc("enter", {"character_id": (login.characters as Array)[0].id})
	var observer_saw: bool = false
	for peer: Dictionary in entry.get("players", []):
		if int(peer.get("player_id", -1)) == int(c.player.player_id): observer_saw = int((peer.equipment_graphics as Array)[4]) == 40 and not c.character_graphic(peer).is_empty()
	if not check(observer_saw, "Independent native observer did not see Plaot appearance"): return
	var report: Dictionary = {"result": "passed", "confirmed_native_purchase_feedback_only": true, "craft_quantities_30px_scrollbar_margin": true, "native_touch_drag_six_cell_robe": true, "overlap_rejected": true, "focus_loss_cancels_drag": true, "move_selected_to_next_bag": true, "character_layout_survives_reload": true, "server_quantities_unchanged_by_rearrangement": true, "all_inventory_entries_reachable_across_pages": true, "large_original_gear_preview": true, "plaot_robe_all_directions_walk_attack_cast": true, "independent_native_observer_sees_robe": true, "operator_accounts_modified": false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("INVENTORY LIVE PASS: ", JSON.stringify(report))
	actor.close()
	c.session.close()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
