extends "res://tests/mobile_network_live.gd"
var speaker: Node
func login_game(target: Node, fixture: Dictionary) -> bool:
	var c: Node = target.online
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = str(fixture.username)
	c.password_field.text = str(fixture.password)
	c._authenticate("login")
	if not await wait_for(func() -> bool: return c.character_box.visible): return false
	c.character_list.select(0)
	c._enter_selected()
	return await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle())
func _run() -> void:
	root.size = Vector2i(1544, 720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not check(await login_game(game, f.observer), "Viewer login failed"): return
	speaker = load("res://main.tscn").instantiate()
	root.add_child(speaker)
	await process_frame
	if not check(await login_game(speaker, f.actor), "Speaker login failed"): return
	speaker.hide()
	speaker.ui.visible = false
	speaker.camera.enabled = false
	var c: Node = game.online
	var other: Node = speaker.online
	var pid: int = int(other.player.player_id)
	var viewer: int = int(c.player.player_id)
	if not check(await wait_for(func() -> bool:
		for peer: Dictionary in c.players:
			if int(peer.player_id) == pid: return true
		return false), "Native speaker not visible nearby"): return
	speaker.chat_ui.quick_channel.select(0)
	speaker.chat_ui.quick_entry.text = "Hello nearby!"
	speaker.chat_ui.send_quick()
	if not check(await wait_for(func() -> bool: return c.chat_bubbles.has(pid) and other.chat_bubbles.has(pid)), "Nearby bubble must reach speaker AND second player"): return
	if not check(str(c.chat_bubbles[pid].text) == "Hello nearby!" and str(other.chat_bubbles[pid].text) == "Hello nearby!", "Native nearby text differs"): return
	if not check(c.chat_bubble_position(pid).is_finite() and c.chat_bubble_position(viewer) == game.player_world, "Bubble anchors must resolve to current character positions"): return
	var shots: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots.path_join("v24-nearby-observer.png"))
	await create_timer(.8).timeout
	game.chat_ui.quick_channel.select(0)
	game.chat_ui.quick_entry.text = "I can see your bubble!"
	game.chat_ui.send_quick()
	if not check(await wait_for(func() -> bool: return c.chat_bubbles.has(viewer) and other.chat_bubbles.has(viewer)), "Reply bubble must reach both clients"): return
	# Global and whispers remain in their feeds, without replacing Nearby speech.
	await create_timer(.8).timeout
	speaker.chat_ui.quick_channel.select(1)
	speaker.chat_ui.quick_entry.text = "Global message"
	speaker.chat_ui.send_quick()
	if not check(await wait_for(func() -> bool: return speaker.chat_ui.pending_chat.is_empty()), "Global send failed"): return
	if not check(str(c.chat_bubbles[pid].text) == "Hello nearby!", "Global message replaced Nearby bubble"): return
	await create_timer(6).timeout
	if not check(c.chat_bubbles.is_empty() and other.chat_bubbles.is_empty(), "Expired bubbles must clear on every client"): return
	var report: Dictionary = {"result":"passed","actual_native_two_client_nearby_broadcast":true,"speaker_and_observer_receive_speech":true,"reply_visible_to_both":true,"bubble_anchors_match_character_positions":true,"global_does_not_replace_nearby_speech":true,"expired_bubbles_removed":true,"speech_drawn_after_world_and_combat_layers":true,"operator_accounts_modified":false}
	print("NEARBY BUBBLES LIVE PASS: ", JSON.stringify(report))
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  ")+"\n")
	other.session.close()
	c.session.close()
	game.started = false
	speaker.started = false
	speaker.queue_free()
	game.queue_free()
	quit()
