extends SceneTree
var game: Node
var c: Node
var checks: int = 0
var failed: bool = false
var opens: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks += 1
	if not ok: failed = true; push_error(why)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < end:
		if test.call(): return true
		await process_frame
	return false
func key(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_W; event.pressed = pressed
	Input.parse_input_event(event)
func touch(point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 85; event.position = root.get_final_transform() * point; event.pressed = pressed
	Input.parse_input_event(event)
func finish() -> void:
	if game != null: game.queue_free()
	await process_frame; await process_frame
	quit(1 if failed else 0)
func run() -> void:
	root.size = Vector2i(1544,720)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_INN_FIXTURE")))
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	c = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void:
		if message.get("op","") == "chest_open" and bool(message.get("ok",false)): opens += 1
	)
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = fixture.account.username; c.password_field.text = fixture.account.password; c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Chest fixture login failed"): finish(); return
	c.character_list.select(0); c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Chest fixture entry failed"): finish(); return
	var ui: RefCounted = game.services_ui
	check(game.player_tile == Vector2i(6,24), "Fixture must start one walk step before chest adjacency")
	key(true)
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "chest"), "Held walk must open the actual native chest"): key(false); finish(); return
	key(false)
	check(game.player_tile == Vector2i(6,23) and int(c.player.x) == 6 and int(c.player.y) == 23, "Client and native server stay outside the chest tile")
	check(not game.moving and c.pending_inputs.is_empty() and game.movement_keys.is_empty(), "Chest waits for the walk ACK and consumes movement")
	check(opens == 1 and int(c.network_metrics.moves) == 1, "One approaching walk must produce one native chest open")
	var before_gold: int = c.bag_amount(1)
	var chest_gold: int = 0
	for item: Dictionary in ui.state.get("items",[]):
		if int(item.id) == 1: chest_gold = int(item.amount)
	for index: int in range(ui.left_rows.size()):
		if int(ui.left_rows[index].id) == 1: ui.left.select(index)
	ui._selected(); ui.quantity.value = 50; ui._primary()
	if not check(await wait_for(func() -> bool: return c.session.is_idle() and c.bag_amount(1) == before_gold - 50), "Native chest deposit did not confirm bag Gold"): finish(); return
	ui.close(); await wait_for(func() -> bool: return c.session.is_idle())
	await create_timer(.2).timeout
	var origin: Vector2 = game._joystick_zone().get_center()
	touch(origin, true); await process_frame
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 85; drag.position = root.get_final_transform() * (origin + Vector2(0,-84)); Input.parse_input_event(drag)
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "chest"), "Joystick must reopen the adjacent native chest"): touch(origin,false); finish(); return
	touch(origin,false)
	check(game.player_tile == Vector2i(6,23) and game.touch_move_id == -1 and game.stick == Vector2.ZERO, "Chest bump consumes the joystick gesture")
	var stored: int = 0
	for index: int in range(ui.right_rows.size()):
		if int(ui.right_rows[index].id) == 1: stored = int(ui.right_rows[index].amount); ui.right.select(index)
	check(stored == chest_gold + 50, "Reopened chest must contain native deposited Gold")
	ui._selected(); ui._secondary()
	if not check(await wait_for(func() -> bool: return c.session.is_idle() and c.bag_amount(1) == before_gold + chest_gold), "Native whole-stack withdrawal did not return Gold"): finish(); return
	await create_timer(.25).timeout
	check(opens == 2, "Holding movement must not spam extra native chest opens")
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("chest-walk-open.png"))
	ui.close(); c.log_out()
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"native_keyboard_approach_and_bump":true,"native_joystick_bump":true,"native_confirmed_adjacency":true,"native_chest_open_count":opens,"native_gold_deposit_reopen_and_withdraw":true,"blocked_chest_tile_preserved":true,"held_input_consumed":true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n");print("CHEST WALK LIVE: ",JSON.stringify(report));finish()
