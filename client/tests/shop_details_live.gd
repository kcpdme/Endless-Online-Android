extends "res://tests/skills_live.gd"
## Actual shop UI at the supported 1280x720 minimum and wide phone viewport.
func choose(id: int) -> bool:
	var ui: RefCounted = game.shop_ui
	for index: int in range(ui.offers.size()):
		if int(ui.offers[index].id) == id:
			ui.list.select(index)
			ui.list.item_selected.emit(index)
			return true
	return false

func resnapshot() -> bool:
	var before: int = messages.size()
	game.online.session.request("refresh")
	return await wait_for(func() -> bool:
		for index: int in range(before, messages.size()):
			if str(messages[index].get("op", "")) == "refresh": return game.online.session.is_idle()
		return false
	)

func swipe_up(point: Vector2) -> void:
	var press: InputEventScreenTouch = InputEventScreenTouch.new()
	press.index = 73
	press.position = point
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	for step: int in range(8):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 73
		drag.relative = Vector2(0, -22)
		drag.position = point + Vector2(0, -22 * (step + 1))
		Input.parse_input_event(drag)
		await process_frame
	press.pressed = false
	press.position = point + Vector2(0, -176)
	Input.parse_input_event(press)
	await process_frame
	await process_frame

func tap_visible_offer(id: int) -> bool:
	var ui: RefCounted = game.shop_ui
	for y: int in range(15, int(ui.list.size.y) - 15, 4):
		var local_point: Vector2 = Vector2(180, y)
		var row: int = ui.list.get_item_at_position(local_point, true)
		if row < 0 or int(ui.offers[row].id) != id: continue
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.index = 73
		event.position = ui.list.get_global_transform_with_canvas() * local_point
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
		await process_frame
		return int(ui.offers[ui.list.get_selected_items()[0]].id) == id
	return false

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SHOP_FIXTURE"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, f), "Shop fixture login: " + c.last_error): return
	var marble: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 87: marble = npc
	if not check(not marble.is_empty(), "Marble absent"): return
	c.map_click(Vector2i(int(marble.x), int(marble.y)))
	var ui: RefCounted = game.shop_ui
	if not check(await wait_for(func() -> bool: return ui.panel.visible and c.session.is_idle()), "Marble did not open: " + c.last_error): return
	if not check(root.get_visible_rect().encloses((ui.panel.get_child(0) as Control).get_global_rect()), "Shop must fit 1280x720"): return
	if not check(choose(360), "War Axe unavailable"): return
	if not check(ui.list.get_item_text(0) == "War Axe  ·  2000", "Price must be compact with no gold-each suffix"): return
	ui.quantity.value = 2
	if not check(ui.total.text == "Total: 4000" and ui.action.text == "Buy ×2", "Quantity total/action not updated"): return
	if not check(await resnapshot(), "Native resnapshot failed"): return
	if not check(int(ui.quantity.value) == 2 and int(ui.offers[ui.list.get_selected_items()[0]].id) == 360, "World updates reset the selected item/quantity"): return
	await capture("v15-buy-details")
	var gold: int = amount(1)
	ui.action.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(360) == 2 and amount(1) == gold - 4000 and c.session.is_idle()), "Native buy ×2 failed: " + c.last_error): return
	ui.mode = "sell"
	ui.refresh()
	if not check(ui.offers.size() >= 15 and choose(360), "Large sell catalog did not retain its selectable item details"): return
	ui.quantity.value = 2
	if not check(ui.total.text == "Total: 400" and ui.description.text.contains("Damage 2–2"), "Sell details or total missing"): return
	await capture("v15-sell-details")
	ui.action.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(360) == 0 and amount(1) == gold - 3600 and c.session.is_idle()), "Native sell ×2 failed: " + c.last_error): return
	ui.mode = "craft"
	ui.refresh()
	if not check(choose(311), "Lotus Armor recipe absent"): return
	await process_frame
	await process_frame
	if not check(ui.ingredient_rows.size() == 4 and not ui.action.disabled, "All four original materials, including Gold, must be shown"): return
	for row: Control in ui.ingredient_rows:
		if not check(ui.details_scroll.get_global_rect().encloses(row.get_global_rect()), "A recipe material is clipped below the right detail viewport"): return
	if not check(ui.item_title.text == "Lotus Armor (M)" and ui.description.text.contains("Armor +2"), "Craft result details missing"): return
	await capture("v15-four-material-recipe")
	await swipe_up(ui.list.get_global_rect().position + Vector2(210, 320))
	if not check(ui.list.get_v_scroll_bar().value > 0, "Catalog must scroll with a finger swipe"): return
	if not check(int(ui.offers[ui.list.get_selected_items()[0]].id) == 311, "A swipe must not select another catalog row"): return
	if not check(await tap_visible_offer(313), "A native tap must select the visible Pilotte recipe"): return
	if not check(ui.material_totals(ui.offers[ui.list.get_selected_items()[0]])[322] == 11 and ui.action.disabled, "Repeated ingredient IDs must add up before reporting readiness"): return
	await capture("v15-missing-materials")
	if not check(choose(406), "Long detail recipe absent"): return
	await process_frame
	await process_frame
	ui.list.get_v_scroll_bar().value = ui.list.get_v_scroll_bar().max_value
	await swipe_up(ui.details_scroll.get_global_rect().position + Vector2(220, 245))
	if not check(ui.details_scroll.scroll_vertical > 0, "Item details must scroll with a finger swipe"): return
	await process_frame
	var left_scroll: float = ui.list.get_v_scroll_bar().value
	var right_scroll: int = ui.details_scroll.scroll_vertical
	if not check(left_scroll > 0 and right_scroll > 0, "Both panes must scroll independently"): return
	if not check(await resnapshot(), "Browse resnapshot failed"): return
	await process_frame
	await process_frame
	if not check(absf(ui.list.get_v_scroll_bar().value - left_scroll) < 1.0 and ui.details_scroll.scroll_vertical == right_scroll, "World refresh resets catalog or detail scroll position"): return
	if not check(choose(311) and not ui.action.disabled, "Ready recipe did not re-enable"): return
	var count: int = amount(311)
	gold = amount(1)
	ui.action.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(311) == count + 1 and amount(318) == 0 and amount(320) == 0 and amount(322) == 0 and amount(1) == gold - 250 and c.session.is_idle()), "Native four-material craft failed: " + c.last_error): return
	if not check(ui.action.disabled and ui.status.text.contains("Missing"), "Craft acknowledgement must update owned/needed rows and readiness"): return
	root.size = Vector2i(1544, 720)
	await process_frame
	await process_frame
	if not check(root.get_visible_rect().encloses((ui.panel.get_child(0) as Control).get_global_rect()), "Shop does not fit wide phone viewport"): return
	await capture("v15-wide-craft-result")
	var report: Dictionary = {"result": "passed", "compact_price_amounts": true, "native_finger_swipe_in_both_panes": true, "swipe_preserves_selection_and_tap_selects": true, "dedicated_buy_sell_craft_details": true, "four_material_rows_visible_at_1280x720": true, "independent_catalog_details_scroll_preserved_across_native_snapshot": true, "quantity_and_selection_preserved_across_native_snapshot": true, "duplicate_ingredient_totals_and_missing_state": true, "native_buy_sell_and_four_material_craft": true, "wide_phone_layout": true, "operator_accounts_modified": false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("SHOP DETAILS LIVE PASS: ", JSON.stringify(report))
	c.session.close()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
