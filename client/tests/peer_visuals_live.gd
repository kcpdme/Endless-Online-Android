extends "res://tests/mobile_network_live.gd"
var actor: Node
var actor_replies: Dictionary = {}

func rpc(operation: String, fields: Dictionary = {}) -> Dictionary:
	var id: int = actor.request(operation, fields)
	if not check(await wait_for(func() -> bool: return actor_replies.has(id)), "Actor RPC missing: " + operation): return {}
	var reply: Dictionary = actor_replies[id] as Dictionary
	if not check(bool(reply.get("ok", false)), "Actor RPC refused: " + str(reply.get("error", ""))): return {}
	return reply.get("data", {}) as Dictionary

func peer_record(c: Node, pid: int) -> Dictionary:
	for peer: Dictionary in c.players:
		if int(peer.get("player_id", -1)) == pid: return peer
	return {}

func _run() -> void:
	root.size = Vector2i(1544, 720)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	var observer: Dictionary = fixtures.observer as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = str(observer.username)
	c.password_field.text = str(observer.password)
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Observer login failed: " + c.last_error): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming), "Observer entry failed"): return
	actor = (load("res://scripts/online_session.gd") as Script).new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void: actor_replies[int(message.get("id", -1))] = message)
	actor.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return actor.connected), "Actor transport failed"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login", {"username": fixtures.actor.username, "password": fixtures.actor.password})
	var character: Dictionary = (login.characters as Array)[0] as Dictionary
	var entry: Dictionary = await rpc("enter", {"character_id": character.id})
	var pid: int = int((entry.player as Dictionary).player_id)
	if not check(await wait_for(func() -> bool: return not peer_record(c, pid).is_empty()), "Observer did not receive actor spawn"): return
	var swings: int = 0
	for weapon: int in [21, 281]:
		var expected: int = int(c.item_info("item:%d" % weapon).doll_graphic)
		await rpc("equip", {"item_id": weapon})
		if not check(await wait_for(func() -> bool:
			var peer: Dictionary = peer_record(c, pid)
			return not peer.is_empty() and int((peer.equipment_graphics as Array)[8]) == expected
		), "Observer missed native equipment change"): return
		for direction: int in [0, 1, 2, 3]:
			await rpc("strike", {"direction": direction})
			if not check(await wait_for(func() -> bool:
				var animation: Dictionary = c.entity_animation("online_player", peer_record(c, pid))
				return animation.state == "attack" and animation.direction == c._facing(direction) and float(animation.phase) < 0.15
			), "Observer did not start native swing in the correct direction"): return
			var peer: Dictionary = peer_record(c, pid)
			var appearance: Dictionary = c.character_graphic(peer)
			if not check(not appearance.is_empty() and int((appearance.appearance as Dictionary).weapon_graphic) == expected, "Observer rendered wrong weapon"): return
			var animation: Dictionary = c.entity_animation("online_player", peer)
			var first: Dictionary = game._frame(appearance, str(animation.direction), str(animation.state), float(animation.phase))
			await create_timer(0.20).timeout
			animation = c.entity_animation("online_player", peer)
			var second: Dictionary = game._frame(appearance, str(animation.direction), str(animation.state), float(animation.phase))
			if not check(animation.state == "attack" and first.path != second.path, "Peer weapon remained on the same animation frame"): return
			swings += 1
			await create_timer(0.40).timeout
		await rpc("unequip", {"item_id": weapon})
		if not check(await wait_for(func() -> bool: return int((peer_record(c, pid).equipment_graphics as Array)[8]) == 0), "Observer missed weapon removal"): return
	c.session.request("diagnostics")
	if not check(await wait_for(func() -> bool:
		for message: Dictionary in messages:
			if str(message.get("op", "")) == "diagnostics": return true
		return false
	), "Observer diagnostics missing"): return
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "diagnostics" and not check(int((message.data as Dictionary).refreshes) == 0, "Observer needed a world refresh to animate peers"): return
	var report: Dictionary = {"result": "passed", "two_independent_native_sessions": true, "observer_equipment_updates_without_refresh": true, "observer_weapon_removal_updates": true, "weapons": [21, 281], "directions_per_weapon": 4, "observed_two_frame_weapon_swings": swings, "native_attack_direction_used": true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("PEER VISUALS LIVE PASS: ", JSON.stringify(report))
	actor.close()
	game.started = false
	c.session.close()
	game.queue_free()
	actor.queue_free()
	await process_frame
	quit(0)
