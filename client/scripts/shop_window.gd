extends RefCounted
## Original shop trade/craft catalogue, with touch-sized controls.
var game: Node
var panel: Control
var title: Label
var balance: Label
var description: Label
var list: ItemList
var quantity: SpinBox
var action: Button
var shop: Dictionary = {}
var mode: String = "buy"
var offers: Array[Dictionary] = []

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(900, 650))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	if ResourceLoader.exists("res://content/ui/classic_52.png"):
		var art: TextureRect = TextureRect.new()
		art.texture = load("res://content/ui/classic_52.png") as Texture2D
		art.size = Vector2(900, 650)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
	title = game._label(card, "Shop", Vector2(38, 20), 25, game.GOLD)
	game._button(card, "×", Vector2(810, 14), Vector2(54, 48), close)
	for index: int in range(3):
		var operation: String = ["buy", "sell", "craft"][index]
		game._button(card, operation.capitalize(), Vector2(40 + index * 178, 78), Vector2(162, 50), func() -> void:
			mode = operation
			refresh()
		)
	balance = game._label(card, "", Vector2(598, 90), 19, game.GOLD)
	list = ItemList.new()
	list.position = Vector2(42, 147)
	list.size = Vector2(812, 296)
	list.fixed_icon_size = Vector2i(42, 42)
	list.add_theme_font_size_override("font_size", 22)
	list.add_theme_constant_override("v_separation", 12)
	list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	list.item_selected.connect(func(_index: int) -> void: _selected())
	card.add_child(list)
	description = game._label(card, "", Vector2(42, 460), 18)
	description.size = Vector2(804, 90)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(card, "Quantity", Vector2(44, 574), 20)
	quantity = SpinBox.new()
	quantity.position = Vector2(164, 560)
	quantity.size = Vector2(170, 54)
	quantity.min_value = 1
	quantity.max_value = 1
	quantity.add_theme_font_size_override("font_size", 22)
	quantity.value_changed.connect(func(_value: float) -> void: _selected(false))
	card.add_child(quantity)
	action = game._button(card, "Buy", Vector2(356, 560), Vector2(496, 54), transact, true)
	panel.hide()

func close() -> void:
	panel.hide()

func open(data: Dictionary) -> void:
	shop = data
	mode = "buy"
	game.inventory.hide()
	game.character_panel.hide()
	game.stats_ui.hide()
	game._cancel_controls()
	panel.show()
	refresh()

func held(id: int) -> int:
	for item: Dictionary in game.online.inventory_items():
		if int(item.id) == id: return int(item.amount)
	return 0

func item_name(id: int) -> String:
	return str(game.online.item_info("item:%d" % id).get("name", "Item %d" % id))

func refresh() -> void:
	if not panel.visible: return
	title.text = str(shop.get("name", "Shop"))
	balance.text = "Gold: %d" % game.coins
	var old_id: int = -1
	var selected: PackedInt32Array = list.get_selected_items()
	if not selected.is_empty() and selected[0] < offers.size(): old_id = int(offers[selected[0]].id)
	list.clear()
	offers.clear()
	var rows: Array = shop.get("craft" if mode == "craft" else "trade", []) as Array
	for raw: Variant in rows:
		var offer: Dictionary = raw as Dictionary
		if mode != "craft" and (int(offer.get(mode, 0)) <= 0 or (mode == "sell" and held(int(offer.id)) <= 0)): continue
		offers.append(offer)
		var info: Dictionary = game.online.item_info("item:%d" % int(offer.id))
		var caption: String = "%s  —  %d gold each" % [item_name(int(offer.id)), int(offer.get(mode, 0))]
		if mode == "craft": caption = item_name(int(offer.id)) + "  —  recipe"
		if mode == "sell": caption += "  ·  Bag ×%d" % held(int(offer.id))
		list.add_item(caption, game.online._catalog_texture(str(info.get("icon", ""))))
	if not offers.is_empty():
		var index: int = 0
		for i: int in range(offers.size()):
			if int(offers[i].id) == old_id: index = i
		list.select(index)
	_selected()

func _selected(reset: bool = true) -> void:
	var selection: PackedInt32Array = list.get_selected_items()
	if selection.is_empty() or selection[0] >= offers.size():
		description.text = "No items available in this section."
		action.disabled = true
		return
	var offer: Dictionary = offers[selection[0]]
	var id: int = int(offer.id)
	quantity.max_value = maxi(1, int(offer.get("max_buy", 1))) if mode == "buy" else (maxi(1, held(id)) if mode == "sell" else 1)
	if reset: quantity.value = 1
	var parts: Array[String] = []
	if mode == "craft":
		for raw: Variant in offer.get("ingredients", []):
			var ingredient: Dictionary = raw as Dictionary
			parts.append("%s ×%d (bag %d)" % [item_name(int(ingredient.id)), int(ingredient.amount), held(int(ingredient.id))])
	else: parts.append("Bag: %d  ·  Total: %d gold" % [held(id), int(offer.get(mode, 0)) * int(quantity.value)])
	var info: Dictionary = game.online.item_info("item:%d" % id)
	parts.append("Damage %d–%d  ·  Armor %d  ·  Weight %d" % [int(info.get("min_damage", 0)), int(info.get("max_damage", 0)), int(info.get("armor", 0)), int(info.get("weight", 0))])
	description.text = "\n".join(parts)
	action.text = "%s %s ×%d" % [mode.capitalize(), item_name(id), int(quantity.value)]
	action.disabled = not game.online._action_ready()

func transact() -> void:
	var selection: PackedInt32Array = list.get_selected_items()
	if selection.is_empty() or not game.online._action_ready(): return
	var offer: Dictionary = offers[selection[0]]
	game.online.session.request("shop_" + mode, {"item_id": int(offer.id), "amount": int(quantity.value)})
	action.disabled = true
