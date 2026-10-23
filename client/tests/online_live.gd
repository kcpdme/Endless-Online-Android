extends SceneTree
## Requires a real local gateway+etheos. It creates test accounts unless env credentials are supplied.
## Run with isolated XDG_DATA_HOME. Never prints or stores account passwords.
var failure: String = ""
var original_save_existed: bool = false
var original_save_bytes: PackedByteArray = PackedByteArray()
var fixture_written: bool = false
var active_game: Node

func _initialize() -> void:
	call_deferred("_run")

func _wait_until(condition: Callable, seconds: float = 25.0) -> bool:
	var limit: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if condition.call(): return true
		await process_frame
	return false

func _letters(count: int) -> String:
	var output: String = ""
	for index: int in range(count): output += String.chr(97 + randi_range(0, 25))
	return output

func _require(condition: bool, reason: String) -> bool:
	if condition: return true
	push_error(reason)
	_restore_save()
	if active_game != null: active_game.started = false
	quit(1)
	return false

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var game: Node = scene.instantiate()
	root.add_child(game)
	active_game = game
	await process_frame
	var controller: Node = game.online
	var save_path: String = "user://aster_vale_save.json"
	original_save_existed = FileAccess.file_exists(save_path)
	original_save_bytes = FileAccess.get_file_as_bytes(save_path) if original_save_existed else PackedByteArray()
	game.coins = 137
	game.kills = 9
	game._save_progress()
	fixture_written = true
	var save_existed: bool = true
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	controller.show_login()
	if not OS.get_environment("ASTER_VALE_TEST_HOST").is_empty(): controller.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	if not OS.get_environment("ASTER_VALE_TEST_PORT").is_empty(): controller.port_field.value = int(OS.get_environment("ASTER_VALE_TEST_PORT"))
	var provided: bool = not OS.get_environment("ASTER_VALE_TEST_USERNAME").is_empty()
	controller.username_field.text = OS.get_environment("ASTER_VALE_TEST_USERNAME") if provided else "av" + _letters(10)
	controller.password_field.text = OS.get_environment("ASTER_VALE_TEST_PASSWORD") if provided else "Dev" + _letters(8) + "42"
	controller._authenticate("login" if provided else "register")
	if not _require(await _wait_until(func() -> bool: return controller.character_box.visible), "Real account login/character listing failed: " + controller.last_error): return
	if controller.selected_characters.is_empty():
		controller.character_name_field.text = "av" + _letters(8)
		controller._create_character()
		if not _require(await _wait_until(func() -> bool: return not controller.selected_characters.is_empty()), "Real character creation failed: " + controller.last_error): return
	controller._close_panel()
	controller.show_login()
	if not _require(controller.character_box.visible and not controller.auth_box.visible, "Canceling character selection must retain its still-live authenticated session"): return
	controller.character_list.select(0)
	controller._enter_selected()
	if not _require(await _wait_until(func() -> bool: return controller.active and controller.streaming and not controller.player.is_empty()), "Real Welcome/world entry failed: " + controller.last_error): return
	if not _require(game.online_mode and int(controller.player.map_id) == 5, "Online character must enter the actually imported map5"): return
	if OS.get_environment("ASTER_VALE_TEST_WARP") != "1" and not _require(not controller.npcs.is_empty(), "Expected real server NPCs in the map snapshot"): return
	if OS.get_environment("ASTER_VALE_TEST_WARP") == "1":
		if not _require(game.player_tile == Vector2i(33, 1), "Warp fixture must begin beside Aeven's real north exit"): return
		if not await _travel(game, controller, Vector2i(0, -1), 4, Vector2i(19, 47)): return
		if not await _travel(game, controller, Vector2i(0, 1), 5, Vector2i(33, 1)): return
		print("LIVE MAP ROUNDTRIP PASS: Aeven -> map4 -> Aeven, server and rendered geometry agree")
	game._toggle_inventory()
	controller._process(0.01)
	if not _require(not controller.server_label.visible, "Connection status must not overprint inventory"): return
	game._toggle_inventory()
	controller._process(0.01)
	if not _require(not controller.server_label.visible, "Connection status must remain outside the gameplay HUD"): return
	var before: Vector2i = game.player_tile
	if not _require(await _wait_until(func() -> bool: return controller.can_issue_walk()), "Live server did not become ready for walking"): return
	var step: Vector2i = Vector2i(1, 0)
	if not game._can_step(before, step): step = Vector2i(0, 1)
	controller.request_step(step)
	if not _require(game.player_tile == before + step and game.moving, "Prediction must begin synchronously before any server reply"): return
	if not _require(await _wait_until(func() -> bool: return not controller.waiting_for_walk and game.player_tile != before), "Real authoritative server movement was not confirmed"): return
	if not _require(game.player_tile == before + step, "Accepted server coordinate does not match the requested tile"): return
	if not _require(await _wait_until(func() -> bool: return controller.session.is_idle() and controller.pending_inputs.is_empty()), "Live connection stalled before equipment"): return
	game._select_item("item:21")
	controller.equipment_request("item:21")
	if not _require(await _wait_until(func() -> bool: return controller.is_equipped("weapon")), "Real weapon equip was not acknowledged: " + controller.last_error): return
	if not _require(await _wait_until(func() -> bool: return controller.session.is_idle()), "Live connection stalled before unequip"): return
	controller.equipment_request("weapon")
	if not _require(await _wait_until(func() -> bool: return not controller.is_equipped("weapon")), "Real weapon unequip was not acknowledged"): return
	game._save_progress()
	if not _require(FileAccess.file_exists(save_path) == save_existed, "Online state created or removed the private offline save"): return
	if save_existed and not _require(FileAccess.get_file_as_bytes(save_path) == saved_bytes, "Online state overwrote private offline save bytes"): return
	controller.log_out()
	if not _require(not controller.active and not game.started, "Logout must stop gameplay"): return
	controller.show_login()
	if not _require(controller.auth_box.visible and not controller.character_box.visible and controller.selected_characters.is_empty(), "Logging back in must show fresh authentication, not stale characters"): return
	_restore_save()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	print("ONLINE LIVE PASS: real registration/login, character creation/select, Welcome, authoritative map5/NPCs/movement, equip/unequip, online logout and legacy save isolation")
	quit(0)

func _restore_save() -> void:
	if not fixture_written: return
	var path: String = "user://aster_vale_save.json"
	if original_save_existed:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file != null: file.store_buffer(original_save_bytes)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	fixture_written = false

func _travel(game: Node, controller: Node, step: Vector2i, map_id: int, tile: Vector2i) -> bool:
	if not _require(await _wait_until(func() -> bool: return controller.can_issue_walk()), "Server stalled before map travel"): return false
	controller.request_step(step)
	if not _require(await _wait_until(func() -> bool: return int(game.world.id) == map_id and game.player_tile == tile and not controller.waiting_for_walk), "Server/rendered map transition failed: " + controller.last_error): return false
	return _require(game.player_world == game.tile_position(tile) and not game.moving, "Map arrival must snap the camera/player to the confirmed destination")
