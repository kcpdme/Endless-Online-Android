extends SceneTree
## Exercise the rendered mobile shop and original stats panel against real EO packets.
var failed: bool = false
func _initialize() -> void: call_deferred("_run")
func wait_for(predicate: Callable, timeout: float = 25.0) -> bool:
	var until: int = Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call(): return true
		await process_frame
	return false
func require_true(value: bool, reason: String) -> bool:
	if value: return true
	push_error(reason)
	quit(1)
	return false
func _run() -> void:
	root.size = Vector2i(1544, 720)
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var online: Node = game.online
	online.show_login()
	online.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	online.username_field.text = OS.get_environment("ASTER_VALE_TEST_USERNAME")
	online.password_field.text = OS.get_environment("ASTER_VALE_TEST_PASSWORD")
	online._authenticate("login")
	if not require_true(await wait_for(func() -> bool: return online.character_box.visible), "Economy fixture login failed"): return
	online.character_list.select(0)
	online._enter_selected()
	if not require_true(await wait_for(func() -> bool: return online.active and not online.npcs.is_empty()), "Economy fixture enter failed"): return
	if not require_true(int(game.world.id) == 193, "Expected fresh fixture in Cyndi's shop"): return
	var npc: Dictionary = {}
	for row: Dictionary in online.npcs:
		if int(row.id) == 100: npc = row
	if not require_true(not npc.is_empty(), "Native Cyndi NPC missing"): return
	var npc_tile: Vector2i = Vector2i(int(npc.x), int(npc.y))
	var hit: Vector2i = online.map_target(game.tile_position(npc_tile) + Vector2(0, -34), game._world_tile(game.tile_position(npc_tile) + Vector2(0, -34)))
	if not require_true(hit == npc_tile, "Tapping Cyndi sprite must target her actual tile"): return
	online.map_click(hit)
	if not require_true(await wait_for(func() -> bool: return game.shop_ui.panel.visible), "Tap/approach did not open native shop: " + online.last_error): return
	var shop: RefCounted = game.shop_ui
	if not require_true(str(shop.shop.name) == "Cyndi Shop" and game._modal_open(), "Wrong shop catalogue or modal state"): return
	for i: int in range(shop.offers.size()):
		if int(shop.offers[i].id) == 21: shop.list.select(i)
	shop._selected()
	shop.quantity.value = 2
	shop.transact()
	if not require_true(await wait_for(func() -> bool: return shop.held(21) == 2 and game.coins == 950), "Shop Buy acknowledgement failed: " + online.last_error): return
	shop.mode = "sell"
	shop.refresh()
	for i: int in range(shop.offers.size()):
		if int(shop.offers[i].id) == 258: shop.list.select(i)
	shop._selected()
	shop.transact()
	if not require_true(await wait_for(func() -> bool: return shop.held(258) == 3 and game.coins == 955), "Shop Sell acknowledgement failed"): return
	shop.mode = "craft"
	shop.refresh()
	shop.list.select(0)
	shop._selected()
	shop.transact()
	if not require_true(await wait_for(func() -> bool: return shop.held(21) == 3 and shop.held(258) == 1), "Shop Craft acknowledgement failed"): return
	game._handle_back()
	if not require_true(not shop.panel.visible, "Android Back did not close shop"): return
	game._toggle_inventory()
	if not require_true((game.bag_slots[0].get_node("Quantity") as Label).text == "955" and game.bag_slots[0].text == "", "Gold corner badge missing or shifting icon"): return
	game.inventory.hide()
	game.stats_ui.show_stats()
	await process_frame
	if not require_true(game.stats_ui.add_buttons[0].size.y <= 32, "Original stats point controls must not overlap adjacent rows"): return
	if not require_true((game.stats_ui.classic_fields.gold as Label).text == "955", "Original stats panel shows stale Gold"): return
	game._handle_back()
	game.stats_ui.show_item("item:21")
	if not require_true(game.stats_ui.item_heading.text.contains("×3") and game.stats_ui.item_body.text.contains("Damage  1–2"), "EIF item detail quantity or weapon stats incorrect"): return
	game.stats_ui.hide()
	game.started = false
	online.session.close()
	game.queue_free()
	await process_frame
	await process_frame
	print("ECONOMY LIVE PASS: approach/tap shop, native Buy/Sell/Craft, original stats artwork values, corner Gold quantity, EIF Dagger details and stack quantity, Android Back")
	quit(0)
