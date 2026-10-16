extends RefCounted
## Original Talk local/global/whisper channels, with a bounded session-only log.
var game: Node
var panel: Control
var history: RichTextLabel
var channel: OptionButton
var target: LineEdit
var entry: LineEdit
var button: Control
var messages: Array[Dictionary] = []
var unread: int = 0

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new()
	button.kind = "chat"
	button.position = Vector2(-266, 24)
	button.size = Vector2(68, 68)
	button.pressed.connect(func() -> void: open())
	parent.add_child(button)
	game.chat_button = button
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	button.tooltip_text = "Nearby, global and private chat"
	panel = game._modal(parent, Vector2(1000, 620))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "CHAT", Vector2(36, 20), 26, game.GOLD)
	game._button(card, "×", Vector2(916, 16), Vector2(54, 48), close)
	channel = OptionButton.new()
	channel.position = Vector2(36, 78)
	channel.size = Vector2(230, 50)
	for value: String in ["Nearby", "Global", "Whisper"]: channel.add_item(value)
	channel.add_theme_font_size_override("font_size", 22)
	channel.item_selected.connect(func(_i: int) -> void: _refresh())
	card.add_child(channel)
	target = LineEdit.new()
	target.position = Vector2(286, 78)
	target.size = Vector2(430, 50)
	target.placeholder_text = "Character name"
	target.max_length = 16
	target.add_theme_font_size_override("font_size", 22)
	card.add_child(target)
	history = RichTextLabel.new()
	history.position = Vector2(36, 224)
	history.size = Vector2(920, 350)
	history.bbcode_enabled = false
	history.selection_enabled = true
	history.scroll_following = true
	history.add_theme_font_size_override("normal_font_size", 22)
	card.add_child(history)
	entry = LineEdit.new()
	entry.position = Vector2(36, 146)
	entry.size = Vector2(718, 60)
	entry.max_length = 128
	entry.placeholder_text = "Write a message…"
	entry.add_theme_font_size_override("font_size", 22)
	entry.text_submitted.connect(func(_text: String) -> void: send_message())
	card.add_child(entry)
	game._button(card, "Send", Vector2(776, 146), Vector2(180, 60), send_message, true)
	panel.hide()

func open(recipient: String = "") -> void:
	if not game.online_mode or not game.online.active:
		game._toast("Sign in to chat with other players.")
		return
	game._cancel_controls()
	game.inventory.hide()
	game.character_panel.hide()
	game.menu.hide()
	game.shop_ui.close()
	game.stats_ui.hide()
	game.services_ui.panel.hide()
	if not recipient.is_empty():
		channel.select(2)
		target.text = recipient
	unread = 0
	button.unread = false
	panel.show()
	_refresh()

func close() -> void:
	entry.release_focus()
	target.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	panel.hide()

func clear() -> void:
	messages.clear()
	unread = 0
	button.unread = false
	history.clear()
	close()

func receive(event: Dictionary) -> void:
	messages.append(event.duplicate(true))
	while messages.size() > 150: messages.pop_front()
	if not panel.visible and not bool(event.get("outgoing", false)):
		unread += 1
		button.unread = true
	_refresh()

func _refresh() -> void:
	target.visible = channel.selected == 2
	history.clear()
	var selected: String = ["local", "global", "private"][channel.selected]
	for event: Dictionary in messages:
		var kind: String = str(event.get("channel", "local"))
		if kind != selected and kind != "system": continue
		history.push_color(Color("f1d18d") if kind == "system" else (Color("9ed4ff") if kind == "private" else Color("f2ead7")))
		var name: String = str(event.get("name", "Server"))
		if bool(event.get("outgoing", false)) and kind == "private": name = "You → " + str(event.get("target", ""))
		history.add_text("%s: %s\n\n" % [name, str(event.get("message", ""))])
		history.pop()

func send_message() -> void:
	var text: String = entry.text.strip_edges()
	if text.is_empty() or not game.online.session.is_idle(): return
	var recipient: String = target.text.strip_edges().to_lower()
	if channel.selected == 2 and recipient.is_empty():
		game._toast("Choose a character name to whisper to.")
		return
	var request_id: int = game.online.session.request("chat_send", {"channel": ["local", "global", "private"][channel.selected], "message": text, "target": recipient})
	if request_id < 0: return
	entry.clear()
	if channel.selected == 0: close()
