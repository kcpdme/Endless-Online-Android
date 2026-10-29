extends SceneTree
var game: Node
var c: Node
var ui: RefCounted
var checks: int = 0
var failed: bool = false
var replies: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks += 1
	if not ok: failed = true; push_error(why)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int = Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<end:
		if test.call(): return true
		await process_frame
	return false
func login(account: Dictionary) -> bool:
	c.username_field.text = str(account.username); c.password_field.text = str(account.password); c._authenticate("login")
	if not await wait_for(func() -> bool: return c.character_box.visible): return false
	c.character_list.select(0); c._enter_selected()
	return await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle())
func tap(control: Control) -> void:
	await create_timer(.2).timeout
	for pressed: bool in [true,false]:
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.index = 85; event.position = root.get_final_transform()*control.get_global_rect().get_center(); event.pressed = pressed
		Input.parse_input_event(event); await process_frame
	# Modal scrolling replays a confirmed tap on the next input frames.
	await process_frame; await process_frame
func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func finish() -> void:
	if game != null: game.queue_free()
	await process_frame; await process_frame; quit(1 if failed else 0)
func run() -> void:
	root.size = Vector2i(1544,720)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_INN_FIXTURE")))
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	c = game.online; ui = game.admin_ui
	c.session.message_received.connect(func(message: Dictionary) -> void:
		if str(message.get("op","")).begins_with("admin_"): replies.append(message)
	)
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	check(not ui.button.visible,"Login screen must hide Admin")
	if not check(await login(fixture.account),"Admin fixture login"): finish(); return
	await process_frame
	check(ui.button.visible,"Native admin sees icon")
	check(ui.button.get_global_rect().end.x < game.party_ui.button.get_global_rect().position.x,"Admin is beside Party")
	c.game.skills_ui.armed = 1
	await tap(ui.button)
	if not check(await wait_for(func() -> bool: return not ui.busy and ui.teleport_list.get_child_count()==14),"Native touch opens fourteen server destinations"): finish(); return
	check(ui.panel.visible and game.skills_ui.armed==0,"Admin tap consumes armed world targeting")
	check(replies.size()==1,"One native touch must issue one menu request")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1544,720)]:
		root.size = dimensions; await process_frame
		var card: Control = ui.panel.get_child(0)
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(card.get_global_rect()),"Admin dialog must fit landscape")
	await screenshot("admin-teleport")
	var locations: Array = [[119,24,29],[136,49,18],[277,11,31],[109,7,13],[155,8,11],[271,25,54],[229,82,112],[21,12,6],[161,32,36],[255,12,19],[229,20,20],[71,34,14],[270,8,14],[5,40,40]]
	for index: int in range(locations.size()):
		if not ui.panel.visible:
			await create_timer(.8).timeout; ui.open()
			if not await wait_for(func() -> bool: return not ui.busy): check(false,"Admin reopen failed"); finish(); return
		await process_frame; await process_frame
		(ui.teleport_list.get_parent() as ScrollContainer).ensure_control_visible(ui.teleport_list.get_child(index))
		await process_frame; await process_frame
		var previous_replies: int = replies.size()
		await tap(ui.teleport_list.get_child(index))
		if not check(await wait_for(func() -> bool: return replies.size()>previous_replies and not ui.busy and c.session.is_idle()),"Teleport acknowledged"): finish(); return
		var d: Array = locations[index]
		check(int(game.world.id)==int(d[0]) and game.player_tile==Vector2i(d[1],d[2]),"Native destination must match preset "+str(index))
		check(not ui.panel.visible and bool(replies.back().get("ok",false)),"Teleport closes after native map confirmation")
	await create_timer(.8).timeout; ui.open(); await wait_for(func() -> bool: return not ui.busy)
	ui.tabs.current_tab=1; ui.item_id.text="oops"; ui.submit("item",ui.item_id)
	check(not ui.busy and ui.notice.text.contains("numeric"),"Invalid ID rejected locally")
	var gold: int = c.bag_amount(1)
	ui.item_id.text="1"; await tap(ui.item_button)
	if not check(await wait_for(func() -> bool: return not ui.busy and c.session.is_idle()),"Native item acknowledgement"): finish(); return
	check(c.bag_amount(1)==gold+1 and bool(replies.back().get("ok",false)),"Native item grant adds exactly one")
	await screenshot("admin-item")
	await create_timer(.8).timeout
	ui.item_id.text="99999"; await tap(ui.item_button); await wait_for(func() -> bool: return not ui.busy)
	check(not bool(replies.back().get("ok",true)) and c.bag_amount(1)==gold+1,"Unknown item cannot change bag")
	await create_timer(.8).timeout
	var ids: Array = []
	for npc: Dictionary in c.npcs: ids.append(int(npc.index))
	ui.tabs.current_tab=2; ui.npc_id.text="1"; await tap(ui.spawn_button)
	if not check(await wait_for(func() -> bool: return not ui.busy and c.session.is_idle()),"Native spawn acknowledgement"): finish(); return
	var spawned: bool = false
	for npc: Dictionary in c.npcs:
		if int(npc.id)==1 and int(npc.index) not in ids: spawned=true
	check(spawned and bool(replies.back().get("ok",false)),"Native NPC spawn appears in current world")
	await screenshot("admin-spawn")
	game._handle_back(); check(not ui.panel.visible,"Back closes admin")
	c.log_out(); await wait_for(func() -> bool: return not c.active)
	check(not ui.button.visible and not ui.panel.visible,"Logout hides and resets admin")
	if not check(await login(fixture.regular),"Regular fixture login"): finish(); return
	await process_frame
	check(not ui.button.visible,"Regular players never see icon")
	ui.open(); check(not ui.panel.visible,"Regular players cannot open menu directly")
	for operation: String in ["admin_open","admin_teleport","admin_item","admin_spawn"]:
		var before: int = replies.size()
		c.session.request(operation,{"destination":"apozen","item_id":1,"npc_id":1,"admin":4})
		if not check(await wait_for(func() -> bool: return replies.size()>before),"Forged operation receives rejection"): finish(); return
		check(not bool(replies.back().get("ok",true)) and str(replies.back().get("error","")).contains("Admin access"),"Server blocks forged role for "+operation)
	c.log_out()
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"native_teleport_count":locations.size(),"native_one_item_grant":true,"native_npc_spawn":true,"ordinary_player_forgery_rejected":true,"touch_and_armed_heal_consumed":true,"landscape_dialog_fits":true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n"); print("ADMIN LIVE: ",JSON.stringify(report)); finish()
