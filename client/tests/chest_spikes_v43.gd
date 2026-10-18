extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failed = true
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.online_mode = true
	game.started = true
	game.load_map(136)
	var c: Node = game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session = wire
	c.active = true
	c.streaming = true
	var chest: Vector2i = Vector2i(56,83)
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var origin: Vector2i = chest - direction
		game.player_tile = origin
		game.player_world = game.tile_position(origin)
		game.moving = false
		c.player = {"map_id":136,"x":origin.x,"y":origin.y,"sitting":0,"player_id":100,"hp":100,"maxhp":100}
		wire.calls.clear()
		c.request_step(direction)
		check(game.player_tile == origin and not game.moving, "Turtle chest blocks prediction from %s" % str(origin))
		check(wire.calls.all(func(call: Dictionary) -> bool: return str(call.op) != "move"), "No walk packet into Turtle chest from %s" % str(origin))
	var ghost: Vector2i = Vector2i(7,55)
	check(game.decorations.any(func(d: Dictionary) -> bool: return d.tile == ghost and str(d.layer) == "objects"), "Chest on approach at (7,55) has visible artwork")
	var hit: Dictionary = c.map_entity_target(game.tile_position(ghost) + Vector2(0,-12))
	check(hit.get("kind", "") == "chest" and hit.get("tile") == ghost, "Restored chest artwork targets its actual native tile")
	# Reproduce stale collision cache: native Chest spec must still win.
	var stale: Dictionary = game.world.duplicate(true)
	stale.server_blocked = []
	stale.blocked = []
	game._configure_world(stale)
	check(not game._walkable(chest) and not game._walkable(ghost), "Chest tile specs block movement even with incomplete collision cache")
	game.load_map(5)
	game.load_map(136)
	var spike: Dictionary = {"tile":Vector2i(56,84),"layer":"objects"}
	check(not game._decoration_visible(spike), "Timed spikes start retracted")
	c._process_events([{"kind":"timed_spikes"}])
	check(game._decoration_visible(spike), "Native timed spike event raises the four surrounding spikes")
	game.timed_spikes_until = Time.get_ticks_msec() - 1
	check(not game._decoration_visible(spike), "Timed spikes retract after their one-second display")
	c.player.x = 56; c.player.y = 84
	c._process_events([{"kind":"player_damage","source":"spike","player_id":100,"damage":5,"hp":95}])
	check(game._decoration_visible(spike), "Native self-damage on timed spikes raises their artwork")
	game.player_tile = Vector2i(7,56)
	var trap: Dictionary = {"tile":Vector2i(5,55),"layer":"objects"}
	check(not game._decoration_visible(trap), "Unoccupied trap spikes stay retracted")
	game.player_tile = Vector2i(5,55)
	check(game._decoration_visible(trap), "Standing or walking onto trap spikes raises them")
	game.player_tile = Vector2i(7,56)
	c.players.assign([{"player_id":200,"x":5,"y":55}])
	check(game._decoration_visible(trap), "Nearby player's occupied trap tile is raised")
	c.players.clear()
	check(not game._decoration_visible(trap), "Trap spikes retract when all players leave")
	game.tile_specs[Vector2i(5,55)] = 35
	check(game._decoration_visible(trap), "Static spikes remain visible")
	game.map_effect_event({"kind":"map_transition"})
	check(game.timed_spikes_until == 0, "Map transition clears old spike pulses")
	game.player_tile = Vector2i(56,84)
	game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	game.camera.reset_smoothing()
	if OS.get_environment("ASTER_VALE_SCREENSHOTS") != "":
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("ASTER_VALE_SCREENSHOTS")+"/chest-spikes.png")
	game.started = false
	game.queue_free()
	await process_frame
	print("CHEST SPIKES ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
