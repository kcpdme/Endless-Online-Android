extends RefCounted
var game: Node
var button: Control
var panel: Control
var tabs: TabContainer
var teleport_list: VBoxContainer
var item_id: LineEdit
var npc_id: LineEdit
var item_button: Button
var spawn_button: Button
var notice: Label
var busy: bool = false
var capabilities: Dictionary = {}

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new()
	button.kind = "admin"; button.position = Vector2(-716,24); button.size = Vector2(68,68)
	parent.add_child(button); button.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	button.pressed.connect(open); button.hide()
	panel = game._modal(parent,Vector2(860,620))
	var card: Control = panel.get_child(0)
	game._wood_card(card)
	game._label(card,"ADMIN",Vector2(30,20),28,game.GOLD)
	game._button(card,"×",Vector2(778,16),Vector2(54,48),close)
	tabs = TabContainer.new(); tabs.position = Vector2(30,86); tabs.size = Vector2(800,416)
	tabs.add_theme_font_size_override("font_size",22); card.add_child(tabs)
	var teleport: Control = Control.new(); teleport.name = "Teleport"; tabs.add_child(teleport)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(12,12); scroll.size = Vector2(768,350); teleport.add_child(scroll)
	teleport_list = VBoxContainer.new(); teleport_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teleport_list.add_theme_constant_override("separation",8); scroll.add_child(teleport_list)
	var items: Control = Control.new(); items.name = "Item"; tabs.add_child(items)
	game._label(items,"Receive one item in your bag",Vector2(24,24),24)
	item_id = id_field(items,"Item ID")
	item_button = game._button(items,"Get item",Vector2(24,152),Vector2(744,60),func() -> void: submit("item",item_id))
	item_id.text_submitted.connect(func(_text: String) -> void: submit("item",item_id))
	var spawn: Control = Control.new(); spawn.name = "Spawn"; tabs.add_child(spawn)
	game._label(spawn,"Spawn one NPC at your location",Vector2(24,24),24)
	npc_id = id_field(spawn,"NPC ID")
	spawn_button = game._button(spawn,"Spawn NPC",Vector2(24,152),Vector2(744,60),func() -> void: submit("spawn",npc_id))
	npc_id.text_submitted.connect(func(_text: String) -> void: submit("spawn",npc_id))
	notice = game._label(card,"",Vector2(30,526),20,game.MUTED)
	notice.size = Vector2(800,76); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.hide()

func id_field(parent: Control, hint: String) -> LineEdit:
	var field: LineEdit = LineEdit.new()
	field.position = Vector2(24,82); field.size = Vector2(744,56); field.placeholder_text = hint
	field.max_length = 5; field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.add_theme_font_size_override("font_size",24); parent.add_child(field)
	return field

func allowed() -> bool:
	return game.started and game.online_mode and game.online.active and int((game.online.player.get("stats",{}) as Dictionary).get("admin",0)) > 0

func tick() -> void:
	if not allowed(): disconnected(); return
	button.visible = not game._modal_open()

func open() -> void:
	if busy or not allowed(): return
	game._cancel_controls(); game.skills_ui.armed = 0
	game.menu.hide(); game.chat_ui.panel.hide(); game.services_ui.panel.hide()
	panel.show(); tabs.current_tab = 0; capabilities.clear()
	busy = true; notice.text = "Loading admin functions…"; refresh()
	if game.online.session.request("admin_open") < 0:
		busy = false; notice.text = "Unable to connect to the server."; refresh()

func close() -> void:
	item_id.release_focus(); npc_id.release_focus(); panel.hide()

func refresh() -> void:
	for entry: Node in teleport_list.get_children(): entry.disabled = busy or not bool(capabilities.get("teleport",false))
	item_button.disabled = busy or not bool(capabilities.get("item",false))
	spawn_button.disabled = busy or not bool(capabilities.get("spawn",false))
	item_id.editable = not busy; npc_id.editable = not busy
	button.disabled = busy

func send(operation: String, fields: Dictionary) -> void:
	if busy or not allowed(): return
	busy = true; notice.text = "Waiting for the server…"; refresh()
	item_id.release_focus(); npc_id.release_focus()
	if game.online.session.request(operation,fields) < 0:
		busy = false; notice.text = "Unable to send this action."; refresh()

func submit(kind: String, field: LineEdit) -> void:
	if busy or not bool(capabilities.get(kind,false)): return
	var value: String = field.text.strip_edges()
	if value.is_empty() or not value.is_valid_int() or int(value) <= 0:
		notice.text = "Enter a positive numeric ID."; return
	send("admin_"+kind,{"item_id" if kind == "item" else "npc_id":int(value)})

func response(message: Dictionary) -> void:
	var operation: String = str(message.get("op",""))
	if not operation.begins_with("admin_"): return
	busy = false
	if not bool(message.get("ok",false)):
		notice.text = str(message.get("error","Admin action failed.")); refresh(); return
	var data: Dictionary = message.get("data",{}) as Dictionary
	if operation == "admin_open":
		capabilities = data.get("capabilities",{}) as Dictionary
		for child: Node in teleport_list.get_children(): teleport_list.remove_child(child); child.queue_free()
		for destination: Dictionary in data.get("destinations",[]):
			var entry: Button = Button.new(); entry.text = str(destination.name); entry.custom_minimum_size = Vector2(0,58)
			entry.add_theme_font_size_override("font_size",22); teleport_list.add_child(entry)
			entry.pressed.connect(func() -> void: send("admin_teleport",{"destination":str(destination.key)}))
		notice.text = "Choose a destination, get an item, or spawn an NPC. Functions require your server admin rank."
	else:
		notice.text = str(data.get("admin_notice","Action confirmed."))
		if operation == "admin_teleport": close(); game._toast(notice.text)
	refresh()

func disconnected() -> void:
	button.hide(); close(); busy = false; button.disabled = false; capabilities.clear(); item_id.clear(); npc_id.clear()
