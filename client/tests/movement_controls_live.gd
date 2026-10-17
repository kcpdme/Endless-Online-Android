extends "res://tests/peer_visuals_live.gd"
var seen: Dictionary = {}
func press_key(code: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func press_pad(direction: Vector2i, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 59
	event.position = game._joystick_zone().get_center()
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed:
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 59
		drag.position = event.position + Vector2(direction) * 84
		Input.parse_input_event(drag)
func _run() -> void:
	root.size = Vector2i(1544,720)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = str(fixtures.actor.username)
	c.password_field.text = str(fixtures.actor.password)
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible),"Subject login: "+c.last_error): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()),"Subject enter"): return
	actor = load("res://scripts/online_session.gd").new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void:
		actor_replies[int(message.get("id",-1))] = message
		var data: Dictionary = message.get("data",{}) as Dictionary
		for row: Dictionary in data.get("players",data.get("players_upsert",[])):
			seen[int(row.player_id)] = Vector2i(int(row.x),int(row.y))
	)
	actor.open(c.host_field.text,8079)
	if not check(await wait_for(func() -> bool: return actor.connected),"Observer transport"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login",{"username":fixtures.observer.username,"password":fixtures.observer.password})
	await rpc("enter",{"character_id":(login.characters as Array)[0].id})
	await rpc("stream",{"enabled":true})
	var pid: int = int(c.player.player_id)
	var cases: Array = [[KEY_W,Vector2i.UP],[KEY_S,Vector2i.DOWN],[KEY_A,Vector2i.LEFT],[KEY_D,Vector2i.RIGHT],[KEY_UP,Vector2i.UP],[KEY_DOWN,Vector2i.DOWN],[KEY_LEFT,Vector2i.LEFT],[KEY_RIGHT,Vector2i.RIGHT],[0,Vector2i.UP],[0,Vector2i.DOWN],[0,Vector2i.LEFT],[0,Vector2i.RIGHT]]
	for pair: Array in cases:
		var direction: Vector2i = pair[1]
		var origin: Vector2i = game.player_tile
		var start: int = Time.get_ticks_msec()
		if int(pair[0]) == 0: press_pad(direction,true)
		else: press_key(int(pair[0]),true)
		if not check(await wait_for(func() -> bool: return game.player_tile == origin + direction * 3,4),"Held direction did not move three straight native tiles: "+str(pair)+" "+c.last_error+" tile="+str(game.player_tile)+" origin="+str(origin)+" keys="+str(game.movement_keys)+" focus="+str(game.get_viewport().gui_get_focus_owner())+" modal="+str(game._modal_open())+" corrections="+str(c.network_metrics.corrections)): return
		if int(pair[0]) == 0: press_pad(direction,false)
		else: press_key(int(pair[0]),false)
		await process_frame
		var end: Vector2i = game.player_tile
		if not check(end == origin + direction * 3,"Direction drifted onto another axis"): return
		if not check(await wait_for(func() -> bool: return not game.moving and c.pending_inputs.is_empty(),4),"Release did not finish committed tile"): return
		if not check(await wait_for(func() -> bool: return seen.get(pid,Vector2i(-1,-1)) == end,4),"Other player sees a different position"): return
		await create_timer(.45).timeout
		if not check(game.player_tile == end and game.stick == Vector2.ZERO,"Held release left extra movement"): return
		print("DIRECTION PASS: ",pair," three steps in ",Time.get_ticks_msec()-start," ms")
	if not check(int(c.network_metrics.corrections)==0,"Valid straight input produced server corrections"): return
	var shots: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots.path_join("v25-dynamic-stick.png"))
	var report: Dictionary = {"result":"passed","keyboard_directions":8,"dynamic_joystick_directions":4,"straight_steps_per_hold":3,"observer_positions_match_all_holds":true,"no_steps_after_release":true,"server_corrections":int(c.network_metrics.corrections),"operator_accounts_modified":false}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  ")+"\n")
	print("MOVEMENT CONTROLS LIVE PASS: ",JSON.stringify(report))
	actor.close()
	c.session.close()
	game.started = false
	game.queue_free()
	actor.queue_free()
	quit()
