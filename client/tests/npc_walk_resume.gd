extends SceneTree
## Held walking must overlap native confirmation with the departing NPC's animation.
class Wire extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate(true)})
		return calls.size()
var game: Node
var wire: Wire
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func moves() -> Array:
	return wire.calls.filter(func(c: Dictionary) -> bool: return c.op == "move")
func run() -> void:
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.online.session.set_process(false); game.music.stop()
	for card: Control in game.modal_cards: card.get_parent().hide()
	game.online.session.queue_free(); wire = Wire.new(); game.online.add_child(wire); wire.set_process(false); game.online.session = wire
	game.started = true; game.online_mode = true; game.online.active = true; game.online.streaming = true
	game.online.player = {"player_id":100,"name":"Fixture","map_id":int(game.world.id),"x":40,"y":40,"direction":3,"sitting":0,"inventory":[],"equipment":{},"spells":[],"stats":{},"hp":10,"max_hp":10,"tp":10,"max_tp":10}
	game.server_blocked.clear()
	for fps: int in [30,60,120]:
		for touch: bool in [false,true]:
			for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				game._cancel_movement(true); game.online._reset_movement(); wire.calls.clear()
				game.online.streaming = true; game.attack_clock = 0.0
				game.player_tile = Vector2i(40,40); game.player_world = game.tile_position(game.player_tile); game.facing = game._direction_name(direction)
				game.online.player.x = 40; game.online.player.y = 40
				var target: Vector2i = game.player_tile + direction
				if touch: game.stick = Vector2(direction)
				else: game.movement_keys.assign([{Vector2i.UP:KEY_W,Vector2i.DOWN:KEY_S,Vector2i.LEFT:KEY_A,Vector2i.RIGHT:KEY_D}[direction]])
				game.online.npcs.assign([{"index":8,"id":101,"x":target.x,"y":target.y,"direction":0}])
				game.online.remote_motion.clear()
				game._process(1.0/fps)
				check(moves().is_empty() and not game.moving,"Occupied tile blocks held walking")
				# Native coordinates leave the road; the displayed sprite still overlaps it.
				var departure: Vector2i = target + Vector2i(-direction.y,direction.x)
				game.online.npcs[0].x = departure.x; game.online.npcs[0].y = departure.y
				var segment: Dictionary = {"from":game.tile_position(target),"to":game.tile_position(departure),"start":Time.get_ticks_msec()/1000.0,"duration":.42,"direction":"south"}
				game.online.remote_motion["npc:8"] = {"to":game.tile_position(departure),"tile":departure,"steps":[segment],"walk_start":segment.start}
				game._process(1.0/fps)
				check(moves().size()==1 and not game.moving,"Held input requests native permission during NPC departure, without predicting through it")
				if moves().is_empty():
					continue # Baseline fails here; no invented ACK.
				var player: Dictionary = game.online.player.duplicate(true); player.x = target.x; player.y = target.y
				game.online._apply_snapshot({"player":player,"position_update":true,"position_seq":game.online.next_input_seq,"correction":false})
				var origin: Vector2 = game.player_world
				for frame: int in range(4): game._process(1.0/fps)
				check(game.player_world==origin and game.local_render_pose().state=="idle" and moves().size()==1,"An early ACK waits for the NPC sprite without duplicate movement or walking in place")
				segment.start = Time.get_ticks_msec()/1000.0 - .43
				game._process(1.0/fps)
				check(game.player_world!=origin and game.step_progress<=1.0/fps/game.step_duration+.00001 and moves().size()==1,"Movement resumes on the first clear frame without another server round trip or accumulated time jump")
				game._cancel_movement()
				for frame: int in range(fps): game._process(1.0/fps)
				check(not game.moving and game.player_tile==target and moves().size()==1,"Release finishes only the accepted step")
	print("NPC WALK RESUME: ",JSON.stringify({"result":"failed" if failed else "passed","checks":checks,"cases":24}))
	game.started = false; game.online.active = false; game.queue_free(); await process_frame; quit(1 if failed else 0)
