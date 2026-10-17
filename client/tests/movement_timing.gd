extends SceneTree
## Frame-rate and packet-jitter regressions using the actual movement code.
class SessionCapture extends "res://scripts/online_session.gd":
	var moves: int = 0
	func request(operation: String, _fields: Dictionary = {}) -> int:
		if operation == "move": moves += 1
		return moves + 1
var failed: bool = false
var game: Node
func _initialize() -> void: call_deferred("_run")
func check(value: bool, reason: String) -> void:
	if not value:
		failed = true
		push_error(reason)
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
	var frame_results: Array[Dictionary] = []
	for fps: int in [15,24,30,59,60,90,120,144]:
		c.pending_inputs.clear()
		game._cancel_movement(true)
		game.player_tile = Vector2i(40,40)
		game.player_world = game.tile_position(game.player_tile)
		game.facing = "east" # Measure continuous walking, after any initial turn.
		game.movement_keys.assign([KEY_D])
		capture.moves = 0
		game._process(0.0)
		var initial: Vector2 = game.player_world
		var previous: Vector2 = initial
		var stopped: int = 0
		var max_error: float = 0.0
		for frame: int in range(fps * 4):
			# ACKs are independently covered by movement.gd and two native sessions.
			c.pending_inputs.clear()
			game._process(1.0 / fps)
			if game.player_world.distance_to(previous) < 0.001: stopped += 1
			var expected: Vector2 = initial + (game.tile_position(Vector2i(41,40))-initial) * ((frame + 1.0) / fps / c.MOVE_SECONDS)
			max_error = maxf(max_error, game.player_world.distance_to(expected))
			previous = game.player_world
		check(stopped == 0 and max_error < 0.02,"Held movement pauses or changes pace at %d FPS: stops=%d error=%f" % [fps,stopped,max_error])
		check(game.animation_clock > 3.9,"Walking animation phase restarted at a tile boundary")
		game._cancel_movement()
		var released_tile: Vector2i = game.player_tile
		for frame: int in range(fps): game._process(1.0 / fps)
		check(not game.moving and game.player_tile == released_tile and game.player_world.distance_to(game.tile_position(released_tile)) < 0.01,"Release must finish only the committed step")
		frame_results.append({"fps":fps,"stationary_frames":stopped,"max_position_error_px":max_error,"tiles_per_second":1.0/c.MOVE_SECONDS})
	# Irregular delivery +/-80 ms must not restart interpolation or introduce
	# stationary frames inside a continuous, server-approved walking sequence.
	c.remote_motion.clear()
	var peer: Dictionary = {"player_id":200.0,"x":40,"y":40,"direction":3}
	c._track_entities("player",c._dict_array([peer]),"player_id",9.0)
	var arrivals: Array[float] = [0.0,0.48,0.83,1.33,1.69,2.18,2.52,3.01]
	var next: int = 0
	var remote_error: float = 0.0
	var remote_idle: int = 0
	var origin: Vector2 = game.tile_position(Vector2i(40,40))
	var unit: Vector2 = game.tile_position(Vector2i(41,40))-origin
	for frame: int in range(430):
		var elapsed: float = frame / 120.0
		while next < arrivals.size() and elapsed + 0.000001 >= arrivals[next]:
			peer.x += 1
			c._track_entities("player",c._dict_array([peer]),"player_id",10.0+elapsed)
			next += 1
		var sample: Dictionary = c._remote_sample("player:200",Vector2.ZERO,10.0+elapsed)
		var expected: Vector2 = origin + unit * clampf((elapsed-c.REMOTE_BUFFER_SECONDS)/c.MOVE_SECONDS,0,8)
		remote_error = maxf(remote_error,(sample.position as Vector2).distance_to(expected))
		if elapsed > 0.11 and elapsed < c.REMOTE_BUFFER_SECONDS + arrivals.size()*c.MOVE_SECONDS - .01 and sample.state != "frames": remote_idle += 1
	check(remote_error < 0.02 and remote_idle == 0,"Packet jitter interrupted observer walking: idle=%d error=%f" % [remote_idle,remote_error])
	check(c.remote_motion["player:200"].steps.size() == 1,"Old remote segments must be pruned")
	var ended: Dictionary = c._remote_sample("player:200",Vector2.ZERO,14.0)
	check(ended.state == "idle" and ended.position == game.tile_position(Vector2i(48,40)),"Remote player must stop at its final confirmed tile")
	# The queued direction belongs to the step being displayed, not a future packet.
	c.remote_motion.clear()
	peer.x = 40
	peer.y = 40
	c._track_entities("player",c._dict_array([peer]),"player_id",20.0)
	peer.x = 41
	c._track_entities("player",c._dict_array([peer]),"player_id",20.0)
	peer.y = 41
	peer.direction = 0
	c._track_entities("player",c._dict_array([peer]),"player_id",20.3)
	check(c._remote_sample("player:200",Vector2.ZERO,20.35).direction == "east","Queued turn changed facing before the active step finished")
	check(c._remote_sample("player:200",Vector2.ZERO,20.55).direction == "south","Queued turn did not face the second step")
	peer.x = 60
	c._track_entities("player",c._dict_array([peer]),"player_id",20.6)
	check(c._remote_sample("player:200",Vector2.ZERO,20.6).position == game.tile_position(Vector2i(60,41)),"Warp must clear the old interpolation route")
	c._track_entities("player",c._dict_array([]),"player_id",21.0)
	check(c.remote_motion.is_empty(),"Departed players must release their tracks")
	print("MOVEMENT TIMING ","FAIL" if failed else "PASS",": ",JSON.stringify({"local":frame_results,"remote_jitter_max_position_error_px":remote_error,"remote_jitter_idle_frames":remote_idle,"remote_buffer_ms":100,"native_step_ms":420}))
	game.started = false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
