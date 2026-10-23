extends SceneTree
var game: Node
var peer: Node
var replies: Dictionary={}
var peer_rows: Array[Dictionary]=[]
var checks: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:push_error(why);quit(1)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func touch(point: Vector2) -> void:
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=90;e.position=root.get_final_transform()*point;e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func tap(control: Control) -> void:
	await process_frame;await process_frame;await touch(control.get_global_rect().get_center())
func join(f: Dictionary) -> bool:
	var c: Node=game.online;c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=f.username;c.password_field.text=f.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Fixture login failed"):return false
	c.character_list.select(0);c._enter_selected()
	return check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Fixture entry failed")
func rpc(op: String, fields: Dictionary={}) -> Dictionary:
	var id: int=peer.request(op,fields)
	if not check(await wait_for(func() -> bool:return replies.has(id)),"Peer timeout"):return {}
	var r: Dictionary=replies[id];check(bool(r.ok),"Peer rejected "+op);return r.get("data",{})
func run() -> void:
	root.size=Vector2i(1600,720)
	var fs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_BARBER_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	if not await join(fs.actor):return
	var c: Node=game.online;var pid: int=int(c.player.player_id);var before: int=c.bag_amount(1)
	peer=load("res://scripts/online_session.gd").new();root.add_child(peer)
	peer.message_received.connect(func(m: Dictionary) -> void:
		replies[int(m.get("id",-1))]=m
		var data: Dictionary=m.get("data",{}) as Dictionary
		for row: Dictionary in data.get("players",[]):peer_rows.append(row)
		for row: Dictionary in data.get("players_upsert",[]):peer_rows.append(row)
	)
	peer.open(OS.get_environment("ASTER_VALE_TEST_HOST"),8079)
	if not check(await wait_for(func() -> bool:return peer.connected),"Peer transport failed"):return
	await rpc("connect");var login: Dictionary=await rpc("login",{"username":fs.observer.username,"password":fs.observer.password});await rpc("enter",{"character_id":int(login.characters[0].id)});await rpc("stream",{"enabled":true})
	var babs: Dictionary={}
	for row: Dictionary in c.npcs:
		if int(row.id)==32:babs=row
	if not check(not babs.is_empty(),"Actual Aeven haircutter missing"):return
	await touch(game.get_global_transform_with_canvas()*(game.tile_position(Vector2i(int(babs.x),int(babs.y)))+Vector2(0,-25)))
	var ui: RefCounted=game.world_services
	if not check(await wait_for(func() -> bool:return ui.barber_panel.visible and c.session.is_idle()),"Babs touch did not open native haircutter"):return
	if not check(int(ui.state.price)==1000,"Native level-five haircut quote must be 1000 Gold"):return
	ui.style.select(20);ui.color.select(9);ui.update_preview()
	if not check(int(c.player.hairstyle)==1 and c.bag_amount(1)==before,"Preview spent Gold or changed real character"):return
	await tap(ui.buy)
	if not check(ui.confirm.visible,"Haircut confirmation missing"):return
	ui.confirm.hide();ui.confirm.confirmed.emit()
	if not check(await wait_for(func() -> bool:return int(c.player.hairstyle)==20 and int(c.player.haircolor)==9 and c.bag_amount(1)==before-1000),"Native haircut receipt did not update Gold and hair"):return
	if not check(await wait_for(func() -> bool:return peer_rows.any(func(row: Dictionary) -> bool:return int(row.get("player_id",0))==pid and int(row.get("hairstyle",0))==20 and int(row.get("haircolor",0))==9)),"Nearby native observer did not see haircut"):return
	ui.close_barber();await wait_for(func() -> bool:return c.session.is_idle());c.log_out();peer.close();peer.queue_free();await create_timer(.8).timeout
	c.show_login();c.password_field.text=fs.actor.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Relogin failed"):return
	if not check(int(c.selected_characters[0].hairstyle)==20 and int(c.selected_characters[0].haircolor)==9,"Haircut did not persist in native character selection"):return
	c.character_list.select(0);c._enter_selected();await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle())
	if not check(c.bag_amount(1)==before-1000,"Native saved Gold incorrect after relogin"):return
	c.log_out();await create_timer(.8).timeout
	if not await join(fs.sign):return
	var sign: Dictionary={}
	for row: Dictionary in game.world.get("signs",[]):
		if int(row.x)==64 and int(row.y)==21:sign=row
	var point: Vector2=game.tile_position(Vector2i(64,21))+Vector2(0,-20)
	if not check(c.map_entity_target(point).get("kind")=="sign","Visible Babs road sign has no touch target"):return
	var serial: int=c.session.serial;await touch(game.get_global_transform_with_canvas()*point)
	if not check(ui.sign_panel.visible and ui.sign_title.text=="Babs Hair Care" and ui.sign_text.text.contains("your hair"),"Original road sign did not open readable text"):return
	if not check(not game.joystick.active and c.session.serial==serial,"Reading road sign starts movement or sends a service request"):return
	game._handle_back();c.log_out();game.queue_free();await create_timer(.2).timeout
	var report: Dictionary={"result":"passed","checks":checks,"native_babs_touch_and_price":true,"native_gold_and_hair_ack_only":true,"native_nearby_avatar_update":true,"native_relogin_hair_and_gold_persist":true,"actual_aeven_sign_touch":true,"sign_has_no_movement_or_network_action":true,"dev_characters_only":true}
	var out: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ")+"\n");print("BARBER LIVE: ",JSON.stringify(report));quit(0)
