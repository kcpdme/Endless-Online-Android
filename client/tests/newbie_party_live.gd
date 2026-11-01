extends "res://tests/peer_visuals_live.gd"
## Native level-zero party rewards through the actual WS gateway and Godot HUD.
func idle()->bool:return game.online.session.is_idle()
func _run()->void:
	root.size=Vector2i(1544,720)
	var fixtures:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c:Node=game.online
	c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fixtures.observer.username;c.password_field.text=fixtures.observer.password;c._authenticate("login")
	if not check(await wait_for(func()->bool:return c.character_box.visible),"Newborn login failed"):return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func()->bool:return c.active and c.streaming and idle()),"Newborn entry failed"):return
	if not check(int(c.player.level)==0 and int(c.player.stats.class_id)==0,"Actor must be an original level-zero newborn"):return
	actor=load("res://scripts/online_session.gd").new();root.add_child(actor)
	actor.message_received.connect(func(message:Dictionary)->void:actor_replies[int(message.get("id",-1))]=message)
	actor.open(c.host_field.text,8079)
	if not check(await wait_for(func()->bool:return actor.connected),"Peer transport failed"):return
	await rpc("connect");var login:Dictionary=await rpc("login",{"username":fixtures.actor.username,"password":fixtures.actor.password})
	var entry:Dictionary=await rpc("enter",{"character_id":int(login.characters[0].id)});var pid:int=int(entry.player.player_id);await rpc("stream",{"enabled":true})
	if not check(await wait_for(func()->bool:return not peer_record(c,pid).is_empty()),"Nearby party peer missing"):return
	game.nameplates.sync()
	if not check(game.nameplates.entries.any(func(e:Dictionary)->bool:return e.key=="player:%d"%pid),"Nearby peer's name must show without tapping"):return
	c.map_click(Vector2i(8,44),"player");game.player_actions.choose("Party")
	if not check(await wait_for(func()->bool:
		for message:Dictionary in actor_replies.values():
			if (message.get("data",{}) as Dictionary).get("party_invitation") is Dictionary:return true
		return false
	),"Party action failed to deliver a native invitation"):return
	await rpc("party_accept")
	if not check(await wait_for(func()->bool:return game.party_ui.party.size()==2 and idle()),"Accepted native roster missing"):return
	if not check(game.party_ui.notice.text.contains("same map"),"Party panel must explain sharing eligibility"):return
	game.party_ui.panel.hide();c.session.request("equip",{"item_id":21})
	if not check(await wait_for(func()->bool:return int(c.player.equipment.get("weapon",0))==21 and idle()),"Earned starter Dagger failed to equip"):return
	c.request_face("north");await create_timer(.3).timeout
	for attempt:int in range(35):
		c.request_attack();await create_timer(.6).timeout
		if int(c.player.stats.get("experience",0))>0:break
	if not check(int(c.player.stats.get("experience",0))==8,"Level-zero attacker did not receive its native 8 EXP share"):return
	await process_frame
	if not check(game.stats_ui.vitals.experience==8 and game.stats_ui.vitals.experience_fraction>0,"Party EXP failed to reach the visible EXP bar"):return
	if not check(game.party_ui.history.get_parsed_text().contains("Shared monster EXP: +8"),"Party window must retain an EXP receipt"):return
	var peer_state:Dictionary=await rpc("refresh")
	if not check(int(peer_state.player.stats.experience)==8,"Non-attacking member did not receive its native 8 EXP share"):return
	var report:Dictionary={"result":"passed","actual_player_menu_party_invitation":true,"both_level_zero_newborns":true,"map_id":194,"goat_exp_multiplier":2,"attacker_exp":8,"non_attacker_exp":8,"actual_godot_exp_bar":true,"nearby_name_without_tap":true,"transport":"Godot -> WebSocket -> gateway -> native EO"}
	FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("NEWBIE PARTY UI PASS: ",JSON.stringify(report));actor.close();c.session.close();actor.queue_free();game.queue_free();await process_frame;quit(0)
