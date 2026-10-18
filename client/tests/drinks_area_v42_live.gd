extends SceneTree
var game: Node
var peer: Node
var checks: int = 0
var events: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func wait_for(condition: Callable, seconds: float = 20.0) -> bool:
	var limit: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < limit:
		if condition.call(): return true
		await process_frame
	return false
func check(ok: bool, why: String) -> bool:
	checks += 1
	if ok: return true
	push_error(why)
	if game != null: game.started = false
	if peer != null: peer.started = false
	quit(1); return false
func tap(control: Control) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 79; event.position = control.get_global_rect().get_center(); event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame
func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("EO_V42_SHOTS")
	if folder.is_empty(): return
	await process_frame; await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(folder.path_join(name + ".png"))

func join(scene: Node, fixture: Dictionary) -> bool:
	var c: Node = scene.online
	c.show_login(); c.host_field.text = "127.0.0.1"; c.port_field.value = 18182
	c.username_field.text = str(fixture.username); c.password_field.text = str(fixture.password); c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Private native login failed"): return false
	for i: int in range(c.selected_characters.size()):
		if str(c.selected_characters[i].name) == str(fixture.character_name): c.character_list.select(i)
	c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Private native Welcome failed"): return false
	scene.music.stop(); return true
func run() -> void:
	root.size = Vector2i(1544,720)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("EO_V42_FIXTURES"))) as Dictionary
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	if not await join(game, fixtures.actor): return
	peer = load("res://main.tscn").instantiate(); root.add_child(peer); await process_frame
	peer.set_process_input(false); peer.set_process_unhandled_input(false); peer.hide(); peer.hud_root.hide(); peer.camera.enabled = false
	if not await join(peer, fixtures.observer): return
	game.camera.make_current()
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void:
		for row: Dictionary in (message.get("data", {}) as Dictionary).get("events", []): events.append(row)
	)
	if not check(c.bag_amount(210) == 3, "Fresh private fixture needs three Small Fairysodas"): return
	game._toggle_inventory(); game._select_item("item:210"); game._refresh_ui(); await process_frame
	await tap(game.equip_button)
	if not check(await wait_for(func() -> bool: return c.bag_amount(210) == 2 and game.drink_effects.drunk()), "Actual Use tap must consume one native soda and start drunk state"): return
	if not check(await wait_for(func() -> bool: return peer.drink_effects.emotes.has(int(c.player.player_id))), "Observer must display native drunk emote"): return
	if not check(not c.pending_item_use, "Native soda ACK must release pending Use"): return
	game.inventory.hide()
	await create_timer(0.30).timeout
	await screenshot("drunk-emote")
	game.skills_ui.slots.assign([14,21]); game.skills_ui.refresh()
	for slot: int in range(2):
		game.skills_ui.ready_at = 0; game.skills_ui.casting.clear(); events.clear()
		var tp: int = int(c.player.tp); var observer_tp: int = int(peer.online.player.tp)
		await tap(game.skills_ui.buttons[slot])
		if not check(game.skills_ui.armed == 0, "Actual Ice Blast shortcut must never require target selection"): return
		if not check(await wait_for(func() -> bool: return events.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "spell_area")), "Native area spell acknowledgement missing"): return
		var hits: Array = events.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "npc_damage")
		if not check(hits.size() == 5 and int(c.player.tp) == tp - 1, "Five native targets must cost exactly one TP"): return
		if not check(await wait_for(func() -> bool: return peer.skills_ui.effects.filter(func(fx: Dictionary) -> bool: return str(fx.get("kind", "")) == "npc").size() >= 5), "Observer must render original Ice Blast effects on all five monsters"): return
		if not check(int(peer.online.player.tp) == observer_tp and not peer.skills_ui.area_bursts.is_empty(), "Observer gets area visual without adopting caster TP"): return
		if not check(not game.skills_ui.area_bursts.is_empty(), "Caster must show 5x5 frost area"): return
		await screenshot("ice-blast-%d" % slot)
		await create_timer(1.0).timeout
	game.chat_ui.quick_entry.text = "hello everyone i am exploring aeven with fairy soda"
	game.chat_ui.send_quick()
	if not check(await wait_for(func() -> bool: return c.chat_bubbles.has(int(c.player.player_id))), "Drunk native chat bubble missing"): return
	var bubble: Dictionary = c.chat_bubbles[int(c.player.player_id)]
	if not check(str(bubble.text) != "hello everyone i am exploring aeven with fairy soda" and bool(bubble.get("drunk", false)), "Original slurring/stars/hiccups must arrive via acknowledged chat"): return
	if not check(await wait_for(func() -> bool: return peer.online.chat_bubbles.has(int(c.player.player_id))), "Nearby observer must receive slurred message"): return
	if not check(str(peer.online.chat_bubbles[int(c.player.player_id)].text) == str(bubble.text), "Self and observer must see identical native chat text"): return
	game.speech_layer.sync(); await process_frame
	if not check((game.speech_layer.bubbles[int(c.player.player_id)].get_node("Haze") as Label).visible, "Drunk speech has visible hazy text ghost"): return
	await screenshot("drunk-chat")
	var report: Dictionary = {"result":"passed","checks":checks,"actual_bag_use":true,"native_quantity_decrements_once":true,"native_drunk_emote_received_and_rendered_by_observer":true,"both_ice_blast_shortcuts_cast_without_selection":true,"native_five_targets_tp_once":true,"caster_and_observer_original_effects_and_area":true,"slurred_chat_same_for_sender_and_receiver":true,"hazy_speech_visible":true,"operator_accounts_used":false}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")+"\n"); file.close()
	print("DRINKS AREA V42 LIVE PASS: ",JSON.stringify(report))
	c.session.close(); peer.online.session.close(); game.started = false; peer.started = false
	game.queue_free(); peer.queue_free(); await process_frame; quit()
