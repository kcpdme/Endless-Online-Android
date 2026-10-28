extends RefCounted
const PET_DETAILS = preload("res://scripts/pet_details.gd")
## Original native shop data, with independent catalog and selected-item detail panes.
var game: Node
var panel: Control
var title: Label
var balance: Label
var description: Label
var item_title: Label
var item_icon: TextureRect
var list: ItemList
var quantity: SpinBox
var action: Button
var total: Label
var status: Label
var count_label: Label
var details_scroll: ScrollContainer
var details_body: VBoxContainer
var ingredient_rows: Array[Control] = []
var tabs: Array[Button] = []
var shop: Dictionary = {}
var mode: String = "buy"
var offers: Array[Dictionary] = []
var list_signature: String = ""
var details_signature: String = ""
var built_mode: String = ""
var selection_by_mode: Dictionary = {}

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(1120, 660))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	title = game._label(card, "Shop", Vector2(28, 20), 28, game.GOLD)
	title.size = Vector2(720, 40)
	title.clip_text = true
	balance = game._label(card, "", Vector2(792, 28), 20, game.GOLD)
	balance.size = Vector2(220, 30)
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	game._button(card, "×", Vector2(1038, 14), Vector2(54, 48), close)
	for index: int in range(3):
		var operation: String = ["buy", "sell", "craft"][index]
		var tab: Button = game._button(card, operation.capitalize(), Vector2(28 + index * 168, 78), Vector2(160, 50), func() -> void:
			mode = operation
			refresh()
		)
		tabs.append(tab)
	game._label(card, "SELECTED ITEM", Vector2(558, 92), 15, game.GOLD)
	for rectangle: Rect2 in [Rect2(28, 142, 496, 410), Rect2(548, 142, 544, 410)]:
		var inset: Panel = game._panel(card, rectangle.position, rectangle.size, Color(0.12, 0.075, 0.035, 0.40))
		inset.add_theme_stylebox_override("panel", game._style(Color(0.12, 0.075, 0.035, 0.40), Color("b28a51"), 8))
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list = ItemList.new()
	list.position = Vector2(38, 150)
	list.size = Vector2(476, 392)
	list.fixed_icon_size = Vector2i(40, 40)
	list.add_theme_font_size_override("font_size", 21)
	list.add_theme_constant_override("v_separation", 16)
	list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	list.item_selected.connect(func(_index: int) -> void: _selected())
	card.add_child(list)
	item_icon = TextureRect.new()
	item_icon.position = Vector2(566, 158)
	item_icon.size = Vector2(72, 60)
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(item_icon)
	item_title = game._label(card, "", Vector2(650, 158), 23, game.TEXT)
	item_title.size = Vector2(300, 58)
	item_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(card, "View", Vector2(968, 162), Vector2(100, 46), func() -> void:
		var selected: PackedInt32Array = list.get_selected_items()
		if not selected.is_empty(): game.stats_ui.show_item("item:%d" % int(offers[selected[0]].id))
	)
	details_scroll = ScrollContainer.new()
	details_scroll.position = Vector2(566, 222)
	details_scroll.size = Vector2(510, 316)
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.scroll_deadzone = 8
	card.add_child(details_scroll)
	details_body = VBoxContainer.new()
	details_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_body.add_theme_constant_override("separation", 9)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 30)
	details_scroll.add_child(margin)
	margin.add_child(details_body)
	count_label = game._label(card, "", Vector2(32, 628), 15, game.MUTED)
	game._label(card, "Quantity", Vector2(32, 581), 20)
	quantity = SpinBox.new()
	quantity.position = Vector2(146, 568)
	quantity.size = Vector2(164, 54)
	quantity.min_value = 1
	quantity.max_value = 1
	quantity.add_theme_font_size_override("font_size", 22)
	quantity.value_changed.connect(func(_value: float) -> void: _selected(false))
	card.add_child(quantity)
	total = game._label(card, "", Vector2(558, 580), 22, game.GOLD)
	total.size = Vector2(254, 34)
	action = game._button(card, "Buy ×1", Vector2(824, 568), Vector2(268, 54), transact, true)
	status = game._label(card, "", Vector2(330, 628), 15, game.TEXT)
	status.size = Vector2(760, 20)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.hide()

func close() -> void:
	if panel.visible:
		game.modal_input_until = Time.get_ticks_msec() + 180
		game.online.interaction.clear()
		game.get_viewport().set_input_as_handled()
	panel.hide()

func confirm_transaction(event: Dictionary) -> void:
	var operation: String = str(event.get("operation", ""))
	var item: String = "%s ×%d" % [item_name(int(event.get("item_id", 0))), int(event.get("amount", 0))]
	if operation == "buy": game._toast("Purchased %s\nTucked safely into your bag." % item)
	elif operation == "craft": game._toast("Crafted %s\nYour new item is in your bag." % item)
	elif operation == "sell": game._toast("Sold %s\nThe Gold is in your bag." % item)

func open(data: Dictionary) -> void:
	shop = data
	mode = "buy"
	list_signature = ""
	details_signature = ""
	built_mode = ""
	selection_by_mode.clear()
	game.inventory.hide()
	game.character_panel.hide()
	game.stats_ui.dismiss()
	game._cancel_controls()
	panel.show()
	refresh()

func held(id: int) -> int:
	for item: Dictionary in game.online.inventory_items():
		if int(item.id) == id: return int(item.amount)
	return 0

func item_name(id: int) -> String:
	return str(game.online.item_info("item:%d" % id).get("name", "Item %d" % id))

func display_name(id: int) -> String:
	var info: Dictionary = game.online.item_info("item:%d" % id)
	if info.has("pet_tier"):
		return "%s · %s" % [str(info.tier_name), item_name(id).replace(" Spirit Egg", " Egg")]
	if int(info.get("type", -1)) == 12:
		return item_name(id) + (" (M)" if int(info.get("gender", 1)) == 1 else " (F)")
	return item_name(id)

func refresh() -> void:
	if not panel.visible: return
	title.text = str(shop.get("name", "Shop"))
	balance.text = "Gold: %d" % game.coins
	for index: int in range(tabs.size()): tabs[index].modulate = Color("ffe0a0") if mode == ["buy", "sell", "craft"][index] else Color.WHITE
	var selected: PackedInt32Array = list.get_selected_items()
	if not selected.is_empty() and selected[0] < offers.size(): selection_by_mode[built_mode] = int(offers[selected[0]].id)
	var next_offers: Array[Dictionary] = []
	for raw: Variant in shop.get("craft" if mode == "craft" else "trade", []):
		var offer: Dictionary = raw as Dictionary
		if mode != "craft" and (int(offer.get(mode, 0)) <= 0 or (mode == "sell" and held(int(offer.id)) <= 0)): continue
		next_offers.append(offer)
	var signature: String = JSON.stringify([mode, next_offers])
	if signature != list_signature:
		var scroll: float = list.get_v_scroll_bar().value if built_mode == mode else 0.0
		var old_id: int = int(selection_by_mode.get(mode, -1))
		var old_mode: String = built_mode
		list_signature = signature
		built_mode = mode
		list.clear()
		offers = next_offers
		for offer: Dictionary in offers:
			var id: int = int(offer.id)
			var info: Dictionary = game.online.item_info("item:%d" % id)
			var caption: String = display_name(id) if mode == "craft" else "%s  ·  %d" % [display_name(id), int(offer.get(mode, 0))]
			var row: int = list.add_item(caption, game.online._catalog_texture(str(info.get("icon", ""))))
			if info.has("tier_color"): list.set_item_custom_fg_color(row, Color(str(info.tier_color)))
			list.set_item_tooltip(row, item_name(id))
		if not offers.is_empty():
			var index: int = 0
			for i: int in range(offers.size()):
				if int(offers[i].id) == old_id: index = i
			list.select(index)
		list.get_v_scroll_bar().set_deferred("value", scroll)
		if old_mode != mode:
			quantity.value = 1
			details_signature = ""
			details_scroll.scroll_vertical = 0
	var noun: String = "recipe" if mode == "craft" else "item"
	count_label.text = "%d %s" % [offers.size(), noun + ("" if offers.size() == 1 else "s")]
	_selected(false)

func material_totals(offer: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in offer.get("ingredients", []):
		var ingredient: Dictionary = raw as Dictionary
		var id: int = int(ingredient.id)
		result[id] = int(result.get(id, 0)) + int(ingredient.amount)
	return result

func _detail_label(text: String, size: int = 19, color: Color = Color("f1e3c8")) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_body.add_child(label)
	return label

func _render_details(offer: Dictionary, id: int, reset: bool) -> void:
	var previous_scroll: int = details_scroll.scroll_vertical if not reset else 0
	for child: Node in details_body.get_children():
		details_body.remove_child(child)
		child.queue_free()
	ingredient_rows.clear()
	var info: Dictionary = game.online.item_info("item:%d" % id)
	item_title.text = display_name(id)
	item_icon.texture = game.online._catalog_texture(str(info.get("icon", "")))
	if mode == "craft":
		_detail_label("Materials", 21, game.GOLD)
		var columns: Label = _detail_label("Have / Need", 15, game.MUTED)
		columns.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var totals: Dictionary = material_totals(offer)
		for material_id: int in totals:
			var row: HBoxContainer = HBoxContainer.new()
			row.custom_minimum_size.y = 42
			row.add_theme_constant_override("separation", 10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			details_body.add_child(row)
			ingredient_rows.append(row)
			var icon: TextureRect = TextureRect.new()
			var material: Dictionary = game.online.item_info("item:%d" % material_id)
			icon.texture = game.online._catalog_texture(str(material.get("icon", "")))
			icon.custom_minimum_size = Vector2(32, 36)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
			var name: Label = Label.new()
			name.text = item_name(material_id)
			name.add_theme_font_size_override("font_size", 19)
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(name)
			var amounts: Label = Label.new()
			amounts.text = "%d / %d" % [held(material_id), int(totals[material_id])]
			amounts.custom_minimum_size.x = 148
			amounts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amounts.add_theme_font_size_override("font_size", 19)
			amounts.add_theme_color_override("font_color", Color("b9dd8b") if held(material_id) >= int(totals[material_id]) else Color("ffb1a0"))
			amounts.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(amounts)
	_detail_label("In bag: %d" % held(id), 18, game.MUTED)
	var parts: Array[String] = []
	if int(info.get("hatch_spell", 0)) > 0:
		item_icon.texture = PET_DETAILS.texture(game, info)
		description = _detail_label(PET_DETAILS.description(game, info))
		details_scroll.set_deferred("scroll_vertical", previous_scroll)
		return
	if int(info.get("max_damage", 0)) > 0: parts.append("Damage %d–%d" % [int(info.get("min_damage", 0)), int(info.get("max_damage", 0))])
	for key: String in ["armor", "accuracy", "evade", "hp", "tp", "strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
		var value: int = int(info.get(key, 0))
		if value != 0: parts.append("%s %s%d" % [key.to_upper() if key in ["hp", "tp"] else key.capitalize(), "+" if value > 0 else "", value])
	var combat_text: String = preload("res://scripts/combat_details.gd").describe(info)
	if not combat_text.is_empty(): parts.append(combat_text)
	parts.append("Weight %d" % int(info.get("weight", 0)))
	if int(info.get("level_requirement", 0)) > 0: parts.append("Requires level %d" % int(info.level_requirement))
	var professions: String = game.online.equipment_classes(info)
	if not professions.is_empty(): parts.append("Class: %s" % professions)
	if info.get("crafted", false): parts.append("Crafted definition · improved combat budget")
	for attribute: String in ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
		if int(info.get(attribute + "_requirement", 0)) > 0: parts.append("Requires %s %d" % [attribute, int(info[attribute + "_requirement"])])
	description = _detail_label("\n".join(parts))
	details_scroll.set_deferred("scroll_vertical", previous_scroll)

func _selected(reset: bool = true) -> void:
	var selection: PackedInt32Array = list.get_selected_items()
	if selection.is_empty() or selection[0] >= offers.size():
		item_title.text = "Nothing to sell" if mode == "sell" else "No recipes" if mode == "craft" else "No items for sale"
		item_icon.texture = null
		if details_signature != "empty:" + mode:
			for child: Node in details_body.get_children():
				details_body.remove_child(child)
				child.queue_free()
			ingredient_rows.clear()
			description = _detail_label("This shop has no available items in this section.")
			details_signature = "empty:" + mode
		action.disabled = true
		action.text = mode.capitalize()
		total.text = ""
		status.text = ""
		quantity.editable = false
		return
	var offer: Dictionary = offers[selection[0]]
	var id: int = int(offer.id)
	selection_by_mode[mode] = id
	quantity.max_value = maxi(1, int(offer.get("max_buy", 1))) if mode == "buy" else (maxi(1, held(id)) if mode == "sell" else 1)
	quantity.editable = mode != "craft"
	if reset: quantity.value = 1
	var cost: int = int(offer.get(mode, 0)) * int(quantity.value)
	var materials: Dictionary = material_totals(offer) if mode == "craft" else {}
	var owned: Dictionary = {id: held(id)}
	var missing: int = 0
	for material_id: int in materials:
		owned[material_id] = held(material_id)
		if held(material_id) < int(materials[material_id]): missing += 1
	var signature: String = JSON.stringify([mode, id, owned, offer])
	if signature != details_signature or reset:
		details_signature = signature
		_render_details(offer, id, reset)
	total.text = "" if mode == "craft" else "Total: %d" % cost
	action.text = "%s ×%d" % [mode.capitalize(), int(quantity.value)]
	status.text = ("All materials ready" if missing == 0 else "Missing %d %s" % [missing, "material" if missing == 1 else "materials"]) if mode == "craft" else "Not enough Gold" if mode == "buy" and cost > held(1) else ""
	status.add_theme_color_override("font_color", Color("ffb1a0") if missing > 0 or (mode == "buy" and cost > held(1)) else Color("b9dd8b"))
	action.disabled = not game.online._action_ready() or missing > 0 or (mode == "buy" and cost > held(1))
	var info: Dictionary = game.online.item_info("item:%d" % id)
	if mode == "buy" and int(info.get("hatch_spell", 0)) > 0 and int(game.online.player.get("stats", {}).get("class_id", 0)) != 7:
		action.disabled = true
		status.text = "Only Summoners can buy bound spirit eggs."
		status.add_theme_color_override("font_color", Color("ffb1a0"))

func transact() -> void:
	var selection: PackedInt32Array = list.get_selected_items()
	if selection.is_empty() or action.disabled or not game.online._action_ready(): return
	var offer: Dictionary = offers[selection[0]]
	game.online.session.request("shop_" + mode, {"item_id": int(offer.id), "amount": int(quantity.value)})
	action.disabled = true
