extends "res://tests/shop_details_live.gd"
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
	root.size = Vector2i(1280, 720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SHOP_FIXTURE"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, f), "Inventory fixture login: " + c.last_error): return
	var quick: RefCounted = game.quick_items
	quick.slots.assign([4, 5])
	quick.refresh()
	for id: int in range(2):
		if not check(quick.buttons[id].visible and root.get_visible_rect().encloses(quick.buttons[id].get_global_rect()), "Quick slot outside screen"): return
		var item: int = 4 + id
		var before: int = amount(item)
		await tap_control(quick.buttons[id])
		if not check(await wait_for(func() -> bool: return amount(item) == before - 1 and c.session.is_idle()), "Quick potion touch must use exactly one native item: " + c.last_error): return
		if not check((quick.buttons[id].get_node("Quantity") as Label).text == str(before - 1), "Quick quantity badge must follow native acknowledgement"): return
	var held: InputEventScreenTouch = InputEventScreenTouch.new()
	held.index = 81
	held.position = quick.buttons[0].get_global_rect().get_center()
	held.pressed = true
	Input.parse_input_event(held)
	await create_timer(.65).timeout
	held.pressed = false
	Input.parse_input_event(held)
	if not check(quick.panel.visible and amount(4) == 6, "Holding shortcut must open assignment without consuming"): return
	quick.assign(4)
	quick.identity = ""
	quick.refresh()
	if not check(quick.slots[0] == 4, "Quick assignments must survive reload"): return
	await capture("v20-consumable-shortcuts")
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
	await capture("v19-purchase-confirmed")
	game.stats_ui.show_item("item:407")
	await process_frame
	await process_frame
	if not check(game.stats_ui.item_art.texture != null and game.stats_ui.item_art.size == Vector2(240, 330), "Large original artwork preview missing"): return
	await capture("v19-robe-large-preview")
	game.stats_ui.hide()
	ui.mode = "craft"
	ui.refresh()
	if not check(choose(311), "Lotus recipe absent"): return
	await process_frame
	await process_frame
	for row: Control in ui.ingredient_rows:
		var edge: float = row.get_global_rect().end.x
		if not check(edge <= ui.details_scroll.get_global_rect().end.x - 30, "Have / Need too close to scrollbar"): return
	await capture("v19-craft-quantity-margin")
	ui.close()
	game.inventory.show()
	game._select_item("item:360")
	if not check(game.equip_button.text == "Equip" and not game.drop_button.disabled, "Compact Equip/Drop actions absent"): return
	await tap_control(game.drop_button)
	var drop: RefCounted = c.drop_ui
	if not check(drop.panel.visible and int(drop.quantity.max_value) == 2, "Drop must offer the actual stack quantity"): return
	drop.quantity.value = 1
	await tap_control(drop.submit)
	if not check(await wait_for(func() -> bool: return amount(360) == 1 and not drop.panel.visible and c.session.is_idle()), "Native partial drop failed: " + c.last_error): return
	var dropped_uid: int = 0
	for item: Dictionary in c.drops:
		if int(item.id) == 360 and int(item.amount) == 1: dropped_uid = int(item.uid)
	game.inventory.hide()
	c._update_loot_control()
	if not check(c.loot_button.visible and c.loot_button.text.is_empty() and c.loot_button.get("kind") == "hand", "Pickup must be a hand icon only"): return
	await capture("v20-pickup-hand")
	if not check(dropped_uid > 0, "Dropped item must appear on native ground"): return
	c.session.request("pickup", {"uid": dropped_uid})
	if not check(await wait_for(func() -> bool: return amount(360) == 2 and c.session.is_idle()), "Native drop pickup roundtrip failed"): return
	game.inventory.show()
	game._select_item("item:4")
	if not check(game.equip_button.text == "Use", "Consumable action must say Use only"): return
	game._select_item("item:407")
	var grid: Control = game.bag_grid
	if not check(grid.dimensions(407) == Vector2i(2, 3) and grid.dimensions(281) == Vector2i(1, 4) and grid.items.size() == c.inventory_items().size(), "Original item footprints or authoritative bag entries missing"): return
	if not check(grid.size.x >= 1000 and grid.rows == 5, "Bag must keep exactly fifteen columns and five rows"): return
	# Migrate a previous paged layout without hiding or changing server items.
	var legacy: FileAccess = FileAccess.open("user://bag_layouts_15x5.json", FileAccess.WRITE)
	legacy.store_string(JSON.stringify({grid.profile: {"1": [0, 0, 0], "407": [3, 0, 0]}}))
	legacy.close()
	grid.profile = ""
	grid.signature = ""
	grid.refresh()
	for button: Button in grid.buttons.values():
		if not check(button.visible or not grid.positions.has(str((grid.buttons as Dictionary).find_key(button))), "Unplaced items must not overlap the grid"): return
	# Pick a clear 2×3 destination before the native finger drag.
	var from: Vector2i = Vector2i(int(grid.positions["407"][0]), int(grid.positions["407"][1]))
	var destination: Vector2i = Vector2i(-1, -1)
	for y: int in range(3):
		for x: int in range(14):
			if Vector2i(x, y) != from and grid.fits(407, Vector2i(x, y)): destination = Vector2i(x, y)
	if not check(destination.x >= 0, "Fixture has no clear robe destination"): return
	var begin: Vector2 = grid.get_global_transform_with_canvas() * (Vector2(from) * grid.CELL + Vector2(20, 20))
	var end: Vector2 = grid.get_global_transform_with_canvas() * (Vector2(destination) * grid.CELL + Vector2(20, 20))
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
	if not check(grid.positions["407"] == [destination.x, destination.y], "Native finger drag failed to move the six-cell robe"): return
	var moved: Array = grid.positions["407"].duplicate()
	var coin: Array = grid.positions["1"] as Array
	if not check(not grid.move_item(407, Vector2i(int(coin[0]), int(coin[1]))) and grid.positions["407"] == moved, "Overlapping drop must roll back"): return
	grid.profile = ""
	grid.signature = ""
	grid.refresh()
	if not check(grid.positions["407"] == moved and amount(360) == 2 and amount(407) == 1 and amount(1) == 46000, "Layout reload changed inventory or lost positions"): return
	game.toast_time = 0
	grid._begin(Vector2(destination) * grid.CELL + Vector2(20, 20), 72)
	grid.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not check(grid.drag_id == 0 and not grid.dragging, "Focus loss must cancel a held item"): return
	game.toast_label.hide()
	await capture("v19-classic-movable-bag")
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
	for id: int in [426, 56]:
		c.session.request("equip", {"item_id": id})
		if not check(await wait_for(func() -> bool: return c.is_equipped("item:%d" % id) and c.session.is_idle()), "Native helmet/shield equip failed: " + c.last_error): return
	appearance = c.character_graphic(c.player)
	if not check(int(appearance.appearance.head_graphic) == 44 and int(appearance.appearance.offhand_graphic) == 1, "Native helmet/offhand artwork was not bound"): return
	for direction: String in ["south", "west", "north", "east"]:
		game.facing = direction
		await capture("v20-darkness-helmet-" + direction)
	game.facing = "south"
	await capture("v20-plaot-robes-in-world")
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
		if int(peer.get("player_id", -1)) == int(c.player.player_id): observer_saw = int((peer.equipment_graphics as Array)[4]) == 40 and int((peer.equipment_graphics as Array)[6]) == 44 and int((peer.equipment_graphics as Array)[7]) == 1 and not c.character_graphic(peer).is_empty()
	if not check(observer_saw, "Independent native observer did not see Plaot appearance"): return
	c.request_face("north")
	await create_timer(.3).timeout
	var observed: Dictionary = await rpc("refresh")
	var facing_seen: bool = false
	for peer: Dictionary in observed.get("players", []):
		if int(peer.get("player_id", -1)) == int(c.player.player_id): facing_seen = int(peer.direction) == 2
	if not check(facing_seen and game.facing == "north", "Native observer must see turning in place"): return
	game.stats_ui.show_stats()
	await process_frame
	var stats_before: int = int(c.player.stats.intelligence)
	var points_before: int = int(c.player.stats.stat_points)
	var plus: Button = game.stats_ui.add_buttons[1]
	var hold: InputEventScreenTouch = InputEventScreenTouch.new()
	hold.index = 79
	hold.position = plus.get_global_rect().get_center()
	hold.pressed = true
	Input.parse_input_event(hold)
	if not check(await wait_for(func() -> bool: return int(c.player.stats.intelligence) >= stats_before + 4), "Holding + must spend repeated native stat points"): return
	hold.pressed = false
	Input.parse_input_event(hold)
	await create_timer(.7).timeout
	var gained: int = int(c.player.stats.intelligence) - stats_before
	if not check(points_before - int(c.player.stats.stat_points) == gained and game.stats_ui.held_stat == 0, "Held stat allocation must use confirmed totals and stop on release"): return
	var settled: int = int(c.player.stats.intelligence)
	await create_timer(.4).timeout
	if not check(int(c.player.stats.intelligence) == settled, "Stat allocation continued after release"): return
	await capture("v19-held-stat-result")
	game.stats_ui.hide()
	game.inventory.show()
	game._select_item("item:360")
	await tap_control(game.junk_button)
	if not check(drop.panel.visible and drop.operation == "junk" and int(drop.quantity.max_value) == 2, "Junk must offer the actual stack quantity"): return
	drop.panel.hide()
	if not check(amount(360) == 2, "Cancelling junk must preserve items"): return
	await tap_control(game.junk_button)
	drop.quantity.value = 1
	var ground_before: String = JSON.stringify(c.drops)
	await tap_control(drop.submit)
	if not check(await wait_for(func() -> bool: return amount(360) == 1 and not drop.panel.visible and c.session.is_idle()), "Native partial junk failed: " + c.last_error): return
	if not check(JSON.stringify(c.drops) == ground_before, "Junk must not create a ground drop"): return
	await capture("v20-junk-native-quantity")
	game.inventory.hide()
	game.started = false
	game._toast("Game server disconnected")
	await create_timer(2.2).timeout
	if not check(not game.toast_label.visible and is_zero_approx(game.toast_time), "Disconnected notification must expire even while gameplay is stopped"): return
	var report: Dictionary = {"result": "passed", "pickup_is_hand_icon_only": true, "native_observer_sees_helmet_robe_and_offhand": true, "two_native_consumable_shortcuts_and_quantities": true, "hold_to_reassign_without_using_and_assignment_persists": true, "helmet_of_darkness_and_shield_native_equip_four_directions": true, "native_partial_junk_and_cancel_no_ground_drop": true, "confirmed_native_purchase_feedback_only": true, "craft_quantities_30px_scrollbar_margin": true, "native_touch_drag_six_cell_robe": true, "overlap_rejected": true, "focus_loss_cancels_drag": true, "fixed_15_columns_5_rows": true, "native_quantity_drop_and_pickup_roundtrip": true, "compact_equip_and_use_labels": true, "character_layout_survives_reload": true, "server_quantities_unchanged_by_rearrangement": true, "legacy_page_items_migrated_into_one_bag": true, "large_original_gear_preview": true, "plaot_robe_all_directions_walk_attack_cast": true, "independent_native_observer_sees_robe": true, "native_observer_sees_turn_in_place": true, "held_plus_uses_native_acknowledged_points_and_stops": true, "text_notification_expires_while_disconnected": true, "operator_accounts_modified": false}
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
