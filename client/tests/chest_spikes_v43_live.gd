extends SceneTree
var game: Node
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func wait_for(condition: Callable, seconds: float = 12.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if condition.call(): return true
		await process_frame
	return false
func check(ok: bool, why: String) -> bool:
	checks += 1
	print("PASS " if ok else "FAIL ", why)
	if not ok: game.started = false; quit(1)
	return ok
func tap_at(point: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 79; event.position = point; event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame
func capture(name: String) -> void:
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func warp(tile: Vector2i) -> bool:
	var c: Node = game.online
	c.session.request("chat_send", {"channel":"local","message":"$warp 136 %d %d" % [tile.x,tile.y]})
	return await wait_for(func() -> bool: return c.session.is_idle() and int(c.player.get("map_id",0)) == 136 and Vector2i(int(c.player.x),int(c.player.y)) == tile)
func select_item(list: ItemList, id: int) -> bool:
	for i: int in range(list.item_count):
		if int(list.get_item_metadata(i)) == id:
			list.select(i); list.item_selected.emit(i); return true
	return false
func run() -> void:
	root.size = Vector2i(1544,720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("EO_V43_FIXTURE"))) as Dictionary
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	var c: Node = game.online
	c.show_login(); c.host_field.text = "127.0.0.1"; c.port_field.value = 18182
	c.username_field.text = str(f.username); c.password_field.text = str(f.password); c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Actual login succeeds with private dev fixture"): return
	c.character_list.select(0); c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Native Welcome enables actual Android UI"): return
	if not check(await warp(Vector2i(56,85)), "Disposable admin fixture reaches the actual unmodified chest map"): return
	c.request_step(Vector2i.UP)
	if not check(await wait_for(func() -> bool: return not game.moving and int(c.player.y) == 84 and c.pending_inputs.is_empty()), "Normal native walk reaches the adjacent spike tile"): return
	for i: int in range(12):
		c.request_step(Vector2i.UP); await process_frame
	if not check(game.player_tile == Vector2i(56,84) and not game.moving and int(c.player.y) == 84, "Repeated walk input cannot cross the Turtle chest"): return
	var spike: Dictionary = {"tile":Vector2i(56,84),"layer":"objects"}
	if not check(await wait_for(func() -> bool: return game._decoration_visible(spike)), "Native server raises timed spikes in actual client"): return
	await capture("turtle-spikes-raised")
	if not check(await wait_for(func() -> bool: return not game._decoration_visible(spike)), "Native pulse expires and spikes retract"): return
	await capture("turtle-spikes-retracted")
	var point: Vector2 = game.get_global_transform_with_canvas() * (game.tile_position(Vector2i(56,83)) + Vector2(0,-8))
	await tap_at(point)
	var ui: RefCounted = game.services_ui
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "chest" and c.session.is_idle()), "Touch on Turtle chest receives native ACK and opens loot UI"): return
	await capture("turtle-chest-open")
	var before: int = c.bag_amount(1)
	if not check(select_item(ui.left,1), "Original starter Gold is available to deposit"): return
	ui.quantity.value = 7
	await tap_at(ui.primary.get_global_rect().get_center())
	if not check(await wait_for(func() -> bool: return c.session.is_idle() and c.bag_amount(1) == before-7), "Actual Deposit touch updates bag from native ACK"): return
	if not check(select_item(ui.right,1), "Deposited Gold appears in native chest contents"): return
	await tap_at(ui.secondary.get_global_rect().get_center())
	if not check(await wait_for(func() -> bool: return c.session.is_idle() and c.bag_amount(1) == before), "Actual Take touch returns acknowledged Gold to bag"): return
	ui.close()
	if not check(await wait_for(func() -> bool: return c.session.is_idle()), "Chest closes cleanly"): return
	await create_timer(0.8).timeout
	if not check(await warp(Vector2i(7,56)), "Private fixture reaches the formerly invisible approach chest"): return
	point = game.get_global_transform_with_canvas() * (game.tile_position(Vector2i(7,55)) + Vector2(0,-8))
	await capture("approach-chest-visible")
	await tap_at(point)
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "chest" and int(ui.state.get("x",-1)) == 7 and int(ui.state.get("y",-1)) == 55), "Restored chest artwork opens the actual existing chest"): return
	var report: Dictionary = {"result":"passed","checks":checks,"native_map_modified":false,"turtle_collision":true,"touch_open_and_deposit_take":true,"native_timed_spikes":true,"restored_approach_chest":true,"operator_accounts_used":false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	c.session.close();game.started = false;game.queue_free();await process_frame
	print("CHEST SPIKES V43 LIVE PASS ",checks);quit()
