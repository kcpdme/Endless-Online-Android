extends "res://tests/peer_visuals_live.gd"
var seen: Dictionary = {}
var holds: Array[Dictionary] = []
var peer_renderer: Node
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
	peer_renderer = load("res://scripts/online_controller.gd").new()
	peer_renderer.game = game
	actor = load("res://scripts/online_session.gd").new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void:
		actor_replies[int(message.get("id",-1))] = message
		var data: Dictionary = message.get("data",{}) as Dictionary
		for row: Dictionary in data.get("players",data.get("players_upsert",[])):
			seen[int(row.player_id)] = Vector2i(int(row.x),int(row.y))
			if int(row.player_id) == int(c.player.player_id): peer_renderer._track_entities("player",peer_renderer._dict_array([row]),"player_id")
	)
	actor.open(c.host_field.text,8079)
	if not check(await wait_for(func() -> bool: return actor.connected),"Observer transport"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login",{"username":fixtures.observer.username,"password":fixtures.observer.password})
	await rpc("enter",{"character_id":(login.characters as Array)[0].id})
	await rpc("stream",{"enabled":true})
	var pid: int = int(c.player.player_id)
	var cases: Array = [[KEY_W,Vector2i.UP],[KEY_S,Vector2i.DOWN],[KEY_A,Vector2i.LEFT],[KEY_D,Vector2i.RIGHT],[KEY_UP,Vector2i.UP],[KEY_DOWN,Vector2i.DOWN],[KEY_LEFT,Vector2i.LEFT],[KEY_RIGHT,Vector2i.RIGHT],[0,Vector2i.UP],[0,Vector2i.DOWN],[0,Vector2i.LEFT],[0,Vector2i.RIGHT],[KEY_D,Vector2i.RIGHT,12],[KEY_A,Vector2i.LEFT,12]]
	for pair: Array in cases:
		var direction: Vector2i = pair[1]
		var steps: int = int(pair[2]) if pair.size() > 2 else 3
		var origin: Vector2i = game.player_tile
		var start: int = Time.get_ticks_msec()
		if int(pair[0]) == 0: press_pad(direction,true)
		else: press_key(int(pair[0]),true)
		var samples: Dictionary = {"last":game.player_world,"started":false,"stationary_frames":0,"frames":0,"step_times":[],"tile":origin,"last_tick":Time.get_ticks_usec(),"stationary_ms":0.0,"peer_started":false,"peer_idle_frames":0,"max_pending":0}
		var reached: bool = await wait_for(func() -> bool:
			samples.max_pending = maxi(int(samples.max_pending), c.pending_inputs.size())
			var now: int = Time.get_ticks_usec()
			var peer: Dictionary = peer_renderer._remote_sample("player:"+str(pid),Vector2.ZERO,now/1000000.0)
			if peer.state == "frames" and str(peer.direction) == game._direction_name(direction): samples.peer_started = true
			elif samples.peer_started and peer.state != "frames": samples.peer_idle_frames += 1
			if game.player_tile != samples.tile:
				(samples.step_times as Array).append(now / 1000.0)
				samples.tile = game.player_tile
			if samples.started:
				samples.frames += 1
				if game.player_world.distance_to(samples.last) < 0.001:
					samples.stationary_frames += 1
					samples.stationary_ms += (now - int(samples.last_tick)) / 1000.0
			elif game.player_world.distance_to(samples.last) > 0.001: samples.started = true
			samples.last = game.player_world
			samples.last_tick = now
			return game.player_tile == origin + direction * steps
		,steps * c.MOVE_SECONDS + 3)
		holds.append({"key":int(pair[0]),"direction":[direction.x,direction.y],"stationary_frames":samples.stationary_frames,"stationary_ms":samples.stationary_ms,"frames":samples.frames,"step_times_ms":samples.step_times,"peer_idle_frames":samples.peer_idle_frames,"max_pending":samples.max_pending,"peer_started":samples.peer_started,"steps":steps})
		if OS.get_environment("ASTER_VALE_TEST_SMOOTHNESS") == "1":
			if not check(samples.stationary_frames == 0,"Local held walking paused: "+str(holds.back())): return
			if OS.get_environment("ASTER_VALE_TEST_REMOTE_STRICT") != "0":
				if not check(samples.peer_started and samples.peer_idle_frames == 0,"Observer walking paused: "+str(holds.back())): return
		if not check(reached,"Held direction did not reach its straight native endpoint: "+str(pair)+" "+c.last_error+" tile="+str(game.player_tile)+" origin="+str(origin)+" keys="+str(game.movement_keys)+" focus="+str(game.get_viewport().gui_get_focus_owner())+" modal="+str(game._modal_open())+" corrections="+str(c.network_metrics.corrections)): return
		if int(pair[0]) == 0: press_pad(direction,false)
		else: press_key(int(pair[0]),false)
		await process_frame
		var end: Vector2i = game.player_tile
		if not check(end == origin + direction * steps,"Direction drifted onto another axis"): return
		if not check(await wait_for(func() -> bool: return not game.moving and c.pending_inputs.is_empty(),4),"Release did not finish committed tile"): return
		if not check(await wait_for(func() -> bool: return seen.get(pid,Vector2i(-1,-1)) == end,4),"Other player sees a different position"): return
		await create_timer(.45).timeout
		if not check(game.player_tile == end and game.stick == Vector2.ZERO,"Held release left extra movement"): return
		print("DIRECTION PASS: ",pair," ",steps," steps in ",Time.get_ticks_msec()-start," ms")
	# Sustained walking catches a pace that outruns the native queue only after
	# many tiles. Bounce inside the observer's visible area without releasing.
	var long_origin: Vector2i = game.player_tile
	var move_base: int = int(c.network_metrics.moves)
	var long_run: Dictionary = {"max_pending":0,"stationary_frames":0,"peer_idle_frames":0,"started":false,"peer_started":false,"last":game.player_world,"step_times_ms":[],"tile":long_origin}
	var held: int = KEY_D
	press_key(held,true)
	var sustained: bool = await wait_for(func() -> bool:
		var now: int = Time.get_ticks_usec()
		long_run.max_pending = maxi(int(long_run.max_pending),c.pending_inputs.size())
		if game.player_tile != long_run.tile:
			(long_run.step_times_ms as Array).append(now/1000.0)
			long_run.tile = game.player_tile
		if long_run.started and game.player_world.distance_to(long_run.last) < .001: long_run.stationary_frames += 1
		elif game.player_world.distance_to(long_run.last) > .001: long_run.started = true
		long_run.last = game.player_world
		var peer: Dictionary = peer_renderer._remote_sample("player:"+str(pid),Vector2.ZERO,now/1000000.0)
		if peer.state == "frames" and str(peer.direction) == "east": long_run.peer_started = true
		elif long_run.peer_started and peer.state != "frames": long_run.peer_idle_frames += 1
		if int(c.network_metrics.moves)-move_base >= 84: return true
		if game.player_tile == long_origin + Vector2i.RIGHT*6 and game._input_direction() == Vector2i.RIGHT:
			press_key(KEY_A,true)
			press_key(KEY_D,false)
		elif game.player_tile == long_origin and game._input_direction() == Vector2i.LEFT:
			press_key(KEY_D,true)
			press_key(KEY_A,false)
		return false
	,48)
	press_key(KEY_D,false)
	press_key(KEY_A,false)
	if not check(sustained,"Continuous 84-step walk stalled: "+str(long_run)): return
	if not check(await wait_for(func() -> bool: return not game.moving and c.pending_inputs.is_empty(),5),"Long walk did not settle"): return
	if not check(game.player_tile == long_origin and await wait_for(func() -> bool: return seen.get(pid,Vector2i(-1,-1)) == long_origin,4),"Long walk endpoints differ"): return
	if OS.get_environment("ASTER_VALE_TEST_SMOOTHNESS") == "1":
		if not check(long_run.stationary_frames == 0,"Sustained local walking paused: "+str(long_run)): return
		if OS.get_environment("ASTER_VALE_TEST_REMOTE_STRICT") != "0":
			if not check(long_run.peer_started and long_run.peer_idle_frames == 0,"Sustained observer walking paused: "+str(long_run)): return
	print("SUSTAINED WALK PASS: ",JSON.stringify(long_run))
	if not check(int(c.network_metrics.corrections)==0,"Valid straight input produced server corrections"): return
	var shots: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots.path_join("v25-dynamic-stick.png"))
	var report: Dictionary = {"remote_strict_jitter_assertions":OS.get_environment("ASTER_VALE_TEST_REMOTE_STRICT") != "0","sustained_84_steps":long_run,"holds":holds,"result":"passed","keyboard_directions":8,"dynamic_joystick_directions":4,"straight_steps_per_direction_hold":3,"long_continuous_holds":2,"steps_per_long_hold":12,"observer_positions_match_all_holds":true,"no_steps_after_release":true,"server_corrections":int(c.network_metrics.corrections),"operator_accounts_modified":false}
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
	peer_renderer.free()
	quit()
