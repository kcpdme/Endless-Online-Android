extends SceneTree
## Fresh dev account only; full public TLS UI → gateway → native creation → bag.
var game: Node
func _initialize() -> void: call_deferred("run")
func wait_for(condition: Callable) -> bool:
	var limit: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < limit:
		if condition.call(): return true
		await process_frame
	return false
func check(ok: bool, why: String) -> bool:
	if ok: return true
	push_error(why)
	if game != null: game.started = false
	quit(1)
	return false
func letters() -> String:
	var value: String = "dev"
	for i: int in range(8): value += String.chr(97 + randi_range(0, 25))
	return value
func tap(control: Control) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 71; event.position = control.get_global_rect().get_center(); event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame
func find_button(panel: Control, text: String) -> Button:
	for child: Node in panel.get_child(0).get_children():
		if child is Button and child.text == text: return child
	return null
func run() -> void:
	root.size = Vector2i(1544, 720)
	game = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	var c: Node = game.online
	c.session.message_received.connect(func(message: Dictionary) -> void:
		print("LIVE stage: ", str(message.get("op", message.get("event", ""))), " ok=", bool(message.get("ok", true)), " error=", str(message.get("error", "")))
	)
	c.show_login(); c.host_field.text = "wss://eo.kcpd.top/ws"
	var password: String = "Dev" + letters() + "42"
	c.username_field.text = letters(); c.password_field.text = password
	c._authenticate("register")
	if not check(await wait_for(func() -> bool: return c.character_box.visible), "Public registration/login failed: " + c.last_error): return
	var report: Dictionary = {"transport":"Godot TLS WebSocket -> native EO -> persistent SQLite", "operator_accounts_used":false, "body_cases":[]}
	for gender: int in [0, 1]:
		c.creation_panel.show(); c.character_name_field.text = letters()
		c.body_choice.select(gender); c.skin_choice.select(3 if gender == 0 else 0)
		c.hair_choice.select(19 if gender == 0 else 0); c.color_choice.select(9 if gender == 0 else 0)
		c._update_creation_preview()
		var name: String = c.character_name_field.text
		await tap(find_button(c.creation_panel, "Create character"))
		if not check(await wait_for(func() -> bool: return c.selected_characters.size() == gender + 1), "Public UI creation failed: " + c.last_error): return
		var selected_index: int = -1
		for index: int in range(c.selected_characters.size()):
			if str(c.selected_characters[index].name) == name: selected_index = index
		if not check(selected_index >= 0, "Created character must be listed by name"): return
		var created: Dictionary = c.selected_characters[selected_index]
		if not check(int(created.gender) == gender and int(created.hairstyle) == (20 if gender == 0 else 1) and int(created.haircolor) == (9 if gender == 0 else 0) and int(created.race) == (3 if gender == 0 else 0), "Native selected appearance mismatch"): return
		c.character_list.select(selected_index); c._enter_selected()
		if not check(await wait_for(func() -> bool: return c.active and c.streaming and c.session.is_idle()), "Public Welcome failed: " + c.last_error): return
		var outfit: int = 151 if gender == 0 else 144
		if not check(c.bag_amount(1) == 1000 and c.bag_amount(outfit) == 1 and c.bag_amount(21) == 1 and c.bag_amount(453) == 1 and c.player.inventory.size() == 4, "Native starter bag must contain exact quantities"): return
		if not check(game.skills_ui.known(1), "Heal Self must be learned natively"): return
		# Equip through actual inventory buttons and wait for authoritative ACKs.
		for row: Array in [[outfit,"armor"],[21,"weapon"],[453,"offhand"]]:
			game.inventory.show(); game._select_item("item:%d" % int(row[0])); game._refresh_ui(); await process_frame
			await tap(game.equip_button)
			if not check(await wait_for(func() -> bool: return int(c.player.equipment.get(str(row[1]),0)) == int(row[0]) and c.session.is_idle()), "Starter Equip tap failed"): return
		game.inventory.hide()
		if not check(game.skills_ui.slots.has(1) and game.skills_ui.icon(1) != null, "Heal Self shortcut must be ready with original icon"): return
		report.body_cases.append({"gender":gender,"selected_appearance_native":true,"exact_starter_bag":true,"actual_bag_equip_buttons":true,"heal_self_learned_and_shortcut":true})
		if gender == 0:
			c.session.close()
			await create_timer(1.0).timeout
			c.show_login(); c.password_field.text = password; c._authenticate("login")
			if not check(await wait_for(func() -> bool: return c.character_box.visible and c.selected_characters.size() == 1), "Public relogin failed"): return
		report.result = "passed"
	var out: FileAccess = FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"), FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  ") + "\n"); out.close()
	print("STARTERS V41 PUBLIC UI PASS: ", JSON.stringify(report))
	c.session.close(); game.started = false; game.queue_free(); await process_frame; quit()
