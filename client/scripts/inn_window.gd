extends RefCounted
## Native sleep quote and town-question citizenship, with server-confirmed home.
var game: Node
var panel: Control
var title: Label
var detail: Label
var notice: Label
var sleep_button: Button
var register_button: Button
var remove_button: Button
var submit_button: Button
var summary: VBoxContainer
var registration: VBoxContainer
var questions: Array[Label] = []
var answers: Array[LineEdit] = []
var confirm: ConfirmationDialog
var state: Dictionary = {}
var busy: bool = false
var registration_reply: bool = false
var identity: String = ""

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(920, 640))
	var card: Control = panel.get_child(0)
	game._wood_card(card)
	var margin: MarginContainer = MarginContainer.new()
	card.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 24)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	var header: HBoxContainer = HBoxContainer.new()
	body.add_child(header)
	title = game._label(header, "Innkeeper", Vector2.ZERO, 28, game.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exit: Button = button(header, "×", close)
	exit.custom_minimum_size.x = 60
	exit.size_flags_horizontal = Control.SIZE_SHRINK_END
	detail = game._label(body, "", Vector2.ZERO, 19)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice = game._label(body, "", Vector2.ZERO, 18, game.GOLD)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	summary = VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 16)
	scroll.add_child(summary)
	var info: Label = game._label(summary, "Citizenship sets the town where you return after death.\nSleeping restores HP and TP and takes you to a bed.", Vector2.ZERO, 19, game.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	register_button = button(summary, "Citizenship · Set respawn here", open_registration, true)
	sleep_button = button(summary, "Sleep · Ask price", func() -> void: send("inn_sleep" if state.has("cost") else "inn_quote"))
	remove_button = button(summary, "Give up citizenship…", func() -> void: confirm.popup_centered())
	registration = VBoxContainer.new()
	registration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	registration.add_theme_constant_override("separation", 10)
	scroll.add_child(registration)
	for index: int in range(3):
		var question: Label = game._label(registration, "", Vector2.ZERO, 19)
		question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		questions.append(question)
		var answer: LineEdit = LineEdit.new()
		answer.custom_minimum_size.y = 48
		answer.max_length = 80
		answer.placeholder_text = "Your answer"
		answer.add_theme_font_size_override("font_size", 21)
		registration.add_child(answer)
		answers.append(answer)
		var slot: int = index
		answer.text_submitted.connect(func(_text: String) -> void:
			if slot < 2: answers[slot + 1].grab_focus()
			else: answer.release_focus(); hide_keyboard()
		)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	registration.add_child(actions)
	button(actions, "Back", show_summary)
	submit_button = button(actions, "Register · Set respawn", submit_registration, true)
	confirm = ConfirmationDialog.new()
	confirm.title = "Give up citizenship?"
	confirm.dialog_text = "Your death respawn will return to the default home."
	confirm.ok_button_text = "Give up citizenship"
	confirm.confirmed.connect(func() -> void: send("inn_remove"))
	game.add_child(confirm)
	registration.hide()
	panel.hide()

func button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var result: Button = game._button(parent, text, Vector2.ZERO, Vector2.ONE, action, primary)
	result.custom_minimum_size.y = 56
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func send(operation: String, fields: Dictionary = {}) -> void:
	if busy: return
	busy = game.online.session.request(operation, fields) >= 0
	refresh()

func request_finished(error: String = "", operation: String = "") -> void:
	busy = false
	registration_reply = operation == "inn_register" and error.is_empty()
	if not error.is_empty(): state["notice"] = error
	refresh()

func open_registration() -> void:
	if busy or (state.get("questions", []) as Array).size() != 3: return
	for index: int in range(3):
		questions[index].text = "%d. %s" % [index + 1, str((state.get("questions", []) as Array)[index])]
		answers[index].clear()
	summary.hide()
	registration.show()
	refresh()

func submit_registration() -> void:
	for answer: LineEdit in answers:
		if answer.text.strip_edges().is_empty():
			notice.text = "Please answer all three questions."
			answer.grab_focus()
			return
	for answer: LineEdit in answers: answer.release_focus()
	hide_keyboard()
	send("inn_register", {"answer1": answers[0].text.strip_edges(), "answer2": answers[1].text.strip_edges(), "answer3": answers[2].text.strip_edges()})

func show_summary() -> void:
	for answer: LineEdit in answers: answer.release_focus()
	hide_keyboard()
	registration.hide()
	summary.show()
	refresh()

func receive(data: Dictionary) -> void:
	if not data.has("inn"): return
	if not data.inn is Dictionary:
		state.clear(); identity = ""; busy = false; registration_reply = false
		confirm.hide(); panel.hide()
		return
	state = (data.inn as Dictionary).duplicate(true)
	var key: String = "%d:%d" % [int(state.map_id), int(state.npc_index)] if state.has("map_id") else str(state.npc_index)
	if key != identity:
		identity = key
		show_summary()
		for answer: LineEdit in answers: answer.clear()
	if registration_reply and bool((state.get("registration", {}) as Dictionary).get("accepted", false)): show_summary()
	registration_reply = false
	game._cancel_controls()
	game.quest_ui.panel.hide()
	game.shop_ui.close()
	game.services_ui.panel.hide()
	refresh()
	panel.show()

func refresh() -> void:
	if sleep_button == null: return
	var npc: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(state.get("npc_id", 0))), {}) as Dictionary
	var home: Dictionary = state.get("home", {}) as Dictionary
	var current: Dictionary = state.get("current_home", {}) as Dictionary
	title.text = str(npc.get("name", "Innkeeper")) + (" · " + str(home.name) if home.has("name") else "")
	detail.text = "Current respawn: " + str(current.get("name", "Ask this innkeeper"))
	if current.has("map_id"): detail.text += " · Map %d (%d, %d)" % [int(current.map_id), int(current.x), int(current.y)]
	if state.has("cost"): detail.text += "\nA night’s rest: %d Gold" % int(state.cost)
	notice.text = "Please wait for the innkeeper…" if busy else str(state.get("notice", "Answer the town’s three questions to register your new respawn."))
	var player: Dictionary = game.online.player
	var rested: bool = int(player.get("max_hp", 0)) > 0 and int(player.get("hp", 0)) >= int(player.get("max_hp", 0)) and int(player.get("tp", 0)) >= int(player.get("max_tp", 0))
	sleep_button.text = "Sleep · Fully rested" if rested else ("Sleep · %d Gold" % int(state.cost) if state.has("cost") else "Sleep · Ask price")
	sleep_button.disabled = busy or rested or (state.has("cost") and game.online.bag_amount(1) < int(state.cost))
	register_button.disabled = busy or (state.get("questions", []) as Array).size() != 3
	remove_button.disabled = busy
	submit_button.disabled = busy
	for answer: LineEdit in answers: answer.editable = not busy

func back() -> void:
	if confirm.visible: confirm.hide()
	elif registration.visible: show_summary()
	else: close()

func close() -> void:
	confirm.hide()
	show_summary()
	game.online.session.request("inn_close")
	state.clear(); identity = ""; busy = false; registration_reply = false
	panel.hide()

func disconnected() -> void:
	confirm.hide()
	panel.hide()
	state.clear(); identity = ""; busy = false; registration_reply = false
	for answer: LineEdit in answers: answer.clear()

func hide_keyboard() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
