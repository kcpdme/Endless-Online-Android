extends SceneTree
## Frame-rate and packet-jitter regressions using the actual movement code.
class SessionCapture extends "res://scripts/online_session.gd":
	var moves: int = 0
	var faces: int = 0
	func request(operation: String, _fields: Dictionary = {}) -> int:
		if operation == "move": moves += 1
		if operation == "face": faces += 1
		return moves + 1
var failed: bool = false
var game: Node
func _initialize() -> void: call_deferred("_run")
func check(value: bool, reason: String) -> void:
	if not value:
		failed = true
		push_error(reason)
func point_input(direction: Vector2i, keyboard: bool) -> void:
	if keyboard:
		var code: int = {Vector2i.UP:KEY_W,Vector2i.DOWN:KEY_S,Vector2i.LEFT:KEY_A,Vector2i.RIGHT:KEY_D}[direction]
		game.movement_keys.assign([code])
	else:
		game.stick = Vector2(direction)
		game.touch_move_id = 41
func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var c: Node = game.online
	c.set_process(false)
	c.session.queue_free()
	var capture: SessionCapture = SessionCapture.new()
	c.add_child(capture)
	capture.set_process(false)
	c.session = capture
	game.welcome.hide()
	game.online_mode = true
	game.started = true
	c.active = true
	c.streaming = true
	game.world = {"id":40,"width":250,"height":250,"warps":[]}
	game.server_blocked.clear()
	var cases: int = 0
	for facing: String in ["north","south","east","west"]:
		for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			for keyboard: bool in [true,false]:
				c.pending_inputs.clear()
				c.pending_face = ""
				c.last_face_at = -125
				game._cancel_controls(true)
				game.player_tile = Vector2i(40,40)
				game.player_world = game.tile_position(game.player_tile)
				game.facing = facing
				point_input(direction,keyboard)
				var interval: float = .20
				var from: Vector2 = game.player_world
				var expected: Vector2 = game.tile_position(game.player_tile+direction)-from
				var moves_before: int = capture.moves
				var faces_before: int = capture.faces
				game._process(1.0/60.0)
				if keyboard and facing != game._direction_name(direction):
					check(not game.moving and game.player_world == from and capture.moves == moves_before and capture.faces == faces_before+1,"A different-direction tap must send only a face, from "+facing+" to "+str(direction))
					game._process(interval / 2)
					check(not game.moving and capture.moves == moves_before,"A short hold must not become a walk before its keyboard/touch turn interval")
					game._cancel_movement()
					game._process(.3)
					check(game.player_world == from and capture.moves == moves_before,"Releasing after a turn must not schedule a delayed walk")
					point_input(direction,keyboard)
					game._process(1.0/60.0)
				var moved: Vector2 = game.player_world-from
				check(moved.dot(expected)>0 and absf(moved.cross(expected))<0.01 and capture.moves == moves_before+1,"A same-facing tap must immediately move along the requested axis")
				check(game.facing == game._direction_name(direction),"Input retained the old facing")
				check(not game.camera.position_smoothing_enabled and game.camera.position==game.player_world,"Camera creates a false opposite drift")
				var endpoint: Vector2i = game.player_tile
				game._cancel_movement()
				game._process(.5)
				check(game.player_tile==endpoint and not game.moving,"Short release issued another step")
				# A continuous hold after a turn uses its input-specific interval.
				if keyboard and facing != game._direction_name(direction):
					c.pending_inputs.clear()
					game._cancel_controls(true)
					game.player_tile = Vector2i(40,40)
					game.player_world = from
					game.facing = facing
					point_input(direction,keyboard)
					moves_before = capture.moves
					game._process(.01)
					game._process(interval - .01)
					check(capture.moves == moves_before and not game.moving,"Turn hold moved too soon")
					game._process(.011)
					check(capture.moves == moves_before+1 and game.moving,"Holding a turned direction must walk after its keyboard/touch interval")
				cases+=1
	# Turns during an existing walk must not add a stationary interval.
	c.pending_inputs.clear()
	game._cancel_controls(true)
	game.player_tile = Vector2i(40,40)
	game.player_world = game.tile_position(game.player_tile)
	game.facing = "east"
	point_input(Vector2i.RIGHT,true)
	game._process(0)
	point_input(Vector2i.UP,true)
	game._process(c.MOVE_SECONDS)
	check(game.moving and game.player_tile == Vector2i(41,39) and game.turn_wait == 0,"A held walking turn must continue at the tile boundary without a pause")
	# Tap-to-walk routes already choose their own path and never need this gate.
	c.pending_inputs.clear()
	game._cancel_controls(true)
	game.player_tile = Vector2i(40,40)
	game.player_world = game.tile_position(game.player_tile)
	game.facing = "south"
	game.route.assign([Vector2i(41,40)])
	game._process(.01)
	check(game.moving and game.player_tile == Vector2i(41,40),"Path walking must retain its existing immediate behavior")
	game._cancel_controls(true)
	# Releasing and pressing again before the next frame must clear turn-only wait.
	c.pending_inputs.clear()
	game._cancel_controls(true)
	game.player_tile = Vector2i(40,40)
	game.player_world = game.tile_position(game.player_tile)
	game.facing = "north"
	point_input(Vector2i.RIGHT,true)
	game._process(.01)
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_D
	release.pressed = false
	game._input(release)
	var press: InputEventKey = release.duplicate()
	press.pressed = true
	game._input(press)
	game._process(.01)
	check(game.moving and game.player_tile == Vector2i(41,40),"A second same-facing tap must walk even when key-up/down occurred between frames")
	c.pending_inputs.clear()
	game._cancel_controls(true)
	game.facing = "north"
	point_input(Vector2i.RIGHT,true)
	game._process(.01)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var moves_before_focus: int = capture.moves
	game._process(.3)
	check(not game.moving and capture.moves == moves_before_focus and game.turn_wait == 0,"Focus loss must cancel a pending held-turn walk")
	c._apply_snapshot({"player":{"player_id":100,"map_id":40,"x":40,"y":40,"hp":950,"max_hp":1000,"tp":10,"max_tp":10,"stats":{"dead":false}},"events":[{"kind":"player_damage","source":"spike","player_id":100,"damage":50,"hp":950,"dead":false}]})
	check(game.stats_ui.vitals.hp==950 and not c.defeated,"Spike hit must visibly drain HP without killing a1000HP character")
	check(str(game.damage_numbers.back().value)=="-50" and not c.npc_attack_until.has(-1),"Spike damage feedback must not invent an attacking NPC")
	print("SHORT MOVEMENT ","FAIL" if failed else "PASS",": ",cases," heading/input combinations: tap turns, same-face tap walks,200ms keyboard/immediate touch, release cancellation, smooth walking turns and unchanged paths")
	game.started=false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
