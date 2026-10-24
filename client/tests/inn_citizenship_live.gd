extends SceneTree
var game: Node
var c: Node
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failed = true; push_error(message)
	return ok
func wait_for(test: Callable, seconds: float = 12.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if test.call(): return true
		await process_frame
	return false
func tap(control: Control) -> void:
	# Match a human tap after the game’s 160ms modal-gesture suppression window.
	await create_timer(.18).timeout
	await process_frame; await process_frame
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 82; touch.position = root.get_final_transform() * control.get_global_rect().get_center(); touch.pressed = true
	Input.parse_input_event(touch); await process_frame
	touch = touch.duplicate(); touch.pressed = false
	Input.parse_input_event(touch); await process_frame
func shot(name: String) -> void:
	var folder: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
func run() -> void:
	root.size = Vector2i(1544,720)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_INN_FIXTURE")))
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	c = game.online
	c.host_field.text = OS.get_environment("ASTER_VALE_TEST_HOST")
	c.username_field.text = fixture.account.username; c.password_field.text = fixture.account.password; c._authenticate("login")
	if not check(await wait_for(func() -> bool: return c.character_box.visible),"Native account login failed"): finish(); return
	c.character_list.select(0); c._enter_selected()
	if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()),"Native world entry failed"): finish(); return
	var ui: RefCounted = game.inn_ui
	var towns: Array[String] = []
	for row: Dictionary in fixture.inns:
		if int(game.world.id) != int(row.map_id):
			c.session.request("chat_send", {"channel":"local","message":"$warp %d %d %d" % [int(row.map_id), int(row.x), int(row.y)]})
			if not check(await wait_for(func() -> bool: return int(game.world.id) == int(row.map_id) and not c.transition_pending and c.session.is_idle()),"Native inn warp failed: " + str(row.home)): finish(); return
		var index: int = -1
		for npc: Dictionary in c.npcs:
			if int(npc.id) == int(row.npc_id): index = int(npc.index)
		if not check(index >= 0,"Innkeeper missing: " + str(row.home)): finish(); return
		c.session.request("inn_open", {"npc_index":index})
		if not check(await wait_for(func() -> bool: return ui.panel.visible and c.session.is_idle()),"Native inn dialogue failed: " + str(row.home)): finish(); return
		if row.home == "aeven":
			var before_gold: int = c.bag_amount(1)
			await tap(ui.sleep_button)
			if not check(await wait_for(func() -> bool: return ui.state.has("cost") and not ui.busy),"Native sleep quote failed"): finish(); return
			check(c.bag_amount(1) == before_gold,"Quote charged Gold before acceptance")
			await tap(ui.sleep_button)
			if not check(await wait_for(func() -> bool: return int(game.world.id) == 86 and not c.transition_pending and c.session.is_idle()),"Native sleep did not warp to bed"): finish(); return
			check(c.bag_amount(1) < before_gold and int(c.player.hp) == int(c.player.max_hp) and int(c.player.tp) == int(c.player.max_tp),"Paid sleep must restore native HP and TP")
			c.session.request("chat_send", {"channel":"local","message":"$warp %d %d %d" % [int(row.map_id),int(row.x),int(row.y)]})
			if not check(await wait_for(func() -> bool: return int(game.world.id) == int(row.map_id) and not c.transition_pending and c.session.is_idle()),"Return from bed failed"): finish(); return
			for npc: Dictionary in c.npcs:
				if int(npc.id) == int(row.npc_id): index = int(npc.index)
			c.session.request("inn_open", {"npc_index":index})
			if not check(await wait_for(func() -> bool: return ui.panel.visible and c.session.is_idle()),"Inn reopen failed"): finish(); return
		await tap(ui.register_button)
		check(ui.registration.visible,"Citizenship button did not open original town questions")
		if row.home == "aeven":
			for answer: LineEdit in ui.answers: answer.text = "incorrectfixture"
			await tap(ui.submit_button)
			if not check(await wait_for(func() -> bool: return not ui.busy and (ui.state.get("registration",{}) as Dictionary).has("wrong_answers")),"Native wrong-answer reply missing"): finish(); return
			check(int(ui.state.registration.wrong_answers) == 3 and ui.registration.visible and ui.answers[0].text == "incorrectfixture","Wrong answers must preserve the form and native home")
		for i: int in range(3): ui.answers[i].text = str(row.answers[i])
		await shot("inn-questions-" + str(row.home))
		await tap(ui.submit_button)
		if not check(await wait_for(func() -> bool: return not ui.busy and bool((ui.state.get("registration",{}) as Dictionary).get("accepted",false)) and str((ui.state.get("current_home",{}) as Dictionary).get("name","")) == str(row.name)),"Native citizenship failed: " + str(row.home)): finish(); return
		check(ui.summary.visible and not ui.registration.visible and ui.detail.text.contains(str(row.name)),"Confirmed respawn must be shown in the inn")
		towns.append(str(row.home))
		await shot("inn-registered-" + str(row.home))
		if row.home == "aeven":
			await tap(ui.register_button)
			c.session.request("refresh")
			await wait_for(func() -> bool: return c.session.is_idle())
			check(ui.registration.visible, "World refresh must not close a reopened citizenship form")
			game._handle_back()
			await tap(ui.remove_button)
			check(ui.confirm.visible, "Renouncing citizenship must require confirmation")
			game._handle_back()
			check(not ui.confirm.visible and ui.panel.visible, "Back must cancel renunciation and keep the inn open")
			await tap(ui.remove_button)
			ui.confirm.hide(); ui.confirm.confirmed.emit()
			if not check(await wait_for(func() -> bool: return not ui.busy and bool(ui.state.get("removed",false))), "Confirmed UI renunciation was not native acknowledged"): finish(); return
			check(str(ui.state.current_home.name) == "Aeven", "Renouncing must show default home")
		ui.close(); await wait_for(func() -> bool: return c.session.is_idle())
	c.log_out()
	check(await wait_for(func() -> bool: return c.panel.visible and not game.started),"Logout failed after registration")
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"native_citizenship_towns":towns,"native_wrong_answers_preserve_form":true,"native_quote_before_sleep_payment":true,"native_sleep_hp_tp_and_bed_warp":true,"native_respawn_confirmation":true,"native_ui_renunciation_and_back_cancellation":true}
	var file: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print("INN CITIZENSHIP LIVE: ",JSON.stringify(report))
	finish()
func finish() -> void:
	if game != null: game.queue_free()
	await process_frame; await process_frame
	quit(1 if failed else 0)
