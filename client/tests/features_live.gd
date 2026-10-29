extends SceneTree
var game: Node
var c: Node
var ui: RefCounted
var replies: Dictionary = {}
var checks: int = 0
var failed: bool = false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,why: String) -> bool:
	checks+=1
	if not ok:failed=true;push_error(why)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+16000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func call_op(operation: String,fields: Dictionary={}) -> Dictionary:
	var ident: int=c.session.request(operation,fields)
	if not await wait_for(func() -> bool:return replies.has(ident)):check(false,"Timed out: "+operation);return {}
	return replies[ident] as Dictionary
func press(title: String) -> void:
	if title=="Publish post":ui.board_ui.publish_button.pressed.emit();return
	for node: Node in ui.content.get_children():
		if node is Button and node.text==title:node.pressed.emit();return
	check(false,"Missing button "+title)
func screenshot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func finish() -> void:
	if game!=null:game.queue_free()
	await process_frame;await process_frame;quit(1 if failed else 0)
func run() -> void:
	root.size=Vector2i(1544,720)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_INN_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	c=game.online;ui=game.feature_ui
	c.session.message_received.connect(func(message: Dictionary) -> void:
		if message.has("id"):replies[int(message.id)]=message
	)
	c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text=fixture.account.username;c.password_field.text=fixture.account.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Fixture login"):finish();return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Fixture enter"):finish();return
	ui.open("social")
	if not check(await wait_for(func() -> bool:return not ui.busy and ui.panel.visible),"Social menu opens"):finish();return
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(ui.panel.get_child(0).get_global_rect()),"Feature dialog fits phone")
	ui.layout(250);check(ui.card.get_global_rect().end.y<=470,"Feature form remains above software keyboard");ui.layout(0)
	await screenshot("social")
	press("Disable whispers");await wait_for(func() -> bool:return not ui.busy)
	check(not bool(ui.state.get("whispers",true)),"Whisper privacy changes through native reply")
	press("Enable whispers");await wait_for(func() -> bool:return not ui.busy)
	check(bool(ui.state.get("whispers",false)),"Whispers can be restored")
	press("Emotes");await wait_for(func() -> bool:return not ui.busy)
	press("Hearts");await wait_for(func() -> bool:return not ui.busy)
	check(not ui.panel.visible,"Emote picker consumes selection")
	ui.open("find");await wait_for(func() -> bool:return not ui.busy)
	ui.fields.name.text=fixture.account.character_name;press("Find");await wait_for(func() -> bool:return not ui.busy)
	check(ui.status.text.contains("nearby"),"Find reports nearby native player")
	ui.close();ui.open("book");await wait_for(func() -> bool:return not ui.busy)
	check(str(ui.state.get("name",""))==str(fixture.account.character_name),"Book shows native character")
	ui.close();ui.open("report");await wait_for(func() -> bool:return not ui.busy)
	ui.fields.body.text="Disposable UI help request";press("Ask an admin for help");await wait_for(func() -> bool:return not ui.busy)
	check(ui.status.text.contains("Sent"),"Help request native ordering confirmation")
	ui.close()
	# Server-provided environment metadata and actual ignored-before packet feedback.
	var reply: Dictionary=await call_op("admin_teleport",{"destination":"wraith_room"})
	check(bool(reply.get("ok",false)) and bool(c.world_rules.get("pk",false)),"PK map status is authoritative")
	ui.reduced_motion=false;game.map_effect_event({"kind":"quake","strength":8});ui.tick()
	check(game.camera.offset.length()<=12 and game.camera.offset.length()>0,"Bounded camera quake")
	ui.reduced_motion=true;ui.tick();check(game.camera.offset==Vector2.ZERO,"Reduced motion disables quake")
	ui.reduced_motion=false
	# Native board interaction from the map route, with a real published post.
	await create_timer(.8).timeout
	await call_op("chat_send",{"channel":"local","message":"$warp 5 46 2"})
	await wait_for(func() -> bool:return int(game.world.id)==5 and c.session.is_idle())
	c.map_click(Vector2i(46,1),"board")
	if not check(await wait_for(func() -> bool:return ui.panel.visible and not ui.busy),"Board map object opens UI"):finish();return
	check(ui.board_ui.tab==0 and not ui.fields.has("subject"),"Board defaults to Read")
	ui.board_ui.choose(1)
	ui.fields.subject.text="UI probe";ui.fields.body.text="Disposable\nmultiline post";press("Publish post")
	check(ui.confirmation.visible,"Posting requires explicit confirmation")
	ui.confirmation.get_ok_button().pressed.emit();await wait_for(func() -> bool:return not ui.busy)
	check((ui.state.get("posts",[]) as Array).any(func(p: Dictionary) -> bool:return str(p.subject).begins_with("UI probe")),"Published post appears from native list")
	await screenshot("board")
	game._handle_back();check(not ui.panel.visible,"Back closes feature dialog")
	# Reset is a native service and also clears durable/local skill shortcuts.
	await create_timer(.8).timeout
	var master: Dictionary={}
	for world: Dictionary in c.catalog.maps.values():
		for npc: Dictionary in world.get("npc_spawns",[]):
			if int(npc.id)==116:master={"map_id":int(world.id),"x":int(npc.x),"y":int(npc.y)};break
		if not master.is_empty():break
	await call_op("chat_send",{"channel":"local","message":"$warp %d %d %d"%[master.map_id,master.x,int(master.y)+1]})
	await wait_for(func() -> bool:return int(game.world.id)==int(master.map_id) and c.session.is_idle())
	var master_index: int=0
	for npc: Dictionary in c.npcs:
		if int(npc.id)==116:master_index=int(npc.index)
	ui.open("reset",{"npc_index":master_index});await wait_for(func() -> bool:return not ui.busy)
	await screenshot("skill-reset")
	press("Reset attributes and skills");check(ui.confirmation.visible,"Reset confirmation")
	ui.confirmation.get_ok_button().pressed.emit()
	var reset_ok: bool=await wait_for(func() -> bool:return not ui.busy and not ui.panel.visible and (c.player.get("spells",[]) as Array).is_empty())
	if not reset_ok:
		var recent: Array=[]
		for message: Dictionary in replies.values():
			if message.get("op","")=="feature_action":recent.append({"ok":message.get("ok"),"error":message.get("error",""),"feature":(message.get("data",{}) as Dictionary).get("feature",{})})
		print("RESET UI DIAGNOSTIC ",JSON.stringify({"status":ui.status.text,"busy":ui.busy,"panel_visible":ui.panel.visible,"spells":c.player.get("spells",[]),"actions":recent}))
	check(reset_ok,"Native reset removes learned skills in UI")
	check(game.skills_ui.slots==[0,0],"Reset clears shortcut slots")
	# Account management stays in character selection.
	c.log_out();await wait_for(func() -> bool:return not c.active)
	c.username_field.text=fixture.account.username;c.password_field.text=fixture.account.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible and c.session.is_idle()),"Account management login"):finish();return
	var delete_name: String="dev"+str(fixture.account.character_name).substr(3,5)+"del"
	reply=await call_op("create_character",{"name":delete_name})
	if not check(bool(reply.get("ok",false)),"Create disposable deletion target"):finish();return
	for index: int in c.selected_characters.size():
		if str(c.selected_characters[index].name)==delete_name:c.character_list.select(index)
	ui.open("delete");ui.fields.name.text="wrong";press("Delete permanently")
	check(not ui.confirmation.visible and ui.status.text.contains("exact"),"Deletion requires exact selected name")
	ui.fields.name.text=delete_name;press("Delete permanently")
	check(ui.confirmation.visible,"Deletion requires final confirmation")
	ui.confirmation.get_ok_button().pressed.emit()
	if not check(await wait_for(func() -> bool:return not ui.busy and not ui.panel.visible and c.selected_characters.size()==1),"Native deletion updates character list"):finish();return
	ui.open("password");check(ui.panel.get_parent().get_child(-1)==ui.panel,"Account dialog owns draw and touch order above login");await screenshot("change-password");ui.fields.old_password.text=fixture.account.password
	var new_password: String="Flow9_"+str(fixture.account.username)
	ui.fields.new_password.text=new_password;ui.fields.repeat_password.text="different";press("Change password")
	check(not ui.busy and ui.status.text.contains("match"),"Password confirmation validation")
	ui.fields.repeat_password.text=new_password;ui.fields.old_password.text="incorrect-password";press("Change password")
	check(await wait_for(func() -> bool:return not ui.busy and ui.panel.visible and ui.status.text.contains("declined")),"Wrong old password is rejected without closing form")
	ui.fields.old_password.text=fixture.account.password;press("Change password")
	if not check(await wait_for(func() -> bool:return not ui.busy and not ui.panel.visible),"Native password change"):finish();return
	check(c.resume_token.is_empty() and c.reconnection.credentials.is_empty(),"Password change forgets old reconnect proof and credentials")
	c.log_out();await wait_for(func() -> bool:return not c.active)
	c.username_field.text=fixture.account.username;c.password_field.text=new_password;c._authenticate("login")
	check(await wait_for(func() -> bool:return c.character_box.visible and c.session.is_idle()),"New password authenticates with native server")
	c.log_out()
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"native_social_ui":true,"native_board_map_ui":true,"native_character_deletion":true,"native_password_change":true,"pk_metadata_and_reduced_motion":true}
	var file: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n");print("FEATURES LIVE: ",JSON.stringify(report));finish()
