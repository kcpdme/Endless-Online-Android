extends SceneTree
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:failed=true;push_error(why)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func login(game: Node, account: Dictionary) -> bool:
	var c: Node=game.online;c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text=account.username;c.password_field.text=account.password;c._authenticate("login")
	if not await wait_for(func() -> bool:return c.character_box.visible):return false
	c.character_list.select(0);c._enter_selected()
	return await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle())
func run() -> void:
	root.size=Vector2i(1280,720)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_INN_FIXTURE")))
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	if not check(await login(game,fixture.account),"Disposable native walker login"):quit(1);return
	var view: SubViewport=SubViewport.new();view.size=Vector2i(1280,720);view.world_2d=World2D.new();root.add_child(view)
	var observer: Node=load("res://main.tscn").instantiate();view.add_child(observer);await process_frame
	if not check(await login(observer,fixture.regular),"Independent native observer login"):quit(1);return
	var c: Node=game.online;var other: Node=observer.online
	var pid: int=int(c.player.player_id)
	check(int(game.world.id)==7 and game.player_tile==Vector2i(12,15),"Start on real Malone Outlet bank")
	check(int(game.tile_specs.get(Vector2i(13,15),-1))==29,"Original map carries Jump tile specification")
	var results: Array[Dictionary]=[]
	for x: int in [13,14,15,16]:
		if not check(await wait_for(func() -> bool:return c.can_issue_walk() and c.pending_inputs.is_empty()),"Native walk is ready"):quit(1);return
		var expected_hop: bool=x<=15
		var previous_seq: int=c.next_input_seq;c.request_step(Vector2i.RIGHT)
		if not check(c.next_input_seq==previous_seq+1,"A real native move was sent"):quit(1);return
		var local_peak: float=0;var peer_peak: float=0;var seen_peer: bool=false;var done: bool=false
		var end: int=Time.get_ticks_msec()+6000
		while Time.get_ticks_msec()<end:
			var pose: Dictionary=game.local_render_pose()
			local_peak=maxf(local_peak,(pose.ground_position as Vector2).y-(pose.position as Vector2).y)
			for peer: Dictionary in other.players:
				if int(peer.get("player_id",-1))!=pid:continue
				var remote: Dictionary=other.entity_render_pose("online_player",peer)
				peer_peak=maxf(peer_peak,(remote.ground_position as Vector2).y-(remote.position as Vector2).y)
				if remote.state=="frames":seen_peer=true
				if seen_peer and remote.state=="idle" and (remote.ground_position as Vector2).distance_to(game.tile_position(Vector2i(x,15)))<.01 and not game.moving and c.pending_inputs.is_empty():done=true
			if done:break
			await process_frame
		check(done,"Native actor and observer both finish the crossing")
		check(Vector2i(int(c.player.x),int(c.player.y))==Vector2i(x,15),"Native acknowledgement confirms landing tile")
		check(local_peak>=15.0 if expected_hop else is_zero_approx(local_peak),"Local Jump/ordinary walking distinction")
		check(peer_peak>=15.0 if expected_hop else is_zero_approx(peer_peak),"Independent observer sees the same hop")
		check(game.local_render_pose().position==game.player_world,"Native landing returns sprite to ground")
		results.append({"tile":[x,15],"hop":expected_hop,"local_peak":local_peak,"observer_peak":peer_peak})
	c.log_out();other.log_out()
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"real_godot_gateway_native_world":true,"map_id":7,"two_native_players":true,"crossings":results,"operator_characters_modified":false}
	var file: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("STEPPING STONES LIVE: ",JSON.stringify(report));game.queue_free();view.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
