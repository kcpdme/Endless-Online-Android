extends "res://tests/mobile_network_live.gd"
func warp_to(mid: int, tile: Vector2i) -> bool:
	await create_timer(.8).timeout
	game.online.session.request("chat_send", {"channel":"local","message":"$warp %d %d %d" % [mid,tile.x,tile.y]})
	return await wait_for(func() -> bool: return int(game.world.id) == mid and game.player_tile == tile and game.online.session.is_idle() and not game.online.transition_pending)
func tap_npc(ident: int) -> bool:
	var c: Node = game.online
	if not await wait_for(func() -> bool:
		for n: Dictionary in c.npcs:
			if int(n.id) == ident: return true
		return false): return false
	await create_timer(.3).timeout
	var npc: Dictionary = {}
	for n: Dictionary in c.npcs:
		if int(n.id) == ident: npc = n; break
	var at: Vector2 = game.tile_position(Vector2i(int(npc.x),int(npc.y))) + Vector2(0,-35)
	var screen: Vector2 = game.get_global_transform_with_canvas() * at
	touch(screen,true);touch(screen,false)
	return true
func _run() -> void:
	root.size = Vector2i(1544,720)
	game = load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))).actor
	var c: Node = game.online
	c.show_login();c.host_field.text = "127.0.0.1";c.port_field.value = 18087
	c.username_field.text = str(f.username);c.password_field.text = str(f.password);c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible),"Login failed"): return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()),"Enter failed"): return
	game.music.stop()
	# Actual touch, original native Dialog, and original native linked next page.
	if not check(await tap_npc(166),"Wise Man missing"): return
	if not check(await wait_for(func() -> bool: return game.quest_ui.panel.visible),"Wise Man touch did not open conversation: "+c.last_error): return
	(game.quest_ui.body.get_child(2) as Button).pressed.emit()
	if not check(await wait_for(func() -> bool: return game.quest_ui.panel.visible and game.quest_ui.body.get_child_count()==6),"Native Class menu did not reopen"): return
	game.quest_ui.close()
	if not check(await wait_for(func() -> bool: return c.session.is_idle()),"Cancel failed"): return
	var verified: Array[String] = ["Wise Man"]
	for row: Array in [[139,Vector2i(19,8),197,"Maze Master"],[34,Vector2i(51,57),281,"Limbo Sailor"],[94,Vector2i(6,9),168,"Ayla"]]:
		if not check(await warp_to(int(row[0]),row[1]),"Private test warp failed"): return
		if not check(await tap_npc(int(row[2])),"Quest NPC missing"): return
		if not check(await wait_for(func() -> bool: return game.quest_ui.panel.visible),"Quest touch failed: "+str(row[3])+": "+c.last_error): return
		verified.append(str(row[3]));game.quest_ui.close()
		await wait_for(func() -> bool: return c.session.is_idle())
	if not check(await warp_to(70,Vector2i(6,3)),"Inn warp failed"): return
	if not check(await tap_npc(150),"Innkeeper missing"): return
	if not check(await wait_for(func() -> bool: return game.inn_ui.panel.visible),"Inn touch failed: "+c.last_error): return
	game.inn_ui.sleep_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return game.inn_ui.state.has("cost")),"Native inn price missing"): return
	var cost: int = int(game.inn_ui.state.cost)
	var gold: int = c.bag_amount(1)
	if DisplayServer.get_name() != "headless":
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v36-inn-quote.png")
	game.inn_ui.sleep_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return int(game.world.id)==86 and game.player_tile==Vector2i(4,8)),"Inn failed to recover and warp to bed: "+c.last_error): return
	if not check(int(c.player.hp)==int(c.player.max_hp) and int(c.player.tp)==int(c.player.max_tp) and c.bag_amount(1)==gold-cost,"Native paid full recovery did not reach HUD/bag"): return
	var report: Dictionary = {"result":"passed","real_native_gateway_and_rendered_touch":true,"quest_npcs":verified,"linked_class_menu_opens":true,"cancel_preserves_native_quest":true,"inn_touch_quote_and_payment":true,"sleep_bed":[86,4,8],"full_hp_tp_and_gold_acknowledged":true,"operator_characters_modified":false}
	var file: FileAccess = FileAccess.open("res://../docs/services-v36-live-report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("V36 SERVICES LIVE PASS: ",JSON.stringify(report))
	c.session.close();game.started = false;game.queue_free();await process_frame;quit()
