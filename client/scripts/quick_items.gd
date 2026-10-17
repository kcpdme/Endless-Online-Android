extends RefCounted
## Two persistent consumable shortcuts. Tap to use, hold to assign; native counts only.
var game: Node
var panel: Control
var choices: ItemList
var buttons: Array[Button] = []
var slots: Array[int] = [0, 0]
var selected_slot: int = 0
var identity: String = ""
var held_slot: int = -1
var held_pointer: int = -99
var held_at: int = 0
var held_opened: bool = false
var last_rows: String = ""

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	for index: int in range(2):
		var slot: int = index
		var button: Button = Button.new()
		button.position = Vector2(-324, -254 + index * 92)
		button.size = Vector2(76, 76)
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 46)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBoxFlat = game._style(Color(0.04, 0.10, 0.13, 0.48), Color(0.8, 0.86, 0.9, 0.65), 38)
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 8
			style.content_margin_bottom = 14
			button.add_theme_stylebox_override(state, style)
		parent.add_child(button)
		button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
		var count: Label = game._label(button, "", Vector2(4, 51), 16, game.TEXT)
		count.name = "Quantity"
		count.size = Vector2(62, 22)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 5)
		buttons.append(button)
	panel = game._modal(parent, Vector2(660, 520))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "QUICK ITEMS", Vector2(28, 22), 26, game.GOLD)
	game._label(card, "Tap to use · Hold a shortcut to change it", Vector2(28, 63), 18, game.MUTED)
	game._button(card, "×", Vector2(576, 16), Vector2(54, 48), func() -> void: panel.hide())
	choices = ItemList.new()
	choices.position = Vector2(28, 106)
	choices.size = Vector2(604, 312)
	choices.fixed_icon_size = Vector2i(40, 40)
	choices.add_theme_font_size_override("font_size", 21)
	card.add_child(choices)
	game._button(card, "Clear slot", Vector2(28, 444), Vector2(220, 50), func() -> void: assign(0))
	game._button(card, "Assign", Vector2(276, 444), Vector2(356, 50), func() -> void:
		var selected: PackedInt32Array = choices.get_selected_items()
		if not selected.is_empty(): assign(int(choices.get_item_metadata(selected[0])))
	)
	panel.hide()

func contains(point: Vector2) -> int:
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		if button.visible and point.distance_to(button.get_global_rect().get_center()) <= 38.0: return index
	return -1

func begin(index: int, pointer: int) -> void:
	if held_slot >= 0: return
	held_slot = index
	held_pointer = pointer
	held_at = Time.get_ticks_msec()
	held_opened = false

func release(pointer: int) -> void:
	if held_slot < 0 or held_pointer != pointer: return
	var index: int = held_slot
	var used: bool = held_opened
	cancel_hold()
	if not used and game.started and game.online.active and not game._modal_open(): press(index)

func cancel_hold() -> void:
	held_slot = -1
	held_pointer = -99

func press(index: int) -> void:
	if slots[index] == 0:
		open(index)
		return
	if not game.online.mobile_action_ready(): return
	if game.online.bag_amount(slots[index]) <= 0:
		game._toast("Your bag has no more of this item. Hold to change the shortcut.")
		return
	game.online.bag_action("item:%d" % slots[index])

func open(index: int) -> void:
	selected_slot = index
	game._cancel_controls()
	panel.show()
	last_rows = ""
	refresh()

func assign(ident: int) -> void:
	slots[selected_slot] = ident
	var data: Dictionary = {}
	if FileAccess.file_exists("user://quick_items.json"):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://quick_items.json"))
		if raw is Dictionary: data = raw
	data[identity] = slots
	var file: FileAccess = FileAccess.open("user://quick_items.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data))
	panel.hide()
	refresh()

func refresh() -> void:
	var active: bool = game.online_mode and game.online.active
	if not active:
		panel.hide()
		cancel_hold()
	var current: String = "%s:%d" % [game.online.host_field.text, int(game.online.player.get("character_id", -1))] if active else ""
	if current != identity:
		identity = current
		slots.assign([0, 0])
		var has_saved: bool = false
		if FileAccess.file_exists("user://quick_items.json"):
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://quick_items.json"))
			if saved is Dictionary:
				var loaded: Array = saved.get(identity, []) as Array
				if loaded.size() == 2:
					has_saved = true
					for index: int in range(2): slots[index] = int(loaded[index])
		if active and not has_saved:
			for item: Dictionary in game.online.inventory_items():
				var ident: int = int(item.id)
				var info: Dictionary = game.online.item_info("item:%d" % ident)
				if int(info.get("type", -1)) != 3 or game.online.bag_amount(ident) <= 0: continue
				if slots[0] == 0 and int(info.get("hp", 0)) > 0: slots[0] = ident
				elif slots[1] == 0 and int(info.get("tp", 0)) > 0: slots[1] = ident
	if held_slot >= 0 and not held_opened and game._modal_open(): cancel_hold()
	if held_slot >= 0 and not held_opened and Time.get_ticks_msec() - held_at >= 500:
		held_opened = true
		open(held_slot)
	if held_slot >= 0 and (not active or not game.started): cancel_hold()
	for index: int in range(2):
		var button: Button = buttons[index]
		button.visible = active and game.started and not game._modal_open()
		var ident: int = slots[index]
		button.icon = game._item_texture("item:%d" % ident) if ident > 0 else null
		button.text = "+" if ident == 0 else ""
		button.tooltip_text = str(game.online.item_info("item:%d" % ident).get("name", "Assign consumable")) + " · Hold to assign"
		(button.get_node("Quantity") as Label).text = str(game.online.bag_amount(ident)) if ident > 0 else ""
		button.modulate = Color(1, 1, 1, 0.5) if ident > 0 and game.online.bag_amount(ident) <= 0 else Color.WHITE
	if not panel.visible: return
	var items: Array[Dictionary] = []
	for item: Dictionary in game.online.inventory_items():
		if game.online.consumable("item:%d" % int(item.id)) and game.online.bag_amount(int(item.id)) > 0: items.append(item)
	var stamp: String = JSON.stringify(items)
	if stamp == last_rows: return
	last_rows = stamp
	choices.clear()
	for item: Dictionary in items:
		var ident: int = int(item.id)
		var info: Dictionary = game.online.item_info("item:%d" % ident)
		var row: int = choices.add_item("%s  ×%d" % [str(info.get("name", "Item")), game.online.bag_amount(ident)], game._item_texture("item:%d" % ident))
		choices.set_item_metadata(row, ident)
		if ident == slots[selected_slot]: choices.select(row)
