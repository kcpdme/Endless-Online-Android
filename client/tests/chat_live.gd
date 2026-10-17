extends "res://tests/skills_live.gd"
var hidden_client: Node
var hidden_replies: Dictionary = {}
func tap(control: Control, position: Vector2 = Vector2(-1, -1)) -> void:
	var at: Vector2 = control.get_global_rect().get_center() if position.x < 0 else position
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 75
	event.position = at
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, f.observer), "Chat observer login: " + c.last_error): return
	actor = load("res://scripts/online_session.gd").new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void: actor_replies[int(message.get("id", -1))] = message)
	actor.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return actor.connected), "Actor connection"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login", {"username": f.actor.username, "password": f.actor.password})
	var entry_data: Dictionary = await rpc("enter", {"character_id": (login.characters as Array)[0].id})
	await rpc("stream", {"enabled": true})
	if not check(int(entry_data.player.map_id) != int(c.player.map_id) and peer_record(c, int(entry_data.player.player_id)).is_empty(), "Fixtures must be on different maps"): return
	hidden_client = load("res://scripts/online_session.gd").new()
	root.add_child(hidden_client)
	hidden_client.message_received.connect(func(message: Dictionary) -> void: hidden_replies[int(message.get("id", -1))] = message)
	hidden_client.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return hidden_client.connected), "Hidden fixture connection"): return
	var ident: int = hidden_client.request("connect")
	if not check(await wait_for(func() -> bool: return hidden_replies.has(ident)), "Hidden handshake"): return
	ident = hidden_client.request("login", {"username": f.hidden.username, "password": f.hidden.password})
	if not check(await wait_for(func() -> bool: return hidden_replies.has(ident)), "Hidden login"): return
	var hidden_login: Dictionary = hidden_replies[ident].data
	ident = hidden_client.request("enter", {"character_id": (hidden_login.characters as Array)[0].id})
	if not check(await wait_for(func() -> bool: return hidden_replies.has(ident)), "Hidden entry"): return
	var ui: RefCounted = game.chat_ui
	await rpc("chat_send", {"channel": "global", "message": "Across maps [b]is plain text[/b]"})
	if not check(await wait_for(func() -> bool: return ui.feed.get_parsed_text().contains("Across maps [b]is plain text[/b]")), "Native global must reach HUD across maps as literal text"): return
	if not check(not ui.panel.visible and ui.quick_root.visible, "Global feed must be visible outside chat window"): return
	await create_timer(2.2).timeout
	if not check(ui.feed.get_parsed_text().contains("Across maps"), "Global messages must remain in game feed"): return
	await capture("v22-global-feed")
	ui.open()
	await tap(ui.tabs[3])
	if not check(await wait_for(func() -> bool: return not ui.roster_pending and ui.roster.size() >= 2), "Native online roster missing: " + c.last_error + " tab=" + str(ui.channel.selected) + " status=" + ui.roster_status.text + " pending=" + str(ui.roster_pending) + " rows=" + str(ui.roster.size())): return
	var found: bool = false
	var hidden_found: bool = false
	for player: Dictionary in ui.roster:
		if str(player.name) == str(f.actor.character_name): found = str(player.title) == "Traveler"
		if str(player.name) == str(f.hidden.character_name): hidden_found = true
	if not check(found and not hidden_found, "Online list must include other maps and respect native hidden-player filtering"): return
	if not check(root.get_visible_rect().encloses((ui.panel.get_child(0) as Control).get_global_rect()), "Chat modal outside viewport"): return
	await capture("v22-online-tab")
	var row: int = -1
	for index: int in range(ui.online_list.item_count):
		if str(ui.online_list.get_item_metadata(index)) == str(f.actor.character_name): row = index
	if not check(row >= 0, "Online player row missing"): return
	var item_rect: Rect2 = ui.online_list.get_item_rect(row)
	await tap(ui.online_list, ui.online_list.global_position + item_rect.position + Vector2(80, 18))
	if not check(ui.channel.selected == 2 and ui.target.text == str(f.actor.character_name), "Touching an online player must address a whisper"): return
	ui.entry.text = "Whisper from Online"
	await tap(ui.panel.get_child(0).get_node("ChatSend"))
	if not check(await wait_for(func() -> bool:
		for reply: Dictionary in actor_replies.values():
			for event: Dictionary in (reply.get("data", {}) as Dictionary).get("events", []):
				if str(event.get("message", "")) == "Whisper from Online" and str(event.get("channel", "")) == "private": return true
		return false
	), "Native whisper did not reach selected cross-map player"): return
	await create_timer(.8).timeout
	await rpc("chat_send", {"channel": "private", "target": f.observer.character_name, "message": "Private reply across maps"})
	if not check(await wait_for(func() -> bool: return ui.history.get_parsed_text().contains("Private reply across maps")), "Private conversation reply missing"): return
	await capture("v22-private-thread")
	game.set_process(false)
	ui._layout(280)
	if not check((ui.panel.get_child(0) as Control).get_global_rect().end.y <= 440 and ui.entry.get_global_rect().end.y <= 440, "Chat input must fit above the Android keyboard"): return
	await capture("v22-keyboard-safe-thread")
	game.set_process(true)
	ui.close()
	await process_frame
	var tile: Vector2i = game.player_tile
	await tap(ui.quick_entry)
	if not check(ui.quick_entry.has_focus() and game.stick == Vector2.ZERO and game.touch_move_id == -1, "Quick composer must own touch before joystick"): return
	ui.quick_channel.select(1)
	ui.quick_entry.text = "Quick global from HUD"
	var send_button: Control = ui.quick_bar.get_child(ui.quick_bar.get_child_count() - 1)
	await tap(send_button)
	if not check(await wait_for(func() -> bool: return ui.pending_chat.is_empty() and ui.feed.get_parsed_text().contains("Quick global from HUD")), "Quick global native echo missing"): return
	if not check(not ui.quick_entry.has_focus() and game.player_tile == tile and game.route.is_empty(), "Send must release keyboard without moving the player"): return
	await create_timer(.8).timeout
	ui.quick_entry.text = "/r Reply shortcut"
	ui.send_quick()
	if not check(await wait_for(func() -> bool: return ui.pending_chat.is_empty()), "Reply shortcut did not finish"): return
	await create_timer(.8).timeout
	ui.quick_entry.text = "你好"
	ui.send_quick()
	if not check(await wait_for(func() -> bool: return ui.pending_chat.is_empty() and ui.quick_entry.text == "你好"), "Rejected send must restore draft"): return
	ui.quick_entry.clear()
	game._joystick_begin(Vector2(160, 580), 74)
	game.owned_touches[74] = true
	var release: InputEventScreenTouch = InputEventScreenTouch.new()
	release.index = 74
	release.position = ui.quick_entry.get_global_rect().get_center()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	if not check(game.touch_move_id == -1 and game.stick == Vector2.ZERO and not game.owned_touches.has(74), "Joystick release over chat must not leave movement or touch ownership stuck"): return
	root.size = Vector2i(1544, 720)
	await process_frame
	await process_frame
	if not check(root.get_visible_rect().encloses(ui.quick_root.get_global_rect()), "Quick chat must fit wide screen"): return
	await capture("v22-wide-chat-hud")
	var report: Dictionary = {"result":"passed","native_global_across_maps_visible_without_modal":true,"global_feed_remains_visible":true,"chat_text_is_not_markup":true,"native_server_wide_online_roster":true,"hidden_online_character_not_exposed":true,"native_online_title_metadata":true,"touch_online_name_addresses_whisper":true,"native_cross_map_private_conversation":true,"touch_quick_composer_does_not_move_or_attack":true,"quick_global_native_echo_and_keyboard_release":true,"reply_shortcut":true,"server_rejection_restores_draft":true,"layout_1280_and_1544":true,"joystick_release_over_chat_cleans_up":true,"keyboard_layout_keeps_message_input_visible":true,"operator_accounts_modified":false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("CHAT UI LIVE PASS: ", JSON.stringify(report))
	actor.close();hidden_client.close();c.session.close()
	game.started = false
	game.queue_free()
	await process_frame
	await process_frame
	quit()
