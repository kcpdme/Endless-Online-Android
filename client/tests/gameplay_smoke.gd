extends SceneTree
## Exercises the actual gameplay loop headlessly, restoring any existing player save.
var save_before: String = ""
var had_save: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var save_path: String = "user://aster_vale_save.json"
	had_save = FileAccess.file_exists(save_path)
	if had_save: save_before = FileAccess.get_file_as_string(save_path)
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	assert(game.content_ready, "Real imported content must load")
	game._reset_progress()
	game.started = true
	game.welcome.hide()
	game.online.panel.hide()
	assert(not quit_on_go_back, "Android Back must not terminate the game")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(game.menu.visible, "Android Back opens the in-game menu")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(not game.menu.visible, "Android Back closes the current menu")
	game._toggle_inventory()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(not game.inventory.visible, "Android Back closes inventory without exiting")
	var spawn: Vector2i = game.player_tile
	assert(game._walkable(spawn), "Spawn must be walkable")
	assert(game._screen_direction(Vector2.RIGHT) == Vector2i.RIGHT, "Right is one native tile axis")
	assert(game._screen_direction(Vector2.UP) == Vector2i.UP, "Up is one native tile axis")
	assert(game._screen_direction(Vector2(1, 1)) == Vector2i.DOWN, "Joystick snaps to four native directions")
	var corner: Vector2i = spawn + Vector2i(1, 0)
	game.blocked[corner] = true
	assert(not game._can_step(spawn, Vector2i(1, -1)), "Diagonal motion cannot cut blocked corners")
	game.blocked.erase(corner)
	var stick_center: Vector2 = game._joystick_zone().get_center()
	game._joystick_begin(stick_center, 9)
	assert(game.stick == Vector2.ZERO, "First touch is neutral until the thumb drags")
	game._cancel_movement()
	_touch(game, 3, true, stick_center)
	_drag(game, 3, stick_center + Vector2(84, 0))
	assert(game.stick == Vector2.RIGHT and game.touch_move_id == 3, "Dynamic joystick captures a drag")
	assert(game.joystick.radius >= 125 and game._joystick_zone().size.x >= 340, "Joystick and activation area must have generous targets")
	_drag(game, 3, stick_center + Vector2(420, -240))
	assert(game.touch_move_id == 3 and game.route.is_empty(), "Long drags must retain ownership without targeting the world")
	assert(root.get_visible_rect().encloses(game.joystick.get_global_rect()), "Dynamic circle must stay inside the screen")
	_touch(game, 7, true, Vector2(700, 350))
	assert(game.touch_move_id == 3 and game.route.is_empty() and game.owned_touches.has(7), "An extra map touch cannot redirect a captured joystick")
	_touch(game, 7, false, Vector2(700, 350))
	game._process(0.01)
	game._process(0.04)
	_touch(game, 4, true, game.attack_button.get_global_rect().get_center())
	assert(game.touch_move_id == 3 and game.attack_clock > 0.0, "A second action finger leaves movement captured")
	_touch(game, 4, false, game.attack_button.get_global_rect().get_center())
	_touch(game, 3, false, stick_center + Vector2(200, -30))
	assert(game.stick == Vector2.ZERO and game.touch_move_id == -1 and not game.moving and game.route.is_empty(), "Release outside the stick immediately cancels movement")
	var released_tile: Vector2i = game.player_tile
	var released_world: Vector2 = game.player_world
	for tick: int in range(8): game._process(0.2)
	assert(game.player_tile == released_tile and game.player_world == released_world, "No tiles or interpolation continue after release")
	_touch(game, 3, true, stick_center)
	_drag(game, 3, stick_center + Vector2(0, -65))
	game._toggle_inventory()
	assert(game.stick == Vector2.ZERO and game.touch_move_id == -1 and not game.moving, "Opening a modal clears stick capture")
	game._toggle_inventory()
	game._process(0.2)
	assert(not game.moving, "Closing the modal cannot revive a stale finger")
	_touch(game, 5, true, stick_center)
	_drag(game, 5, stick_center + Vector2(65, 0))
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(game.stick == Vector2.ZERO and game.touch_move_id == -1, "Focus loss clears stick capture")
	assert(game.bag_slots.size() == 24 and game.equipment_slots.size() == 15, "Bag and original paperdoll expose their separate slots")
	assert(game.inventory != game.character_panel and game.paperdoll.background.resource_path == game.manifest.paperdoll.background, "Character screen uses the actual original paperdoll bitmap")
	game._toggle_paperdoll()
	assert(game.character_panel.visible and not game.inventory.visible, "Character icon opens only the paperdoll")
	game._toggle_inventory()
	assert(game.inventory.visible and not game.character_panel.visible, "Bag opens separately and closes paperdoll")
	game._toggle_inventory()
	# HUD touches run through the engine too: no synthesized mouse double-toggle.
	var bag_press: InputEventScreenTouch = InputEventScreenTouch.new()
	bag_press.index = 13
	bag_press.pressed = true
	bag_press.position = game.bag_button.get_global_rect().get_center()
	Input.parse_input_event(bag_press)
	await process_frame
	assert(game.inventory.visible and not game.character_panel.visible, "Native bag icon opens exactly one bag screen")
	bag_press.pressed = false
	Input.parse_input_event(bag_press)
	await process_frame
	game.inventory.hide()
	var person_press: InputEventScreenTouch = InputEventScreenTouch.new()
	person_press.index = 14
	person_press.pressed = true
	person_press.position = game.character_button.get_global_rect().get_center()
	Input.parse_input_event(person_press)
	await process_frame
	assert(game.character_panel.visible and not game.inventory.visible, "Native person icon opens the original paperdoll")
	person_press.pressed = false
	Input.parse_input_event(person_press)
	await process_frame
	var close_press: InputEventScreenTouch = InputEventScreenTouch.new()
	close_press.index = 15
	close_press.pressed = true
	close_press.position = game.paperdoll.get_node("ClassicOk").get_global_rect().get_center()
	Input.parse_input_event(close_press)
	await process_frame
	close_press.pressed = false
	Input.parse_input_event(close_press)
	await process_frame
	assert(not game.character_panel.visible, "The original paperdoll OK button closes its screen")
	game._select_item("armor")
	game._toggle_equip()
	assert(not game.armor_equipped, "Starting armor can move into the bag")
	game._toggle_equip()
	assert(game.armor_equipped, "Starting armor can be worn again")
	var dressed_frame: Dictionary = game._frame(game._active_hero(), "south", "idle")
	game.armor_equipped = false
	var undressed_frame: Dictionary = game._frame(game._active_hero(), "south", "idle")
	assert(dressed_frame.path != undressed_frame.path, "Removing armor selects a real different sprite")
	game.armor_equipped = true
	game._select_item("boots")
	game._toggle_equip()
	assert(not game.boots_equipped, "Starting boots can move into the bag")
	game._toggle_equip()
	assert(game.boots_equipped, "Starting boots can be worn again")
	game.boots_equipped = false
	var barefoot_frame: Dictionary = game._frame(game._active_hero(), "south", "idle")
	assert(dressed_frame.path != barefoot_frame.path, "Removing boots selects a real different sprite")
	game.boots_equipped = true
	game._select_item("weapon")
	game.attack_clock = 0.0
	# Route through Godot itself, including emulate_mouse_from_touch and Button GUI handling.
	game.enemy_tile = game.player_tile + Vector2i(1, 0)
	game.enemy_health = 10
	var action_point: Vector2 = game.attack_button.get_global_rect().get_center()
	var held_press: InputEventScreenTouch = InputEventScreenTouch.new()
	held_press.index = 7
	held_press.pressed = true
	held_press.position = action_point
	Input.parse_input_event(held_press)
	await process_frame
	assert(game.enemy_health == 9, "Full native touch dispatch attacks exactly once on press")
	# Rapid tapping cannot bypass the slower recovery; the swing ends before recovery.
	game._process(0.35)
	game._attack()
	assert(game.enemy_health == 9 and game.swing_clock == 0.0, "A quick second tap cannot deal damage or loop the swing")
	game._process(0.35)
	game._attack()
	assert(game.enemy_health == 9, "Attacks remain blocked after seven tenths of a second")
	game._process(0.25)
	assert(game.enemy_health == 8 and game.attack_touch_id == 7, "Holding repeats one attack after the slow recovery: health=%d pointer=%d clock=%f" % [game.enemy_health, game.attack_touch_id, game.attack_clock])
	var held_release: InputEventScreenTouch = InputEventScreenTouch.new()
	held_release.index = 7
	held_release.pressed = false
	held_release.position = action_point
	Input.parse_input_event(held_release)
	await process_frame
	assert(game.enemy_health == 8 and game.attack_touch_id == -1, "Lifting the attack finger stops hold attack without an extra hit")
	game._process(1.0)
	assert(game.enemy_health == 8, "Attacking stays stopped after release")
	game._attack()
	assert(game.enemy_health == 7, "An attack is accepted again after recovery")
	assert(game.attack_button.contains_point(action_point), "Circular action accepts its center")
	assert(not game.attack_button.contains_point(game.attack_button.global_position + Vector2(1, 1)), "Circular action rejects the square corner")
	assert(game.attack_button.size.x == 164.0, "Attack touch target is enlarged")
	# Menus and drags stop repetition and cannot leave a held action behind.
	game.attack_clock = 0.0
	_touch(game, 10, true, action_point)
	game._toggle_paperdoll()
	assert(game.attack_touch_id == -1 and not game.attack_button.holding, "Paperdoll cancels held attack")
	_touch(game, 10, false, action_point)
	game._toggle_paperdoll()
	game.attack_clock = 0.0
	_touch(game, 11, true, action_point)
	_drag(game, 11, action_point + Vector2(-200, -100))
	assert(game.attack_touch_id == -1, "Sliding away cancels held attack")
	_touch(game, 11, false, action_point + Vector2(-200, -100))
	game.attack_clock = 0.0
	_touch(game, 12, true, action_point)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(game.attack_touch_id == -1 and game.owned_touches.is_empty(), "Focus loss clears held attack and touch ownership")
	# A lethal native touch cannot collect its own drop through the synthesized mouse.
	game.attack_clock = 0.0
	game.enemy_health = 1
	var coins_before: int = game.coins
	var lethal_press: InputEventScreenTouch = InputEventScreenTouch.new()
	lethal_press.index = 8
	lethal_press.pressed = true
	lethal_press.position = action_point
	Input.parse_input_event(lethal_press)
	await process_frame
	assert(game.loot_visible and game.coins == coins_before, "One lethal touch leaves loot for a separate pickup action")
	assert(game.attack_touch_id == 8, "Attack hold remains captured until the actual finger is lifted")
	game._process(0.95)
	assert(game.loot_visible and game.coins == coins_before, "Holding a weapon does not turn into automatic loot pickup")
	var lethal_release: InputEventScreenTouch = InputEventScreenTouch.new()
	lethal_release.index = 8
	lethal_release.pressed = false
	lethal_release.position = action_point
	Input.parse_input_event(lethal_release)
	await process_frame
	var pickup: InputEventScreenTouch = InputEventScreenTouch.new()
	pickup.index = 9
	pickup.pressed = true
	pickup.position = action_point
	Input.parse_input_event(pickup)
	await process_frame
	assert(game.coins == coins_before + 5 and not game.loot_visible, "A separate pickup touch works during attack recovery")
	pickup.pressed = false
	Input.parse_input_event(pickup)
	await process_frame
	game._reset_progress()
	game.enemy_health = 3
	game._place_enemy()
	game.attack_clock = 0.0
	game._request_path(game.enemy_tile)
	assert(not game.route.is_empty(), "Training enemy must be reachable")
	for tick: int in range(20): game._process(0.26)
	assert(game.player_tile == game.enemy_tile, "Pathfinding reaches the enemy")
	for hit: int in range(3):
		game._attack()
		game._process(0.95)
	assert(game.kills == 1 and game.loot_visible, "Three unarmed attacks create loot")
	game._collect_loot(true)
	assert(game.coins == 5 and game.has_blade, "Loot gives a blade and five coins")
	game._toggle_equip()
	assert(game.equipped, "Blade can be equipped")
	game._save_progress()
	game.coins = 0
	game.equipped = false
	game._load_save()
	assert(game.coins == 5 and game.equipped, "Progress survives save and reload")
	# An old version1 save has no clothing flags; its worn outfit must survive migration.
	var old_save: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	old_save.store_string(JSON.stringify({"version": 1, "map_id": int(game.world.id), "position": [spawn.x, spawn.y], "coins": 30, "kills": 6, "has_blade": true, "equipped": true}))
	old_save.close()
	game.armor_equipped = false
	game.boots_equipped = false
	game._load_save()
	assert(game.coins == 30 and game.kills == 6 and game.equipped and game.armor_equipped and game.boots_equipped, "Version1 save migration preserves progress and worn outfit")
	game._reset_progress()
	assert(game.coins == 0 and not game.has_blade and game.player_tile == spawn, "Reset clears progress")
	if had_save:
		var restored: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		restored.store_string(save_before)
		restored.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("GAMEPLAY SMOKE PASS: content, joystick pointer/drag/release, multitouch, modal/focus cancellation, corner collision, movement, combat, loot, paperdoll equipment, save/load, reset")
	await create_timer(0.30).timeout
	game.queue_free()
	await create_timer(.2).timeout
	await process_frame
	quit(0)

func _touch(game: Node, finger: int, pressed: bool, point: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = finger
	event.pressed = pressed
	event.position = point
	game._input(event)

func _drag(game: Node, finger: int, point: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = finger
	event.position = point
	game._input(event)
