extends "res://tests/peer_visuals_live.gd"
## Touch shortcuts and target selection against real native spells; no simulated combat.
func capture(label: String) -> void:
	var directory: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

func login_fixture(c: Node, fixture: Dictionary) -> bool:
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
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES"))) as Dictionary
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void: messages.append(message))
	if not check(await login_fixture(c, fixtures.actor), "Skill actor login: " + c.last_error): return
	var ui: RefCounted = game.skills_ui
	if not check(ui.slots.size() == 2 and ui.slots.has(1) and ui.slots.has(4), "Learned native spells missing from shortcuts"): return
	for button: Button in ui.buttons:
		if not check(button.visible and root.get_visible_rect().encloses(button.get_global_rect()), "Skill button outside screen"): return
	actor = (load("res://scripts/online_session.gd") as Script).new()
	root.add_child(actor)
	actor.message_received.connect(func(message: Dictionary) -> void: actor_replies[int(message.get("id", -1))] = message)
	actor.open(c.host_field.text, 8079)
	if not check(await wait_for(func() -> bool: return actor.connected), "Observer transport failed"): return
	await rpc("connect")
	var login: Dictionary = await rpc("login", {"username": fixtures.observer.username, "password": fixtures.observer.password})
	var peer_entry: Dictionary = await rpc("enter", {"character_id": (login.characters as Array)[0].id})
	var peer_id: int = int((peer_entry.player as Dictionary).player_id)
	await rpc("stream", {"enabled": true})
	var hp: int = int(c.player.hp)
	var tp: int = int(c.player.tp)
	var slot: int = ui.slots.find(1)
	touch(ui.buttons[slot].get_global_rect().get_center(), true)
	touch(ui.buttons[slot].get_global_rect().get_center(), false)
	if not check(not ui.casting.is_empty() and ui.armed == 0, "Self heal touch did not start casting"): return
	await capture("v13-heal-chant")
	if not check(await wait_for(func() -> bool: return ui.casting.is_empty() and int(c.player.hp) > hp and int(c.player.tp) == tp - 1), "Native Heal Self did not reach HUD: " + c.last_error): return
	await capture("v13-heal-effect")
	if not check(not ui.effects.is_empty(), "Original heal effect was not decoded"): return
	await create_timer(.85).timeout
	var target: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 2 and game._distance(game.player_tile, Vector2i(int(npc.x), int(npc.y))) <= 10:
			target = npc
			break
	if not check(not target.is_empty(), "No rat in spell range"): return
	slot = ui.slots.find(4)
	touch(ui.buttons[slot].get_global_rect().get_center(), true)
	touch(ui.buttons[slot].get_global_rect().get_center(), false)
	if not check(ui.armed == 4 and ui.casting.is_empty(), "Fire shortcut must arm before selecting an NPC"): return
	await capture("v13-fire-selected")
	c.map_click(Vector2i(int(target.x), int(target.y)))
	if not check(not ui.casting.is_empty() and ui.armed == 0 and game.route.is_empty(), "NPC tap must cast instead of walking to melee range"): return
	await capture("v13-fire-chant")
	tp = int(c.player.tp)
	if not check(await wait_for(func() -> bool: return ui.casting.is_empty() and int(c.player.tp) == tp - 1 and not ui.effects.is_empty()), "Native fire result or TP/effect missing: " + c.last_error): return
	await capture("v13-fire-effect")
	await create_timer(.8).timeout
	await rpc("spell_cast", {"spell_id": 1, "target_kind": "self"})
	if not check(await wait_for(func() -> bool: return ui.is_chanting(peer_id)), "Nearby player's native chant was not rendered"): return
	var peer: Dictionary = peer_record(c, peer_id)
	if not check(not peer.is_empty() and str(c.entity_animation("online_player", peer).state) == "cast", "Nearby player remains in idle instead of original casting pose"): return
	var appearance: Dictionary = c.character_graphic(peer)
	if not check(not game._frame(appearance, c._facing(peer.direction), "cast").is_empty(), "Original peer casting pose missing"): return
	await capture("v13-peer-casting")
	if not check(await wait_for(func() -> bool:
		for fx: Dictionary in ui.effects:
			if str(fx.kind) == "player" and int(fx.id) == peer_id: return true
		return false
	), "Nearby player's heal effect was not rendered"): return
	ui.press(2)
	if not check(ui.panel.visible and ui.list.item_count >= 3, "Skills book missing learned spells"): return
	if not check(root.get_visible_rect().encloses((ui.panel.get_child(0) as Control).get_global_rect()), "Skill window does not fit screen"): return
	await capture("v13-skills-book")
	ui.panel.hide()
	actor.close()
	c.session.close()
	c._on_closed("Test switching to skill master fixture")
	await create_timer(.7).timeout
	if not check(await login_fixture(c, fixtures.master), "Master fixture login: " + c.last_error): return
	var master: Dictionary = {}
	for npc: Dictionary in c.npcs:
		if int(npc.id) == 116: master = npc
	if not check(not master.is_empty(), "Original skill master missing"): return
	c.map_click(Vector2i(int(master.x), int(master.y)))
	if not check(await wait_for(func() -> bool: return ui.panel.visible and not ui.master.is_empty() and c.session.is_idle()), "Tap skill master did not open original offers: " + c.last_error): return
	if not check(ui.list.item_count >= 3, "Native master offers missing"): return
	for i: int in range(ui.list.item_count):
		if int(ui.list.get_item_metadata(i)) == 1:
			ui.list.select(i)
			ui.list.item_selected.emit(i)
	await capture("v13-original-skill-master")
	if not check(not ui.learn_button.disabled, "Skill master Learn should be available"): return
	ui.learn_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return ui.known(1) and c.session.is_idle()), "Native learning did not update skills book: " + c.last_error): return
	ui.forget_button.pressed.emit()
	if not check(await wait_for(func() -> bool: return not ui.known(1) and c.session.is_idle()), "Native forgetting did not update skills book"): return
	var report: Dictionary = {"result": "passed", "touch_shortcuts_with_native_spell_icons": true, "self_heal_cast_hp_tp_hud_effect": true, "tap_skill_then_npc_without_melee_path": true, "native_fire_tp_damage_and_original_effect": true, "skills_book_fits_screen": true, "observer_renders_original_peer_casting_pose_and_effect": true, "tap_skill_master_original_offers_learn_forget": true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("SKILLS UI LIVE PASS: ", JSON.stringify(report))
	c.session.close()
	game.started = false
	game.queue_free()
	actor.queue_free()
	await process_frame
	quit(0)
