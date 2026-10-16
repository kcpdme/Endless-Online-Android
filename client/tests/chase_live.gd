extends "res://tests/mobile_network_live.gd"
func _run() -> void:
	root.size = Vector2i(1544, 720)
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	c.show_login()
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = OS.get_environment("ASTER_VALE_TEST_USERNAME")
	c.password_field.text = OS.get_environment("ASTER_VALE_TEST_PASSWORD")
	c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Chase fixture login failed"): return
	c.character_list.select(0)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming), "Chase fixture enter failed"): return
	game._select_item("item:21")
	c.equipment_request("item:21")
	if not check(await wait_for(func() -> bool: return c.is_equipped("weapon")), "Chase weapon equip failed"): return
	c.session.request("diagnostics")
	if not check(await wait_for(func() -> bool:
		for message: Dictionary in messages:
			if str(message.get("op", "")) == "diagnostics": return true
		return false
	), "Initial chase diagnostics missing"): return
	var baseline_refreshes: int = 0
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "diagnostics": baseline_refreshes = int((message.data as Dictionary).get("refreshes", 0))
	messages.clear()
	var until: int = Time.get_ticks_msec() + 70000
	var target_id: int = -1
	var killed: bool = false
	var attacks: int = 0
	var attacks_before_ack: int = 0
	var health_strip_observed: bool = false
	while Time.get_ticks_msec() < until and not killed:
		for message: Dictionary in messages:
			var data: Dictionary = message.get("data", {}) as Dictionary
			for raw: Variant in data.get("events", []):
				var event: Dictionary = raw as Dictionary
				if str(event.get("kind", "")) == "npc_killed" and int(event.get("npc_index", -1)) == target_id and int(event.get("player_id", -1)) == int(c.player.get("player_id", 0)): killed = true
		if c.npc_health_fraction(target_id) >= 0.0: health_strip_observed = true
		messages.clear()
		if killed: break
		var target: Dictionary = {}
		var closest: int = 999
		for npc: Dictionary in c.npcs:
			if int(npc.id) != 2: continue
			var steps: int = game._distance(game.player_tile, Vector2i(int(npc.x), int(npc.y)))
			if steps < closest:
				closest = steps
				target = npc
		if not target.is_empty():
			target_id = int(target.index)
			var tile: Vector2i = Vector2i(int(target.x), int(target.y))
			if closest == 1:
				game.route.clear()
				if not game.moving and game.attack_clock <= 0.0:
					game.facing = game._direction_name(tile - game.player_tile)
					game._attack()
					if game.attack_clock > 0.0:
						attacks += 1
						if not c.pending_inputs.is_empty(): attacks_before_ack += 1
			elif not game.moving and game.route.is_empty() and c.can_issue_walk(): c._approach(tile, 1)
		await process_frame
	if not check(killed and attacks > 0, "Client failed to chase and kill a real native Rat: " + c.last_error): return
	c.session.request("diagnostics")
	if not check(await wait_for(func() -> bool:
		for message: Dictionary in messages:
			if str(message.get("op", "")) == "diagnostics": return true
		return false
	), "Chase diagnostics missing"): return
	var diagnostics: Dictionary = {}
	for message: Dictionary in messages:
		if str(message.get("op", "")) == "diagnostics": diagnostics = message.data as Dictionary
	if not check(int(diagnostics.corrections) == 0 and int(diagnostics.refreshes) == baseline_refreshes, "Valid Rat chase was rewound: " + str(diagnostics)): return
	if not check(health_strip_observed, "Native Rat HP strip did not appear during battle"): return
	var report: Dictionary = {"native_rat_battle_health_strip": health_strip_observed, "result": "passed", "real_rat_chased_and_killed": true, "attacks": attacks, "attacks_without_extra_ack_wait": attacks_before_ack, "client": c.network_metrics, "server": diagnostics, "full_refreshes_during_chase": int(diagnostics.refreshes) - baseline_refreshes}
	print("CHASE LIVE PASS: ", JSON.stringify(report))
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	game.started = false
	c.session.close()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
