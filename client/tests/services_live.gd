extends "res://tests/peer_visuals_live.gd"
## Drive the real gameplay dialogs, not a duplicate UI or mocked network.
func send(operation: String, fields: Dictionary = {}) -> void:
	game.online.session.request(operation, fields)

func idle() -> bool:
	return game.online.session.is_idle()

func select_item(list: ItemList, id: int) -> bool:
	for i: int in range(list.item_count):
		var key:Variant=list.get_item_metadata(i)
		if (int(key[0]) if key is Array else int(key)) == id:
			list.select(i)
			list.item_selected.emit(i)
			return true
	return false

func capture(label: String) -> void:
	var directory: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

func _run() -> void:
	root.size = Vector2i(1544, 720)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = str(fixtures.observer.username)
	c.password_field.text = str(fixtures.observer.password)
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "UI observer login: " + c.last_error): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and idle()), "UI observer enter"): return
	if not check(not game.location_label.is_visible_in_tree() and not game.quest_label.is_visible_in_tree() and not game.coin_label.visible and not c.server_label.visible, "Obsolete gameplay information is still visible"): return
	if not check(game.stats_ui.vitals.visible and game.stats_ui.vitals.hp > 0 and not game.joystick.active, "Heart/TP HUD or idle stick incorrect"): return
	await capture("v11-vitals")
	var bank: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 16: bank = npc
	if not check(not bank.is_empty(), "Native banker missing"): return
	c.map_click(Vector2i(int(bank.x), int(bank.y)))
	var ui: RefCounted = game.services_ui
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "bank" and idle()), "Tap banker did not open bank: " + c.last_error): return
	if not check(root.get_visible_rect().encloses(ui.card.get_global_rect()), "Bank dialog must fit inside the screen"): return
	ui.quantity.value = 2000
	ui.primary.pressed.emit()
	if not check(await wait_for(func() -> bool: return int(ui.state.get("gold", 0)) == 2000 and idle()), "Bank deposit did not update dialog/bag"): return
	await capture("v11-bank")
	ui.close()
	c.map_click(Vector2i(2, 1))
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "locker" and idle()), "Tap locker did not open native locker: " + c.last_error): return
	if not check(select_item(ui.left, 21), "Dagger missing from locker bag list"): return
	ui.quantity.value = 2
	ui.primary.pressed.emit()
	if not check(await wait_for(func() -> bool: return ui.right.item_count == 1 and amount(21) == 3 and idle()), "Locker deposit not visible"): return
	if not check(select_item(ui.right, 21), "Deposited dagger missing from locker"): return
	await capture("v11-locker")
	ui.secondary.pressed.emit()
	if not check(await wait_for(func() -> bool: return ui.right.item_count == 0 and amount(21) == 5 and idle()), "Locker withdrawal not visible"): return
	ui.close()
	actor = (load("res://scripts/online_session.gd") as Script).new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void: actor_replies[int(message.get("id", -1))] = message)
	actor.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return actor.connected), "Actor transport"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login", {"username": fixtures.actor.username, "password": fixtures.actor.password})
	var entry: Dictionary = await rpc("enter", {"character_id": (login.characters as Array)[0].id})
	var pid: int = int((entry.player as Dictionary).player_id)
	await rpc("stream", {"enabled": true})
	if not check(await wait_for(func() -> bool: return not peer_record(c, pid).is_empty()), "Player spawn missing"): return
	var own_gear: Dictionary = (c.player.equipment as Dictionary).duplicate()
	c.map_click(Vector2i(2, 3))
	if not check(game.player_actions.panel.visible,"Player tap did not show compact choices"):return
	game.player_actions.choose("Paperdoll")
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "inspect" and idle()), "Player tap did not inspect"): return
	if not check(int(ui.doll.inspection.player_id) == pid and c.player.equipment == own_gear and ui.doll.background != null, "Inspection must show native original paperdoll without replacing your own equipment"): return
	await capture("v11-inspect")
	if not check(not ui.primary.visible and not ui.extra.visible,"Paperdoll must not show trade or whisper buttons"):return
	ui.close();c.map_click(Vector2i(2,3));game.player_actions.choose("Trade")
	await create_timer(.3).timeout
	await rpc("trade_accept", {"player_id": int(c.player.player_id)})
	if not check(await wait_for(func() -> bool: return ui.panel.visible and ui.mode == "trade" and idle()), "Native trade did not open"): return
	if not check(root.get_visible_rect().encloses(ui.card.get_global_rect()), "Trade dialog must fit inside the screen"): return
	if not check(select_item(ui.left, 21), "Dagger missing from trade bag"): return
	ui.quantity.value = 1
	ui.primary.pressed.emit()
	if not check(await wait_for(func() -> bool: return ui.right.item_count == 1 and idle()), "Native own trade offer missing"): return
	await rpc("trade_add", {"item_id": 1, "amount": 100})
	if not check(await wait_for(func() -> bool: return ui.right.item_count == 2 and idle()), "Partner offer missing"): return
	await capture("v11-trade")
	ui.extra.pressed.emit()
	if not check(await wait_for(func() -> bool: return bool(ui.state.get("agreed", false)) and idle()), "Own acceptance not acknowledged"): return
	await rpc("trade_agree", {"agree": true})
	if not check(await wait_for(func() -> bool: return c.trade.is_empty() and not ui.panel.visible and amount(21) == 4 and amount(1) == 48100 and idle()), "Native completed trade missing from inventory"): return
	await rpc("chat_send", {"channel": "local", "message": "Hello from the original EO world"})
	if not check(await wait_for(func() -> bool: return not game.chat_ui.messages.is_empty() and c.chat_bubbles.has(pid)), "Native local chat missing from log/bubble"): return
	game.chat_ui.open()
	if not check(game.chat_ui.history.get_parsed_text().contains("Hello from the original EO world"), "Chat dialog failed to display original message"): return
	await capture("v11-chat")
	game.chat_ui.channel.select(2)
	game.chat_ui.target.text = str(fixtures.actor.character_name)
	game.chat_ui.entry.text = "A private test reply"
	game.chat_ui.send_message()
	if not check(await wait_for(func() -> bool: return game.chat_ui.messages.size() >= 2 and idle()), "Whisper sender display missing"): return
	game.chat_ui.close()
	var report: Dictionary = {"result": "passed", "actual_gameplay_ui": true, "native_banker_tap_deposit": true, "native_locker_tap_deposit_withdraw": true, "original_player_inspection_without_self_equipment_overwrite": true, "native_two_player_trade_dialog_and_inventory": true, "chat_log_and_local_speech_bubble": true, "whisper_input": true, "clean_heart_tp_hud": true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("SERVICES UI LIVE PASS: ", JSON.stringify(report))
	actor.close()
	c.session.close()
	game.started = false
	game.queue_free()
	actor.queue_free()
	await process_frame
	await process_frame
	quit(0)
