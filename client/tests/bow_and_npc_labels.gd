extends SceneTree
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func weapon_frame(frame: Dictionary) -> Dictionary:
	for part: Dictionary in frame.get("layers", []):
		if str(part.get("path", "")).contains("layer_weapon_back_73"): return part
	return {}
func run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.started = true
	game.online_mode = true
	var online: Node = game.online
	online.set_process(false)
	online.active = true
	online.player = {"name":"fixture", "player_id":100, "character_id":100, "map_id":5, "x":40, "y":40, "gender":1, "race":0, "hairstyle":1, "haircolor":0, "equipment_graphics":[1,0,0,0,1,0,44,10,73], "hp":1000, "max_hp":1000, "tp":100, "max_tp":100}
	game.player_tile = Vector2i(40,40)
	game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	game.moving = false
	online.npcs.assign([{"id":257,"index":47,"x":41,"y":40,"direction":0}])
	online.npc_health[47] = {"percent":94,"until":Time.get_ticks_msec()+20000}
	var graphic: Dictionary = online.character_graphic(online.player)
	check(bool(graphic.get("ranged",false)), "Scav Bow must select ranged rendering")
	var weapon: Dictionary = game.manifest.characters.equipment_layers.layers["weapon_back:73"]
	var directions: Array[String] = ["south","west","north","east"]
	for index: int in range(directions.size()):
		var direction: String = directions[index]
		check(weapon_frame(game._frame(graphic,direction,"attack",.1)).region == weapon.ranged_attack[direction][0].region,"Bow preparation must use standing rather than melee art: "+direction)
		check(weapon_frame(game._frame(graphic,direction,"attack",.32)).region == weapon.ranged_attack[direction][1].region,"Bow release must use original shooting art: "+direction)
		var idle: Dictionary = online.npc_name_layout(online.npc_graphic(online.npcs[0]),direction,false)
		var combat: Dictionary = online.npc_name_layout(online.npc_graphic(online.npcs[0]),direction,true)
		check(is_zero_approx(combat.name.x) and idle.name == combat.name,"Boss name must remain at original horizontal center and idle height: "+direction)
		check((combat.health as Rect2).end.y < combat.name.y-11,"Combat health strip must sit above the whole name: "+direction)
		game.facing = direction
		game.swing_clock = .16
		online.npcs[0].direction = index
		game.queue_redraw()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../work/v32-bow-"+direction+".png")
	var peer: Dictionary = online.player.duplicate(true)
	peer.player_id = 101
	online.peer_attacks[101] = {"until":Time.get_ticks_msec()/1000.0+.16,"direction":2}
	var animation: Dictionary = online.entity_animation("online_player",peer)
	check(animation.state == "attack" and bool(online.character_graphic(peer).get("ranged",false)),"Observers must use the same ranged attack renderer")
	var melee: Dictionary = online.player.duplicate(true)
	melee.equipment_graphics[8] = 4
	check(not bool(online.character_graphic(melee).get("ranged",true)),"Melee equipment must retain existing animation")
	print("BOW/NPC ","FAIL" if failed else "PASS",": original ranged poses in four directions, observer rendering, unchanged melee and name height, centered boss, HP above name")
	game.started = false
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
