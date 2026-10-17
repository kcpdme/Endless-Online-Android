extends "res://tests/skills_live.gd"
## Feed native touches through the engine (including its emulated mouse), not map_click.
func finger(point: Vector2, down: bool, id: int = 41) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = down
	Input.parse_input_event(event)

func npc_head(npc: Dictionary) -> Vector2:
	var definition: Dictionary = (game.online.catalog.npcs as Dictionary).get(str(int(npc.id)), {}) as Dictionary
	var appearance: Dictionary = (game.manifest.characters.npcs as Dictionary).get(str(int(definition.get("graphic", 0))), {}) as Dictionary
	var layout: Dictionary = game.online.npc_name_layout(appearance, game.online._facing(npc.get("direction", 0)), false)
	return game.online._remote_position("npc:%d" % int(npc.index), game.tile_position(Vector2i(int(npc.x), int(npc.y)))) + (layout.head as Vector2) + Vector2(0, 5)

func _run() -> void:
	root.size = Vector2i(1544, 720)
	var fs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, fs.shop), "Marble fixture login: " + c.last_error): return
	if not check(int(game.world.id) == 125 and game.player_tile == Vector2i(6, 4), "Fixture must match Skylar's customer-side position"): return
	var marble: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 87: marble = npc
	if not check(not marble.is_empty() and int(marble.x) < 5, "Marble must be on the other side of the impassable counter"): return
	var world_point: Vector2 = npc_head(marble)
	var point: Vector2 = game.get_global_transform_with_canvas() * world_point
	if not check(str(c.map_entity_target(world_point).get("kind", "")) == "npc", "Visible Marble head must resolve to the NPC"): return
	await capture("v14-marble-counter")
	finger(point, true)
	await process_frame
	finger(point, false)
	if not check(await wait_for(func() -> bool: return game.shop_ui.panel.visible and c.session.is_idle()), "Head tap must open Marble across counter: " + c.last_error): return
	if not check(game.shop_ui.title.text == "Marble Shop" and game.player_tile == Vector2i(6, 4) and game.route.is_empty() and not game.joystick.active, "Opening a counter shop must never path toward the blocked NPC tile"): return
	await capture("v14-marble-open")
	var gold: int = amount(1)
	game.shop_ui.action.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(360) == 1 and amount(1) == gold - 2000 and c.session.is_idle()), "Native buy across counter failed: " + c.last_error): return
	game.shop_ui.mode = "sell"
	game.shop_ui.refresh()
	game.shop_ui.action.pressed.emit()
	if not check(await wait_for(func() -> bool: return amount(360) == 0 and amount(1) == gold - 1800 and c.session.is_idle()), "Native sell across counter failed: " + c.last_error): return
	if not check(int(c.network_metrics.moves) == 0 and int(c.network_metrics.corrections) == 0, "Shop tap must not attempt any counter movement"): return
	game.shop_ui.close()
	c.session.close()
	c._on_closed("Switching isolated test fixture")
	await create_timer(.7).timeout
	messages.clear()
	if not check(await login_fixture(c, fs.combat), "Combat fixture login: " + c.last_error): return
	var rat: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 2 and game._distance(game.player_tile, Vector2i(int(npc.x), int(npc.y))) <= 10:
			rat = npc
			if npc_head(npc).x < game.player_world.x: break
	if not check(not rat.is_empty(), "No real native rat within skill range"): return
	world_point = npc_head(rat)
	# Keep the NPC left of the character, outside the reserved movement area.
	# Only the camera changes; native world positions do not.
	game.camera.offset = world_point - game.player_world + Vector2(180, 0)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await process_frame
	await process_frame
	point = game.get_global_transform_with_canvas() * npc_head(rat)
	if not check(not game._joystick_zone().has_point(point) and point.x < root.get_visible_rect().size.x / 2.0, "Left-side spell target must remain accessible outside the movement area"): return
	var ui: RefCounted = game.skills_ui
	ui.press(ui.slots.find(4))
	await process_frame
	if not check(ui.armed == 4, "Small Fire not armed"): return
	var tp: int = int(c.player.tp)
	var before: Vector2i = game.player_tile
	await capture("v14-left-zone-target")
	finger(point, true)
	await process_frame
	finger(point, false)
	if not check(not ui.casting.is_empty() and not game.joystick.active and game.touch_move_id == -1, "Armed skill target was stolen by joystick capture"): return
	if not check(await wait_for(func() -> bool: return ui.casting.is_empty() and int(c.player.tp) == tp - 1), "Native left-zone skill cast did not hit: " + c.last_error): return
	var casts: int = 0
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "spell_cast": casts += 1
	if not check(casts == 1 and game.player_tile == before and game.route.is_empty(), "Emulated mouse duplicated the cast or moved the player"): return
	await capture("v14-left-zone-cast")
	var empty: Vector2 = game._joystick_zone().get_center()
	if not check(game._joystick_zone().has_point(empty), "Movement touch must be in its reserved area"): return
	finger(empty, true, 42)
	await process_frame
	if not check(game.joystick.active and game.touch_move_id == 42, "Empty left-side ground must still start dynamic joystick"): return
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 42
	drag.position = empty + Vector2(70, 0)
	Input.parse_input_event(drag)
	await process_frame
	finger(drag.position, false, 42)
	await process_frame
	if not check(not game.joystick.active and game.stick == Vector2.ZERO and game.touch_move_id == -1, "Joystick release must still stop input"): return
	var report: Dictionary = {"result": "passed", "marble_head_touch_from_skylar_map125_tile6_4": true, "counter_shop_opens_without_path_or_movement": true, "native_buy_and_sell_across_counter": true, "real_touch_skill_target_left_of_character_outside_movement_area": true, "exactly_one_cast_with_emulated_mouse": true, "empty_ground_dynamic_joystick_and_release_preserved": true, "operator_accounts_modified": false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("TOUCH INTERACTIONS LIVE PASS: ", JSON.stringify(report))
	c.session.close()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
