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
	var cases: int = 0
	for facing: String in ["north","south","east","west"]:
		for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			for keyboard: bool in [true,false]:
				c.pending_inputs.clear()
				game._cancel_controls(true)
				game.player_tile = Vector2i(40,40)
				game.player_world = game.tile_position(game.player_tile)
				game.facing = facing
				if keyboard:
					var code: int = {Vector2i.UP:KEY_W,Vector2i.DOWN:KEY_S,Vector2i.LEFT:KEY_A,Vector2i.RIGHT:KEY_D}[direction]
					game.movement_keys.assign([code])
				else: game.stick = Vector2(direction)
				var from: Vector2 = game.player_world
				var expected: Vector2 = game.tile_position(game.player_tile+direction)-from
				game._process(1.0/60.0)
				var moved: Vector2 = game.player_world-from
				check(moved.dot(expected)>0 and absf(moved.cross(expected))<0.01,"First frame moves in wrong direction from "+facing+" to "+str(direction))
				check(game.facing == game._direction_name(direction),"Short input retained the old facing")
				check(not game.camera.position_smoothing_enabled and game.camera.position==game.player_world,"Camera creates a false opposite drift")
				var endpoint: Vector2i = game.player_tile
				game._cancel_movement()
				game._process(.5)
				check(game.player_tile==endpoint and not game.moving,"Short release issued another step")
				cases+=1
	c._apply_snapshot({"player":{"player_id":100,"map_id":40,"x":40,"y":40,"hp":950,"max_hp":1000,"tp":10,"max_tp":10,"stats":{"dead":false}},"events":[{"kind":"player_damage","source":"spike","player_id":100,"damage":50,"hp":950,"dead":false}]})
	check(game.stats_ui.vitals.hp==950 and not c.defeated,"Spike hit must visibly drain HP without killing a1000HP character")
	check(str(game.damage_numbers.back().value)=="-50" and not c.npc_attack_until.has(-1),"Spike damage feedback must not invent an attacking NPC")
	print("SHORT MOVEMENT ","FAIL" if failed else "PASS",": ",cases," heading/input combinations")
	game.started=false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
