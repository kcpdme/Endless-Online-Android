extends SceneTree
## Reproduce an off-centre landing followed by an upward drag through actual touch events.
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate(true)})
		return calls.size()
var game: Node
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func touch(point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point; event.pressed = pressed; event.index = 81
	Input.parse_input_event(event)
	await process_frame
func drag(point: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.position = point; event.index = 81
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	root.size = Vector2i(1544,720)
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop()
	game.welcome.hide();game.online.panel.hide(); game.started = true; game.online_mode = true
	var online: Node = game.online; online.session.queue_free()
	var wire: Capture = Capture.new(); online.add_child(wire); wire.set_process(false); online.session = wire
	online.panel.hide(); online.active = true; online.streaming = true; online.player = {"player_id":100,"stats":{}}
	game.world = {"id":40,"width":250,"height":250,"warps":[]}; game.server_blocked.clear()
	var traces: Array[Dictionary] = []
	var early_steps: int = 0
	var wrong_directions: int = 0
	var delayed_starts: int = 0
	var face_requests: int = 0
	var first_frame_motion: int = 0
	for fixed: bool in [false,true]:
		for isometric: bool in [false,true]:
			for fps: int in [30,60,120]:
				for landing: Vector2 in [Vector2(224,566),Vector2(84,566),Vector2(152,638),Vector2(24,402),Vector2(340,680)]:
					for horizontal_jitter: float in [-3.0,0.0,3.0]:
						game._cancel_controls(true); online.pending_inputs.clear(); wire.calls.clear()
						game.joystick.fixed_base = fixed; game.joystick.isometric = isometric; game.joystick.reset()
						game.player_tile = Vector2i(40,40); game.player_world = game.tile_position(game.player_tile); game.facing = "east"
						var start: Vector2 = game.player_world
						await touch(landing,true)
						game._process(1.0/fps)
						var premature: bool = game.moving
						if premature: early_steps += 1
						await drag(landing + Vector2(horizontal_jitter,-48))
						game._process(1.0/fps)
						var moves: Array = wire.calls.filter(func(row: Dictionary) -> bool: return row.op == "move")
						var faces: Array = wire.calls.filter(func(row: Dictionary) -> bool: return row.op == "face")
						var correct: bool = moves.size() == 1 and int(moves[0].fields.direction) == 2
						if not moves.is_empty() and not correct: wrong_directions += 1
						if moves.is_empty(): delayed_starts += 1
						face_requests += faces.size()
						if not premature and correct and game.player_world.distance_to(start) > .01: first_frame_motion += 1
						traces.append({"fixed":fixed,"isometric":isometric,"fps":fps,"landing":[landing.x,landing.y],"jitter":horizontal_jitter,"premature":premature,"correct":correct,"moves":moves.size()})
						await touch(landing + Vector2(horizontal_jitter,-48),false)
	var report: Dictionary = {"result":"passed" if early_steps == 0 and wrong_directions == 0 and delayed_starts == 0 and first_frame_motion == traces.size() and face_requests == 0 else "failed","traces":traces.size(),"steps_before_drag":early_steps,"wrong_first_directions":wrong_directions,"delayed_first_steps":delayed_starts,"first_frame_motion":first_frame_motion,"extra_face_requests":face_requests,"fps":[30,60,120],"landing_points":5,"modes":4}
	var path: String = OS.get_environment("EO_STARTUP_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report,"  "))
	print("JOYSTICK STARTUP ",report.result.to_upper(),": ",JSON.stringify(report))
	game.started = false; game.queue_free(); await process_frame
	quit(0 if report.result == "passed" else 1)
