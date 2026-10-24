extends SceneTree
var failed: bool = false
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func tap_at(point: Vector2, index: int = 86) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.set_process(false);game.welcome.hide();game.online.panel.hide();game.started = true;game.online_mode = true
	var c: Node = game.online;c.set_process(false);c.active = true
	c.player = {"player_id":100,"map_id":136,"x":56,"y":84,"hp":100,"maxhp":100}
	game.load_map(136);game.player_tile = Vector2i(56,84);game.player_world = game.tile_position(game.player_tile);game.camera.position = game.player_world
	var map: Control = game.minimap
	map.expanded = true;map._resize();map.set_process(false);map._process(0.0)
	check(map.visible and map.expanded, "Minimap is visible by default during gameplay")
	check(map.atlas != null and map.atlas.get_width() == 243, "Original nine-color minimap atlas is loaded")
	check(map.tile_kind(Vector2i(56,83)) == 7 and map.tile_kind(Vector2i(7,55)) == 7, "Both real chests are blue interaction markers")
	check(map.tile_kind(Vector2i(7,54)) == 3, "Native walls are solid minimap cells")
	check(map.tile_kind(Vector2i(86,57)) == -1, "Map edge void does not appear as a passage")
	check(map.npc_kind({"id":2}) == 5 and map.npc_kind({"id":15}) == 8, "Combat NPCs are red and service NPCs purple")
	check(map.marker_position(game.player_tile) == map.PLOT.get_center(), "Green player marker stays centered")
	var old: Vector2 = map.marker_position(Vector2i(56,83))
	game.player_tile += Vector2i.RIGHT
	check(map.marker_position(Vector2i(56,83)) != old and map.marker_position(game.player_tile) == map.PLOT.get_center(), "Map scrolls with player movement")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1544,720)]:
		root.size = dimensions;await process_frame
		check(root.get_visible_rect().encloses(map.get_global_rect()), "Minimap fits landscape %s" % str(dimensions))
		check(not map.get_global_rect().intersects(game.joystick.activation_area()), "Minimap does not cover movement activation area")
		check(not map.get_global_rect().intersects(game.attack_button.get_global_rect()), "Minimap does not cover weapon control")
	var header: Vector2 = map.global_position + Vector2(40,20)
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION;mouse.button_index = MOUSE_BUTTON_LEFT;mouse.position = header;mouse.pressed = true
	Input.parse_input_event(mouse);await process_frame
	check(map.expanded, "Synthesized mouse cannot double-toggle touch minimap")
	await tap_at(header)
	check(not map.expanded and map.size == Vector2(100,42), "One native touch collapses minimap to small Map button")
	check(not game.moving and game.route.is_empty() and not game.joystick.active, "Minimap touch cannot move the player")
	await tap_at(header)
	check(map.expanded, "Collapsed Map button reopens minimap")
	var origin: Vector2i = game.player_tile
	await tap_at(map.global_position + map.PLOT.get_center())
	check(map.expanded and game.player_tile == origin and game.route.is_empty(), "Map plot absorbs touches without walking or casting")
	game.inventory.show();map._process(0.0)
	check(not map.visible and not map.contains(header), "Minimap yields to inventory dialogs")
	game.inventory.hide();map._process(0.0)
	check(map.visible, "Minimap returns after dialog closes")
	game.load_map(5);map._process(0.0)
	check(map.map_id == 5 and map.specs.get(Vector2i(56,83),-1) != 9, "Changing maps clears old chest markers")
	game.started = false;map._process(0.0)
	check(not map.visible, "Minimap hides on welcome/disconnect")
	game.queue_free();await process_frame
	print("MINIMAP V43 ","FAIL" if failed else "PASS",": ",checks," checks")
	quit(1 if failed else 0)
