extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed = true; push_error(message)
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.online.panel.hide()
	game.online_mode = true
	game.started = true
	game.load_map(3)
	var c: Node = game.online
	c.set_process(false)
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session = wire
	c.active = true
	c.streaming = true
	var me: Dictionary = {"name":"fixture","player_id":100,"character_id":100,"map_id":3,"x":5,"y":9,"direction":0,"sitting":0,"gender":1,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"inventory":[{"id":1,"amount":100},{"id":21,"amount":5}],"stats":{"weight":5,"max_weight":70},"equipment_graphics":[1,0,0,0,1,0,0,0,4]}
	c._apply_snapshot({"player":me.duplicate(true),"players":[],"npcs":[],"items":[]},true)
	var tile: Vector2i = Vector2i(4,9)
	var hit: Dictionary = c.map_entity_target(game.tile_position(tile)+Vector2(0,-8))
	check(hit.get("kind","") == "chair" and hit.tile == tile,"Chair artwork must target seating instead of blocked ground")
	for spec: int in range(1,8):
		var sides: Array[Vector2i] = c.chair_sides(spec)
		check(not sides.is_empty(),"Every original chair spec must have an approach side")
	check(c.chair_sides(3)==[Vector2i.RIGHT] and c.chair_sides(5)==[Vector2i.DOWN,Vector2i.RIGHT],"Chair approach must respect original orientation")
	c.map_click(tile,"chair")
	c._process_interaction()
	check(wire.calls.back().op == "sit" and wire.calls.back().fields == {"x":4,"y":9},"Chair sends original tile request")
	check(game.player_tile == Vector2i(5,9) and not c.seated(),"Do not predict native seating")
	me.x = 4
	me.sitting = 1
	me.direction = 3
	c._on_message({"op":"sit","ok":true,"data":{"player":me.duplicate(true),"position_update":true,"events":[{"kind":"seating","player_id":100}]}})
	check(c.seated() and game.player_tile == tile and not game.moving and game.facing == "east","Native chair ACK snaps position and direction without walking")
	var hero: Dictionary = c.character_graphic(c.player)
	for state: String in ["sit_chair","sit_floor"]:
		for direction: String in ["south","east","north","west"]:
			check(not game._frame(hero,direction,state).is_empty(),"All sitting directions must render")
	var weapon: Dictionary = (game.manifest.characters.equipment_layers.layers as Dictionary)["weapon_back:4"]
	check(game._frame(weapon,"east","sit_chair").is_empty(),"Original sitting hides weapons")
	c.request_step(Vector2i.UP)
	check(wire.calls.back().op == "sit" and wire.calls.back().fields.is_empty(),"Movement while seated asks to stand before sending a walk")
	me.x = 5
	me.sitting = 0
	c._on_message({"op":"sit","ok":true,"data":{"player":me.duplicate(true),"position_update":true,"events":[{"kind":"seating","player_id":100}]}})
	check(not c.seated() and game.player_tile == Vector2i(5,9) and not game.moving,"Standing restores the native exit tile")
	var peer: Dictionary = me.duplicate(true)
	peer.player_id = 200
	peer.x = 4
	peer.sitting = 1
	c._apply_snapshot({"players":[peer],"events":[{"kind":"seating","player_id":200}]})
	check(c.entity_animation("online_player",peer).state == "sit_chair" and c.remote_motion["player:200"].steps.is_empty(),"Peer chair pose must be stationary")
	peer.x = 5
	peer.sitting = 0
	c._apply_snapshot({"players":[peer],"events":[{"kind":"seating","player_id":200}]})
	check(c.remote_motion["player:200"].steps.is_empty(),"Peer standing must not invent a walk off the chair")
	game.inventory.show()
	c.refresh_game_ui()
	check("Weight 5 / 70" in game.inventory_summary.text,"Bag displays native carrying weight")
	me.stats.weight = 70
	c.player = me.duplicate(true)
	c.refresh_game_ui()
	check("Overweight" in game.inventory_summary.text and game.inventory_summary.modulate != Color.WHITE,"Full bags warn visually")
	check(game.inventory_summary.get_minimum_size().x < 980,"Weight summary fits the original bag card")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v34-bag-weight.png")
		game.inventory.hide()
		me.x = 4
		me.sitting = 1
		c._apply_snapshot({"player":me.duplicate(true),"position_update":true})
		c.players.clear()
		game.camera.position = game.player_world
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v34-chair.png")
	print("SEATING WEIGHT ","FAIL" if failed else "PASS",": artwork hit, all chair sides, native ACK, stand before walk, original poses, peer sync and bag capacity")
	game.started = false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
