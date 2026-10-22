extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
var checks: int = 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1544,720)
	var settings_path: String = "user://movement_controls.cfg"
	var had_preferences: bool = FileAccess.file_exists(settings_path)
	var prior_preferences: String = FileAccess.get_file_as_string(settings_path) if had_preferences else ""
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop()
	game.welcome.hide(); game.started = true; game.online_mode = true
	var online: Node = game.online; online.session.queue_free()
	var wire: Capture = Capture.new(); online.add_child(wire); wire.set_process(false); online.session = wire
	online.panel.hide(); online.active = true; online.streaming = true; online.player = {"player_id":100,"stats":{}}
	game.world = {"id":40,"width":250,"height":250,"warps":[]}; game.server_blocked.clear()
	var pad: Control = game.joystick
	pad.fixed_base = false; pad.isometric = false; pad.reset()
	var origin: Vector2 = game._joystick_zone().get_center()
	game.player_tile = Vector2i(40,40); game.player_world = game.tile_position(game.player_tile); game.facing = "south"
	# Actual captured joystick input uses the short mobile hold; keyboard stays classic.
	game._joystick_begin(origin,41); game.stick = pad.update_pointer(origin + Vector2(35,0))
	game._process(0)
	check(not game.moving and is_equal_approx(game.turn_wait,.08), "Captured touch must use an80ms turn hold")
	game._process(.079); check(not game.moving, "Touch turn must preserve deliberate very-short turn-only gestures")
	game._process(.002); check(game.moving, "Touch must start walking after80ms without an ACK wait")
	var committed: Vector2i = game.player_tile
	game._cancel_controls(); game._process(.5)
	check(not game.moving and game.player_tile == committed and game.player_world.distance_to(game.tile_position(committed)) < .01, "Release must finish exactly its committed tile")
	game._cancel_controls(true); online.pending_inputs.clear(); game.facing = "south"; game.movement_keys.assign([KEY_D]); game._process(0)
	check(is_equal_approx(game.turn_wait,.20), "Keyboard must retain the original200ms turn interval")
	game._cancel_controls(true); online.pending_inputs.clear()
	# Distinct engagement/release radii prevent thumb jitter from repeatedly stopping.
	pad.begin(origin)
	check(pad.update_pointer(origin + Vector2(13,0)) == Vector2.ZERO, "A sub14px drag must stay neutral")
	check(pad.update_pointer(origin + Vector2(15,0)) == Vector2.RIGHT, "A15px deliberate drag must activate")
	check(pad.update_pointer(origin + Vector2(12,0)) == Vector2.RIGHT, "Small return motion must keep the selected direction")
	check(pad.update_pointer(origin + Vector2(9,0)) == Vector2.ZERO, "Returning inside10px must stop intent")
	pad.begin(origin); pad.update_pointer(origin + Vector2(250,0))
	var far: Vector2 = origin + Vector2(250,0)
	var distance: int = 0
	for offset: int in range(1,100):
		if pad.update_pointer(far - Vector2(offset,0)) == Vector2.LEFT: distance = offset; break
	check(distance <= 79 and distance > 0, "Reversal after a long drag should need at most79px, not the old103px")
	# Each isometric ray must select the matching native tile axis.
	pad.isometric = true
	for tile: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		pad.reset(); pad.begin(origin)
		var projected: Vector2 = Vector2((tile.x-tile.y)*2,tile.x+tile.y).normalized()
		check(pad.update_pointer(origin + projected * 45) == Vector2(tile), "Isometric drag must follow the visible tile projection")
	pad.reset(); pad.fixed_base = true
	var fixed_center: Vector2 = pad.global_position + Vector2.ONE * pad.radius
	pad.begin(fixed_center + Vector2(40,20))
	check(pad.direction == Vector2i.RIGHT, "Fixed isometric base must respond to pressing its lower-right ray")
	var fixed_position: Vector2 = pad.global_position
	pad.update_pointer(Vector2(1500,50))
	check(pad.global_position == fixed_position, "Fixed base must stay anchored during a long drag")
	pad.reset(); pad.fixed_base = false; pad.isometric = false
	pad.begin(origin); pad.update_pointer(Vector2(-200,1000))
	check(root.get_visible_rect().encloses(pad.get_global_rect()), "Floating base must stay visible at screen edges")
	game._cancel_controls(true)
	var preference_file: String = "user://test_movement.cfg"
	pad.set_preferences(true,true,preference_file); pad.isometric = false; pad.fixed_base = false; pad.load_preferences(preference_file)
	check(pad.isometric and pad.fixed_base, "Control preferences must persist independently of game progress")
	pad.isometric = false; pad.fixed_base = false; pad.reset()
	game.menu.show(); game.movement_ui.open()
	check(game.movement_ui.panel.visible and not game.menu.visible and game._modal_open(), "Movement settings must suspend gameplay")
	game.movement_ui.mapping.select(1); game.movement_ui.base.select(1); game.movement_ui.save()
	check(pad.isometric and pad.fixed_base and game.touch_move_id == -1, "Settings must update mapping/base and clear stale input")
	game._handle_back(); check(not game.movement_ui.panel.visible and game.menu.visible, "Back from controls must return to the menu")
	game.menu.hide()
	# Bound the renderer traversal without omitting a visible floor tile.
	var rectangle_cases: int = 0
	for center: Vector2 in [Vector2.ZERO,game.tile_position(Vector2i(40,40)),game.tile_position(Vector2i(86,86)),Vector2(-5000,-5000),Vector2(5000,5000)]:
		for zoom: float in [1.0,1.65,2.5]:
			var half: Vector2 = Vector2(1544,720) / zoom / 2 + Vector2(160,240)
			var rect: Rect2 = Rect2(center-half,half*2)
			var bounds: Rect2i = game._visible_tile_bounds(rect,87,87)
			var missing: bool = false
			for y: int in range(87):
				for x: int in range(87):
					var tile: Vector2i = Vector2i(x,y)
					if rect.has_point(game.tile_position(tile)) and not bounds.has_point(tile): missing = true
			check(not missing,"Viewport traversal must contain every previously visible tile")
			rectangle_cases += 1
	var half: Vector2 = Vector2(1544,720) / 1.65 / 2 + Vector2(160,240)
	var bounds: Rect2i = game._visible_tile_bounds(Rect2(game.tile_position(Vector2i(40,40))-half,half*2),87,87)
	var metrics: Dictionary = {"result":"passed" if not failed else "failed","touch_turn_ms":80,"keyboard_turn_ms":200,"step_ms":420,"long_drag_reversal_px":distance,"aeven_full_grid_candidates":7569,"bounded_candidates":bounds.size.x*bounds.size.y,"viewport_cases":rectangle_cases,"checks":checks}
	var output: String = OS.get_environment("EO_MOVEMENT_REPORT")
	if OS.get_environment("EO_MOVEMENT_SCREENSHOT") != "":
		game.movement_ui.open(); await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("EO_MOVEMENT_SCREENSHOT"))
	game.movement_ui.open(); online._on_closed("Test disconnect")
	check(not game.movement_ui.panel.visible and not game.menu.visible, "Disconnect must clear movement settings and recover the welcome screen")
	if had_preferences:
		var restore: FileAccess = FileAccess.open(settings_path,FileAccess.WRITE)
		if restore != null: restore.store_string(prior_preferences)
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	metrics["checks"] = checks; metrics["result"] = "failed" if failed else "passed"
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(metrics,"  "))
	game.started = false; game.queue_free(); await process_frame
	if not failed: print("MOBILE MOVEMENT PASS: ",JSON.stringify(metrics))
	quit(1 if failed else 0)
