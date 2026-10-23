extends RefCounted
## Native EO conversations and world-wide presence, with a compact game HUD composer.
const CHANNELS: Array[String] = ["local", "global", "private"]
const TITLES: Array[String] = ["Nearby", "Global", "Whispers", "Online"]
var game: Node
var panel: Control
var heading: Label
var subheading: Label
var history: RichTextLabel
var channel: OptionButton
var target: LineEdit
var entry: LineEdit
var button: Control
var tabs: Array[Button] = []
var messages: Array[Dictionary] = []
var unread: int = 0
var unread_channels: Array[int] = [0, 0, 0]
var contacts: ItemList
var online_list: ItemList
var search: LineEdit
var roster_status: Label
var refresh_button: Button
var roster: Array[Dictionary] = []
var roster_at: int = -10000
var roster_pending: bool = false
var quick_root: Control
var feed_background: Control
var quick_bar: Control
var quick_channel: OptionButton
var quick_entry: LineEdit
var feed: RichTextLabel
var pending_chat: Dictionary = {}
var last_send: int = -700
var reply_to: String = ""
var visible_tab: int = -1
var roster_stamp: String = ""
var last_keyboard_lift: float = 0.0
var scroll_fingers: Dictionary = {}

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
	button.tooltip_text = "Conversations and online players"
	panel = game._modal(parent, Vector2(1000, 620))
	var card: Control = panel.get_child(0) as Control
	card.add_theme_stylebox_override("panel", game._style(Color("102126"), Color("64756e"), 16))
	heading = game._label(card, "CONVERSATIONS", Vector2(32, 20), 26, game.GOLD)
	subheading = game._label(card, "Drag history to scroll · Tap a name to whisper", Vector2(32, 55), 16, game.MUTED)
	game._button(card, "×", Vector2(916, 18), Vector2(54, 48), close)
	channel = OptionButton.new()
	for title: String in TITLES: channel.add_item(title)
	card.add_child(channel)
	channel.hide() # Tab selection remains a stable API for existing chat callers.
	channel.item_selected.connect(func(index: int) -> void: select_tab(index))
	for index: int in range(4):
		var tab: int = index
		var control: Button = game._button(card, TITLES[index], Vector2(32 + index * 236, 94), Vector2(228, 44), func() -> void: select_tab(tab))
		tabs.append(control)
	history = _log(card, Vector2(32, 154), Vector2(936, 360), 20)
	history.selection_enabled = true
	contacts = ItemList.new()
	contacts.position = Vector2(32, 154)
	contacts.size = Vector2(226, 360)
	contacts.add_theme_font_size_override("font_size", 19)
	contacts.max_text_lines = 2
	contacts.add_theme_constant_override("v_separation", 12)
	contacts.item_selected.connect(func(index: int) -> void: open(str(contacts.get_item_metadata(index))))
	card.add_child(contacts)
	target = LineEdit.new()
	target.position = Vector2(280, 154)
	target.size = Vector2(688, 44)
	target.placeholder_text = "Whisper to character name…"
	target.max_length = 16
	target.add_theme_font_size_override("font_size", 20)
	target.text_changed.connect(func(_value: String) -> void: _refresh())
	card.add_child(target)
	entry = LineEdit.new()
	entry.position = Vector2(32, 542)
	entry.size = Vector2(732, 50)
	entry.max_length = 128
	entry.placeholder_text = "Write a message…  /w name message · /r reply"
	entry.add_theme_font_size_override("font_size", 20)
	entry.text_submitted.connect(func(_text: String) -> void: send_message())
	card.add_child(entry)
	var send: Button = game._button(card, "Send", Vector2(780, 542), Vector2(188, 50), send_message, true)
	send.name = "ChatSend"
	search = LineEdit.new()
	search.position = Vector2(32, 154)
	search.size = Vector2(652, 44)
	search.placeholder_text = "Find an online player…"
	search.add_theme_font_size_override("font_size", 20)
	search.text_changed.connect(func(_value: String) -> void: render_roster())
	card.add_child(search)
	refresh_button = game._button(card, "Refresh", Vector2(706, 154), Vector2(262, 44), func() -> void: request_roster(true))
	online_list = ItemList.new()
	online_list.position = Vector2(32, 212)
	online_list.size = Vector2(936, 302)
	online_list.add_theme_font_size_override("font_size", 20)
	online_list.fixed_icon_size = Vector2i(24, 24)
	online_list.max_text_lines = 2
	online_list.fixed_column_width = 896
	online_list.add_theme_constant_override("v_separation", 12)
	online_list.item_selected.connect(func(index: int) -> void:
		var name: String = str(online_list.get_item_metadata(index))
		if name.to_lower() == str(game.online.player.get("name", "")).to_lower(): return
		open(name)
		entry.call_deferred("grab_focus")
	)
	card.add_child(online_list)
	roster_status = game._label(card, "", Vector2(32, 550), 18, game.MUTED)
	_build_quick(parent)
	panel.hide()
	_refresh()

func _log(parent: Control, at: Vector2, dimensions: Vector2, font_size: int) -> RichTextLabel:
	var log: RichTextLabel = RichTextLabel.new()
	log.position = at
	log.size = dimensions
	log.bbcode_enabled = false
	log.scroll_following = true
	log.scroll_active = true
	log.mouse_filter = Control.MOUSE_FILTER_STOP
	log.gui_input.connect(func(event: InputEvent) -> void: _scroll_input(log, event))
	log.get_v_scroll_bar().custom_minimum_size.x = 22
	log.add_theme_font_size_override("normal_font_size", font_size)
	log.add_theme_constant_override("line_separation", 5)
	log.meta_clicked.connect(func(meta: Variant) -> void: open(str(meta)))
	parent.add_child(log)
	return log

func _scroll_input(log: RichTextLabel, event: InputEvent) -> void:
	var key: int = log.get_instance_id()
	if event is InputEventScreenTouch:
		if event.pressed: scroll_fingers[key] = event.index
		elif scroll_fingers.get(key, -1) == event.index: scroll_fingers.erase(key)
	elif event is InputEventScreenDrag and int(scroll_fingers.get(key, -1)) == event.index:
		log.selection_enabled = false
		log.scroll_following = false
		var bar: VScrollBar = log.get_v_scroll_bar()
		bar.value = clampf(bar.value - event.relative.y, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
		log.accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT: log.selection_enabled = log == history
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: log.scroll_following = false

func _build_quick(parent: Control) -> void:
	quick_root = Control.new()
	quick_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quick_root.position = Vector2(-252, -212)
	quick_root.size = Vector2(504, 196)
	parent.add_child(quick_root)
	quick_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	var backdrop: StyleBoxFlat = game._style(Color(0.025, 0.055, 0.065, 0.50), Color(0.70, 0.77, 0.70, 0.20), 9)
	var feed_panel: Panel = Panel.new()
	feed_background = feed_panel
	feed_panel.size = Vector2(504, 134)
	feed_panel.add_theme_stylebox_override("panel", backdrop)
	quick_root.add_child(feed_panel)
	feed = _log(quick_root, Vector2(12, 8), Vector2(480, 118), 16)
	feed.selection_enabled = false
	feed.scroll_active = true
	feed.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	feed.add_theme_constant_override("outline_size", 3)
	feed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quick_bar = game._panel(quick_root, Vector2(0, 144), Vector2(504, 52), Color(0.03, 0.075, 0.085, 0.86))
	quick_channel = OptionButton.new()
	quick_channel.position = Vector2(8, 6)
	quick_channel.size = Vector2(104, 40)
	quick_channel.add_item("Nearby")
	quick_channel.add_item("Global")
	quick_channel.add_item("Whisper")
	quick_channel.add_theme_font_size_override("font_size", 16)
	quick_channel.item_selected.connect(func(index: int) -> void:
		game._cancel_controls()
		if index == 2:
			open(reply_to)
			select_tab(2)
	)
	quick_channel.get_popup().about_to_popup.connect(func() -> void: game._cancel_controls())
	quick_bar.add_child(quick_channel)
	quick_entry = LineEdit.new()
	quick_entry.position = Vector2(120, 5)
	quick_entry.size = Vector2(300, 42)
	quick_entry.max_length = 128
	quick_entry.placeholder_text = "Say something…"
	quick_entry.add_theme_font_size_override("font_size", 18)
	quick_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	quick_entry.focus_entered.connect(func() -> void: game._cancel_controls())
	quick_entry.text_submitted.connect(func(_text: String) -> void: send_quick())
	quick_bar.add_child(quick_entry)
	var quick_send: Button = game._button(quick_bar, "Send", Vector2(426, 6), Vector2(70, 40), send_quick)
	quick_send.add_theme_font_size_override("font_size", 16)
	for state: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = game._style(Color("263f42"), Color("bda470"), 8)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		quick_send.add_theme_stylebox_override(state, style)
	quick_root.hide()

func hud_contains(point: Vector2) -> bool:
	return quick_root.visible and (quick_bar.get_global_rect().has_point(point) or (not messages.is_empty() and feed.get_global_rect().has_point(point)))

func typing() -> bool:
	return quick_entry.has_focus() or quick_channel.get_popup().visible

func blur_quick() -> void:
	var focused: bool = quick_entry.has_focus()
	quick_entry.release_focus()
	if focused and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()

func tick() -> void:
	var active: bool = game.online_mode and game.online.active and game.started
	if not active:
		blur_quick()
		if panel.visible: close()
	quick_root.visible = active and not game._modal_open() and not game.welcome.visible
	feed_background.visible = not messages.is_empty()
	feed.visible = not messages.is_empty()
	if not quick_root.visible and quick_entry.has_focus(): blur_quick()
	var keyboard: float = float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	var lift: float = clampf(keyboard * game.get_viewport_rect().size.y / maxf(1.0, DisplayServer.window_get_size().y), 0, game.get_viewport_rect().size.y * 0.6)
	quick_root.offset_top = -212 - lift
	quick_root.offset_bottom = -16 - lift
	_layout(lift)
	if panel.visible and channel.selected == 3:
		if roster_pending and Time.get_ticks_msec() - roster_at > 8000:
			roster_pending = false
			roster_status.text = "Could not refresh. Tap Refresh to try again."
		elif not roster_pending and Time.get_ticks_msec() - roster_at >= 10000: request_roster()

func open(recipient: String = "") -> void:
	if not game.online_mode or not game.online.active:
		game._toast("Sign in to chat with other players.")
		return
	blur_quick()
	game._cancel_controls()
	game.inventory.hide()
	game.character_panel.hide()
	game.menu.hide()
	game.shop_ui.close()
	game.stats_ui.dismiss()
	game.services_ui.panel.hide()
	game.skills_ui.panel.hide()
	game.quick_items.panel.hide()
	if not recipient.is_empty():
		channel.select(2)
		target.text = recipient.to_lower()
		reply_to = recipient.to_lower()
	unread = 0
	button.unread = false
	panel.show()
	_refresh()
	if channel.selected == 3: request_roster()

func select_tab(index: int) -> void:
	channel.select(index)
	if index < 3: unread_channels[index] = 0
	_refresh()
	if index == 3: request_roster()

func close() -> void:
	var focused: bool = entry.has_focus() or target.has_focus() or search.has_focus()
	entry.release_focus()
	target.release_focus()
	search.release_focus()
	blur_quick()
	if focused and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	panel.hide()

func clear() -> void:
	messages.clear()
	roster.clear()
	roster_stamp = ""
	roster_at = -10000
	roster_pending = false
	reply_to = ""
	pending_chat.clear()
	unread = 0
	unread_channels.assign([0, 0, 0])
	button.unread = false
	history.clear()
	feed.clear()
	entry.clear()
	target.clear()
	quick_entry.clear()
	channel.select(0)
	quick_channel.select(0)
	close()

func receive(event: Dictionary) -> void:
	var row: Dictionary = event.duplicate(true)
	var clock: Dictionary = Time.get_time_dict_from_system()
	row["time"] = "%02d:%02d" % [int(clock.hour), int(clock.minute)]
	messages.append(row)
	while messages.size() > 250: messages.pop_front()
	var kind: String = str(row.get("channel", "system"))
	var index: int = CHANNELS.find(kind)
	if kind == "private" and not bool(row.get("outgoing", false)): reply_to = str(row.get("name", "")).to_lower()
	if not bool(row.get("outgoing", false)) and (not panel.visible or channel.selected != index):
		unread += 1
		if index >= 0: unread_channels[index] += 1
		button.unread = true
	_refresh()
	_render_feed()

func _append(log: RichTextLabel, row: Dictionary, compact: bool = false) -> void:
	var kind: String = str(row.get("channel", "system"))
	var color: Color = Color("a9dfff") if kind == "private" else Color("efce88") if kind == "global" else Color("e6eee5") if kind == "local" else Color("f4a29a")
	log.push_color(color)
	var prefix: String = {"local":"N", "global":"G", "private":"W", "guild":"Guild", "party":"Party", "system":"!"}.get(kind, "!")
	log.add_text("[%s] " % prefix if compact else str(row.get("time", "")) + "  ")
	var name: String = str(row.get("name", "Server"))
	if bool(row.get("outgoing", false)) and kind == "private": name = "You → " + str(row.get("target", ""))
	var recipient: String = str(row.get("target", "")) if bool(row.get("outgoing", false)) else str(row.get("name", ""))
	if kind != "system" and recipient.to_lower() != str(game.online.player.get("name", "")).to_lower(): log.push_meta(recipient.to_lower())
	log.add_text(name)
	if kind != "system" and recipient.to_lower() != str(game.online.player.get("name", "")).to_lower(): log.pop()
	log.add_text(": " + str(row.get("message", "")) + ("\n" if compact else "\n\n"))
	log.pop()

func _render_feed() -> void:
	var bar: VScrollBar = feed.get_v_scroll_bar()
	var previous: float = bar.value
	var follow: bool = bar.value >= bar.max_value - bar.page - 4
	feed.scroll_following = follow
	feed.clear()
	for row: Dictionary in messages: _append(feed, row, true)
	if not follow: bar.set_deferred("value", previous)

func _refresh() -> void:
	var selected: int = channel.selected
	var online_tab: bool = selected == 3
	var private_tab: bool = selected == 2
	for index: int in range(tabs.size()):
		tabs[index].text = TITLES[index] + (" · %d" % roster.size() if index == 3 else " · %d" % unread_channels[index] if unread_channels[index] > 0 else "")
		tabs[index].modulate = Color("f5d899") if index == selected else Color("b3c2bf")
	target.visible = private_tab
	contacts.visible = private_tab
	history.visible = not online_tab
	entry.visible = not online_tab
	(panel.get_child(0).get_node("ChatSend") as Button).visible = not online_tab
	search.visible = online_tab
	online_list.visible = online_tab
	refresh_button.visible = online_tab
	roster_status.visible = online_tab
	history.position = Vector2(280, 212) if private_tab else Vector2(32, 154)
	history.size = Vector2(688, 302) if private_tab else Vector2(936, 360)
	var scroll: VScrollBar = history.get_v_scroll_bar()
	var previous: float = scroll.value
	var follow: bool = scroll.value >= scroll.max_value - scroll.page - 4 or visible_tab != selected
	visible_tab = selected
	history.scroll_following = follow
	history.clear()
	for event: Dictionary in messages:
		var kind: String = str(event.get("channel", "local"))
		if kind != "system" and (selected >= 3 or kind != CHANNELS[selected]): continue
		if private_tab and kind == "private" and not target.text.strip_edges().is_empty():
			var contact: String = str(event.get("target", "")) if bool(event.get("outgoing", false)) else str(event.get("name", ""))
			if contact.to_lower() != target.text.strip_edges().to_lower(): continue
		_append(history, event)
	if not follow: scroll.set_deferred("value", previous)
	contacts.clear()
	var names: Array[String] = []
	for index: int in range(messages.size() - 1, -1, -1):
		var event: Dictionary = messages[index]
		if str(event.get("channel", "")) != "private": continue
		var name: String = str(event.get("target", "")) if bool(event.get("outgoing", false)) else str(event.get("name", ""))
		if name.is_empty() or names.has(name): continue
		names.append(name)
		var item: int = contacts.add_item(name.capitalize())
		contacts.set_item_metadata(item, name)
	if contacts.item_count == 0:
		var placeholder: int = contacts.add_item("Choose someone\nfrom Online")
		contacts.set_item_disabled(placeholder, true)
	if online_tab: render_roster()
	_layout()

func _layout(keyboard_lift: float = -1.0) -> void:
	if keyboard_lift >= 0.0: last_keyboard_lift = keyboard_lift
	var viewport: Vector2 = game.get_viewport_rect().size
	var available: float = viewport.y - last_keyboard_lift
	var height: float = clampf(available - 24, 280, 620)
	var compact: bool = height < 560
	var card: Control = panel.get_child(0) as Control
	card.size = Vector2(1000, height)
	card.position = Vector2((viewport.x - 1000) / 2.0, maxf(12.0, (available - height) / 2.0))
	heading.visible = not compact
	subheading.visible = not compact
	for index: int in range(tabs.size()):
		tabs[index].position = Vector2(32 + index * (218 if compact else 236), 16 if compact else 94)
		tabs[index].size = Vector2(210 if compact else 228, 44)
	var top: float = 74 if compact else 154
	var bottom: float = height - 106
	target.position.y = top
	contacts.position.y = top
	contacts.size.y = maxf(40, bottom - top)
	search.position.y = top
	refresh_button.position.y = top
	online_list.position.y = top + 58
	online_list.size.y = maxf(40, bottom - top - 58)
	var private_tab: bool = channel.selected == 2
	history.position = Vector2(280, top + 58) if private_tab else Vector2(32, top)
	history.size = Vector2(688 if private_tab else 936, maxf(40, bottom - top - (58 if private_tab else 0)))
	entry.position.y = height - 78
	(card.get_node("ChatSend") as Control).position.y = height - 78
	roster_status.position.y = height - 70
	# The close control keeps its place in the header even when the keyboard is up.

func request_roster(force: bool = false) -> void:
	if roster_pending or not game.online.active: return
	if not force and Time.get_ticks_msec() - roster_at < 5000: return
	if game.online.transition_pending or game.moving or not game.online.pending_inputs.is_empty(): return
	if game.online.session.request("online_players") < 0: return
	roster_pending = true
	roster_at = Time.get_ticks_msec()
	roster_status.text = "Refreshing online players…"

func receive_roster(event: Dictionary) -> void:
	roster.clear()
	for player: Variant in event.get("players", []):
		if player is Dictionary: roster.append(player as Dictionary)
	roster_pending = false
	roster_stamp = ""
	render_roster()
	_refresh()

func render_roster() -> void:
	var query: String = search.text.strip_edges().to_lower()
	var stamp: String = JSON.stringify([roster, query])
	if stamp != roster_stamp:
		roster_stamp = stamp
		online_list.clear()
		for player: Dictionary in roster:
			var name: String = str(player.get("name", ""))
			if not query.is_empty() and not name.to_lower().contains(query): continue
			var own: bool = name.to_lower() == str(game.online.player.get("name", "")).to_lower()
			var classes: Dictionary = game.online.catalog.get("classes", {}) as Dictionary
			var definition: Dictionary = classes.get(str(int(player.get("class_id", 0))), {}) as Dictionary
			var label: String = "●  " + str(player.get("display_name", name)).capitalize() + ("  (You)" if own else "")
			var extras: Array[String] = []
			if not str(definition.get("name", "")).is_empty(): extras.append(str(definition.name))
			if not str(player.get("guild", "")).is_empty(): extras.append("[" + str(player.guild) + "]")
			if not str(player.get("title", "")).is_empty(): extras.append(str(player.title))
			label += "\n    " + (" · ".join(extras) if not extras.is_empty() else "Adventurer")
			var index: int = online_list.add_item(label)
			online_list.set_item_metadata(index, name)
			online_list.set_item_custom_fg_color(index, Color("849593") if own else Color("b8e4cc"))
	if not roster_pending: roster_status.text = "%d online across the world · Tap a player to whisper" % roster.size()

func send_message() -> void:
	_send(entry, CHANNELS[mini(channel.selected, 2)], target.text.strip_edges().to_lower(), false)

func send_quick() -> void:
	_send(quick_entry, CHANNELS[quick_channel.selected], reply_to, true)

func _send(field: LineEdit, kind: String, recipient: String, quick: bool) -> void:
	var text: String = field.text.strip_edges()
	if text.is_empty(): return
	if not game.online.active or not pending_chat.is_empty(): return
	if Time.get_ticks_msec() - last_send < 700:
		game._toast("Wait a moment between messages.")
		return
	var words: PackedStringArray = text.split(" ", false, 2)
	if words.size() > 0 and words[0].to_lower() in ["/w", "/whisper"]:
		if words.size() < 3:
			game._toast("Use /w name message")
			return
		kind = "private"; recipient = words[1].to_lower(); text = words[2]
	elif words.size() > 1 and words[0].to_lower() in ["/g", "/global", "/s", "/nearby", "/r"]:
		var command: String = words[0].to_lower()
		text = text.substr(words[0].length()).strip_edges()
		kind = "global" if command in ["/g", "/global"] else "private" if command == "/r" else "local"
		if command == "/r": recipient = reply_to
	elif text.begins_with("!") and text.contains(" "):
		recipient = text.get_slice(" ", 0).substr(1).to_lower()
		text = text.substr(text.find(" ") + 1).strip_edges();kind = "private"
	if kind == "private" and recipient.is_empty():
		game._toast("Choose a player from Online to whisper to.")
		return
	var request_id: int = game.online.session.request("chat_send", {"channel": kind, "message": text, "target": recipient})
	if request_id < 0: return
	pending_chat = {"id": request_id, "draft": field.text, "quick": quick}
	last_send = Time.get_ticks_msec()
	field.clear()
	if kind == "private": reply_to = recipient
	if quick: blur_quick()
	elif kind == "local": close()

func response(message: Dictionary) -> void:
	if str(message.get("op", "")) == "online_players" and not bool(message.get("ok", true)):
		roster_pending = false
		roster_status.text = str(message.get("error", "Could not refresh online players."))
	if str(message.get("op", "")) != "chat_send" or int(message.get("id", -1)) != int(pending_chat.get("id", -2)): return
	if not bool(message.get("ok", true)):
		var field: LineEdit = quick_entry if bool(pending_chat.quick) else entry
		if field.text.is_empty(): field.text = str(pending_chat.draft)
	pending_chat.clear()
