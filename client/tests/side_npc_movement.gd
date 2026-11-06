extends SceneTree
## Nearby and perpendicular NPC motion must not stall clear-road held walking.
class Wire extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate(true)})
		return calls.size()
var game: Node
var wire: Wire
var failed: bool = false
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func reset(direction: Vector2i, touch: bool) -> void:
	game._cancel_movement(true); game.online._reset_movement(); game.online.streaming = true
	game.online.players.clear(); game.online.npcs.clear(); wire.calls.clear(); game.attack_clock = 0.0
	game.player_tile = Vector2i(40,40); game.player_world = game.tile_position(game.player_tile); game.facing = game._direction_name(direction)
	game.online.player.x = 40; game.online.player.y = 40
	if touch: game.stick = Vector2(direction)
	else: game.movement_keys.assign([{Vector2i.UP:KEY_W,Vector2i.DOWN:KEY_S,Vector2i.LEFT:KEY_A,Vector2i.RIGHT:KEY_D}[direction]])
func moves() -> Array:
	return wire.calls.filter(func(c: Dictionary) -> bool: return c.op == "move")
func ack(tile: Vector2i, correction: bool = false) -> void:
	var player: Dictionary = game.online.player.duplicate(true); player.x = tile.x; player.y = tile.y
	game.online._apply_snapshot({"player":player,"position_update":true,"position_seq":game.online.next_input_seq,"correction":correction})
func run() -> void:
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.set_process(false); game.online.set_process(false); game.online.session.set_process(false); game.music.stop()
	for card: Control in game.modal_cards: card.get_parent().hide()
	game.online.session.queue_free(); wire = Wire.new(); game.online.add_child(wire); wire.set_process(false); game.online.session = wire
	game.started = true; game.online_mode = true; game.online.active = true
	game.online.player = {"player_id":100,"name":"Fixture","map_id":int(game.world.id),"x":40,"y":40,"direction":3,"sitting":0,"inventory":[],"equipment":{},"spells":[],"stats":{},"hp":10,"max_hp":10,"tp":10,"max_tp":10}
	game.server_blocked.clear()
	var cases: int = 0
	for fps: int in [30,60,120]:
		for touch: bool in [false,true]:
			for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				for side: int in [-1,1]:
					for incoming: bool in [false,true]:
						cases += 1; reset(direction,touch)
						var start: Vector2i = game.player_tile
						var target: Vector2i = start + direction
						var offset: Vector2i = Vector2i(-direction.y,direction.x) * side
						var npc_tile: Vector2i = target + offset
						game.online.npcs.assign([{"index":8,"id":101,"x":npc_tile.x,"y":npc_tile.y,"direction":game.online._direction(game._direction_name(-offset))}])
						if incoming:
							game.online._track_entities("npc",game.online.npcs,"index",Time.get_ticks_msec()/1000.0-1.0)
							var old: Vector2i = npc_tile + offset
							game.online.remote_motion["npc:8"] = {"to":game.tile_position(npc_tile),"tile":npc_tile,"walk_start":Time.get_ticks_msec()/1000.0,"steps":[{"from":game.tile_position(old),"to":game.tile_position(npc_tile),"start":Time.get_ticks_msec()/1000.0,"duration":.42,"direction":game._direction_name(-offset)}]}
						game._process(1.0/fps)
						check(game.moving and game.player_world!=game.tile_position(start) and moves().size()==1 and not game.online.pending_inputs[0].deferred,"NPC one tile to the side does not stop or defer straight held movement")
						if moves().is_empty(): continue
						ack(target)
						for frame: int in range(fps):
							var previous: Vector2 = game.player_world
							game._process(1.0/fps)
							check(game.player_world!=previous,"Walking remains continuous past a nearby perpendicular NPC")
							if not game.online.pending_inputs.is_empty(): ack(game.player_tile)
	# If the NPC actually wins the tile, brake presentation and retain input.
	for touch: bool in [false,true]:
		reset(Vector2i.RIGHT,touch); game._process(.1)
		var position: Vector2 = game.player_world
		game.online.npcs.assign([{"index":8,"id":101,"x":41,"y":40,"direction":0}])
		game._process(.1)
		check(game.player_world==position and game.online.waiting_for_npc_clear,"An actual NPC entering the predicted destination pauses the sprite")
		ack(Vector2i(40,40),true)
		check(not game.moving and game._input_direction()==Vector2i.RIGHT and game.player_tile==Vector2i(40,40),"Native collision correction keeps the held key or joystick")
		game._process(.1)
		check(not game.moving and moves().size()==1,"Held input cannot walk into a genuinely occupied destination")
		game.online.npcs.clear(); game._process(.01)
		check(game.moving and moves().size()==2,"Held movement resumes on the first clear frame after collision")
		game._cancel_movement(); game._advance_walk(game.step_duration)
		check(game._input_direction()==Vector2i.ZERO and not game.moving,"Release finishes the committed step and prevents another retry")
	print("SIDE NPC MOVEMENT: ",JSON.stringify({"result":"failed" if failed else "passed","cases":cases,"checks":checks}))
	game.started = false; game.online.active = false; game.queue_free(); await process_frame; quit(1 if failed else 0)
