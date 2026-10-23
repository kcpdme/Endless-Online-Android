extends SceneTree
var game: Node
var peer: Node
var replies: Dictionary = {}
var events: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> bool:
	if not ok: push_error(reason); quit(1)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int = Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<end:
		if test.call(): return true
		await process_frame
	return false
func rpc(op: String, fields: Dictionary = {}) -> Dictionary:
	var id: int = peer.request(op,fields)
	if not await wait_for(func() -> bool: return replies.has(id)): check(false,"Peer timeout: "+op); return {}
	var reply: Dictionary = replies[id]; check(bool(reply.ok),"Peer rejected: "+op); return reply.get("data",{}) as Dictionary
func press(parent: Node, text: String) -> void:
	for button: Node in parent.find_children("*","Button",true,false):
		if button.text==text: button.pressed.emit(); return
	check(false,"Missing UI button: "+text)
func run() -> void:
	var fs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PARTY_FIXTURE")))
	var host: String = OS.get_environment("ASTER_VALE_TEST_HOST")
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void:
		for event: Dictionary in (message.get("data",{}) as Dictionary).get("events",[]): events.append(event)
	)
	c.show_login();c.host_field.text=host;c.username_field.text=fs.leader.username;c.password_field.text=fs.leader.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible),"Actor login failed"):return
	if not check(c.selection_previews.size()>0 and int(c.selection_previews[0].appearance_record().equipment_graphics[8])==49,"Login must show actual equipped Harp"):return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()),"Actor entry failed"):return
	peer=load("res://scripts/online_session.gd").new();root.add_child(peer)
	peer.message_received.connect(func(message: Dictionary) -> void: replies[int(message.get("id",-1))]=message)
	peer.open(host,8079)
	if not check(await wait_for(func() -> bool: return peer.connected),"Peer transport failed"):return
	await rpc("connect");var login: Dictionary=await rpc("login",{"username":fs.member.username,"password":fs.member.password});var entry: Dictionary=await rpc("enter",{"character_id":int(login.characters[0].id)});await rpc("stream",{"enabled":true})
	var pid: int=int(entry.player.player_id)
	if not check(await wait_for(func() -> bool: return c.players.any(func(row: Dictionary) -> bool: return int(row.player_id)==pid)),"Peer not visible"):return
	game.party_ui.invite(pid)
	if not check(await wait_for(func() -> bool:
		for message: Dictionary in replies.values():
			if (message.get("data",{}) as Dictionary).get("party_invitation") is Dictionary:return true
		return false
	),"Actual party UI invitation not delivered"):return
	await rpc("party_accept")
	if not check(await wait_for(func() -> bool: return game.party_ui.party.size()==2 and c.session.is_idle()),"Party roster missing after native create"):return
	game.party_ui.panel.hide()
	var skills: RefCounted=game.skills_ui
	var own: int=int(c.player.player_id)
	for ident: int in [6,8]:
		for recipient: int in [own,pid]:
			await create_timer(.6).timeout
			skills.slots.assign([ident,3]);skills.press(0)
			if not check(skills.armed==ident and not skills.target_panel.visible,"Heal must arm world targeting"):return
			var at: Vector2=game.player_world
			for row: Dictionary in c.players:
				if int(row.player_id)==recipient:at=game.tile_position(Vector2i(int(row.x),int(row.y)))
			var point: Vector2=root.get_final_transform()*game.get_global_transform_with_canvas()*(at+Vector2(0,-45))
			var prior: int=events.size()
			var touch: InputEventScreenTouch=InputEventScreenTouch.new();touch.index=78;touch.pressed=true;touch.position=point;Input.parse_input_event(touch);await process_frame
			touch=touch.duplicate();touch.pressed=false;Input.parse_input_event(touch);await process_frame
			if not check(await wait_for(func() -> bool:
				for i: int in range(prior,events.size()):
					var e: Dictionary=events[i]
					if e.get("kind")=="spell_heal" and int(e.get("spell_id",0))==ident and int(e.get("target_id",0))==recipient:return true
				return false
			),"World touch heal was not native acknowledged for spell %d / player %d" % [ident,recipient]):return
	await create_timer(.6).timeout;skills.press(1)
	if not check(await wait_for(func() -> bool:return events.any(func(e: Dictionary) -> bool:return e.get("kind")=="spell_group" and int(e.get("spell_id",0))==3)),"UI Group Heal was not native acknowledged"):return
	await create_timer(.6).timeout;skills.slots.assign([17,3]);skills.press(0);press(skills.bard_panel,"C1")
	if not check(await wait_for(func() -> bool:return events.any(func(e: Dictionary) -> bool:return e.get("kind")=="bard_note")),"UI Bard note missing"):return
	skills.bard_panel.hide();c.log_out();peer.close();peer.queue_free()
	print("PARTY UI LIVE PASS: native equipped login, invite/roster, world-tap Admin/Large Heal on self and peer, Group Heal and Bard keyboard")
	var report: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not report.is_empty():var f: FileAccess=FileAccess.open(report,FileAccess.WRITE);f.store_string(JSON.stringify({"result":"passed","native_equipped_character_card":true,"native_party_ui_invitation_and_roster":true,"native_world_tap_admin_and_large_heal_self_and_peer":true,"native_group_heal_shortcut":true,"native_bard_keyboard":true},"  ")+"\n")
	game.queue_free();await process_frame;await process_frame;quit(0)
