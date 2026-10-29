extends RefCounted
## Classic paperdoll and two-sided, server-authoritative storage/trade dialogs.
var game: Node
var card: Control
var panel: Control
var title: Label
var balance: Label
var details: Label
var left: ItemList
var right: ItemList
var left_heading: Label
var right_heading: Label
var quantity: SpinBox
var primary: Button
var secondary: Button
var extra: Button
var doll: Control
var mode: String = ""
var state: Dictionary = {}
var left_rows: Array = []
var right_rows: Array = []
var inspected: Dictionary = {}
var book_button: Button
var party_button: Button

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(1000, 650))
	card = panel.get_child(0) as Control
	game._wood_card(card)
	title = game._label(card, "", Vector2(36, 20), 26, game.GOLD)
	game._button(card, "×", Vector2(916, 16), Vector2(54, 48), close)
	balance = game._label(card, "", Vector2(36, 70), 19, game.GOLD)
	left_heading = game._label(card, "Your bag", Vector2(36, 108), 20)
	right_heading = game._label(card, "", Vector2(520, 108), 20)
	left = _list(card, Vector2(36, 146))
	right = _list(card, Vector2(520, 146))
	left.item_selected.connect(func(_i: int) -> void: right.deselect_all(); _selected())
	right.item_selected.connect(func(_i: int) -> void: left.deselect_all(); _selected())
	doll = preload("res://scripts/classic_paperdoll.gd").new()
	doll.game = game
	doll.position = Vector2(36, 98)
	doll.scale = Vector2(1.4, 1.4)
	doll.equipment_selected.connect(_inspect_item)
	doll.close_requested.connect(close)
	card.add_child(doll)
	details = game._label(card, "", Vector2(36, 474), 18, game.TEXT)
	details.size = Vector2(916, 66)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quantity = SpinBox.new()
	quantity.position = Vector2(36, 560)
	quantity.size = Vector2(172, 54)
	quantity.min_value = 1
	quantity.max_value = 2000000000
	quantity.add_theme_font_size_override("font_size", 22)
	card.add_child(quantity)
	primary = game._button(card, "", Vector2(228, 560), Vector2(226, 54), _primary, true)
	secondary = game._button(card, "", Vector2(470, 560), Vector2(226, 54), _secondary)
	extra = game._button(card, "", Vector2(712, 560), Vector2(244, 54), _extra)
	party_button = game._button(card,"Invite to party",Vector2(608,490),Vector2(340,46),func() -> void: game.party_ui.invite(int(state.get("player_id",0))))
	party_button.hide()
	book_button = game._button(card,"Character book",Vector2(608,430),Vector2(340,46),func() -> void:
		var pid: int=int(state.get("player_id",0));panel.hide();game.feature_ui.open("book",{"player_id":pid})
	)
	book_button.hide()
	panel.hide()

func _list(card: Control, at: Vector2) -> ItemList:
	var result: ItemList = ItemList.new()
	result.position = at
	result.size = Vector2(440, 310)
	result.fixed_icon_size = Vector2i(36, 36)
	result.add_theme_font_size_override("font_size", 19)
	result.add_theme_constant_override("v_separation", 10)
	result.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.add_child(result)
	return result

func open(kind: String, data: Dictionary) -> void:
	if mode == "chest" and kind != "chest": close()
	mode = kind
	game._wood_card(card,kind if kind in ["trade","bank","chest"] else "shop")
	state = data.duplicate(true)
	game.inventory.hide()
	game.character_panel.hide()
	game.stats_ui.dismiss()
	game.shop_ui.close()
	game._cancel_controls()
	quantity.max_value = 2000000000
	quantity.value = 1
	left.deselect_all()
	right.deselect_all()
	panel.show()
	refresh()

func close() -> void:
	if mode == "chest": game.online.session.request("chest_close")
	if mode == "trade" and not game.online.trade.is_empty():
		game.online.session.request("trade_cancel")
	if mode == "invitation": game.online.session.request("trade_decline")
	panel.hide()
	mode = ""

func receive(data: Dictionary) -> void:
	if data.has("trade"):
		var current: Dictionary = data.trade as Dictionary if data.trade is Dictionary else {}
		if not current.is_empty():
			if mode != "trade" or not panel.visible: open("trade", current)
			else: state = current; refresh()
		elif mode == "trade": panel.hide(); mode = ""
	if data.has("trade_request") and data.trade_request is Dictionary and not (data.trade_request as Dictionary).is_empty() and game.online.trade.is_empty():
		open("invitation", data.trade_request as Dictionary)
	for kind: String in ["bank", "locker", "chest"]:
		if mode == kind and data.has(kind):
			if data[kind] is Dictionary: state = data[kind] as Dictionary; refresh()
			else: panel.hide(); mode = ""

func _fill(list: ItemList, rows: Array) -> void:
	var old_id: int = 0
	var selected: PackedInt32Array = list.get_selected_items()
	if not selected.is_empty(): old_id = int(list.get_item_metadata(selected[0]))
	list.clear()
	for raw: Variant in rows:
		var item: Dictionary = raw as Dictionary
		var info: Dictionary = game.online.item_info("item:%d" % int(item.id))
		list.add_item("%s  ×%d" % [str(info.get("name", "Item %d" % int(item.id))), int(item.amount)], game.online._catalog_texture(str(info.get("icon", ""))))
		list.set_item_metadata(list.item_count - 1, int(item.id))
		if int(item.id) == old_id: list.select(list.item_count - 1)

func refresh() -> void:
	if not panel.visible: return
	var compact: bool = mode in ["bank", "invitation"]
	card.offset_top = -180.0 if compact else -325.0
	card.offset_bottom = 180.0 if compact else 325.0
	card.offset_left = -500.0
	card.offset_right = 500.0
	for control: Control in [quantity, primary, secondary, extra]: control.position.y = 270.0 if compact else 560.0
	var storage: bool = mode in ["locker", "chest"]
	var trading: bool = mode == "trade"
	var inspect: bool = mode == "inspect"
	party_button.visible = inspect
	book_button.visible = inspect
	left.visible = storage or trading
	right.visible = storage or trading
	left_heading.visible = left.visible
	right_heading.visible = right.visible
	doll.visible = inspect
	details.position = Vector2(608, 130) if inspect else Vector2(36, 132 if compact else 474)
	details.size = Vector2(340, 290) if inspect else Vector2(916, 115 if compact else 66)
	quantity.visible = mode in ["bank", "locker", "chest", "trade"]
	primary.visible = true
	secondary.visible = mode != "inspect"
	extra.visible = inspect or trading or mode == "bank"
	primary.disabled = not game.online.session.is_idle()
	secondary.disabled = primary.disabled
	extra.disabled = primary.disabled
	balance.text = "Bag Gold: %d" % game.coins
	if mode == "bank":
		title.text = "BANK"
		balance.text = "Bag Gold: %d     ·     Bank Gold: %d" % [game.coins, int(state.get("gold", 0))]
		details.text = "Deposit or withdraw Gold. Locker capacity: %d different items.\nTap a nearby locker to store items. Expansion costs %d Gold." % [int(state.get("capacity", 25)), int(state.get("upgrade_cost", 1000))]
		extra.text = "Expand locker" if bool(state.get("can_upgrade", false)) else "Fully expanded"
		extra.disabled = extra.disabled or not bool(state.get("can_upgrade", false))
		primary.text = "Deposit Gold"
		secondary.text = "Withdraw Gold"
	elif storage:
		title.text = "CHEST" if mode == "chest" else "ITEM LOCKER"
		left_heading.text = "Your bag"
		right_heading.text = "Chest contents" if mode == "chest" else "Your locker"
		left_rows = game.online.inventory_items().filter(func(i: Dictionary) -> bool: return (mode == "chest" or int(i.id) != 1) and int(i.amount) > 0)
		right_rows = state.get("items", []) as Array
		_fill(left, left_rows)
		_fill(right, right_rows)
		primary.text = "Deposit item"
		secondary.text = "Take stack" if mode == "chest" else "Withdraw stack"
		details.text = "Select a bag item and quantity to store it, or a locker stack to withdraw.\nThe original locker withdraws a whole stack, limited by what your bag can hold."
		if mode == "chest": details.text = "Select a chest stack to take it. To leave an item, select it in your bag and choose a quantity." if not right_rows.is_empty() else "This chest is empty. Select a bag item and quantity to put inside."
	elif trading:
		title.text = "TRADE  ·  " + str(state.get("name", "Player"))
		left_heading.text = "Your bag  ·  select to offer"
		right_heading.text = "Your offer / Their offer"
		left_rows = game.online.inventory_items()
		_fill(left, left_rows)
		right_rows = []
		right.clear()
		var offers: Dictionary = state.get("offers", {}) as Dictionary
		for pid: String in [str(int(game.online.player.get("player_id", 0))), str(int(state.get("player_id", 0)))]:
			for raw: Variant in offers.get(pid, []):
				var entry: Dictionary = (raw as Dictionary).duplicate()
				entry["owner"] = int(pid)
				right_rows.append(entry)
				var info: Dictionary = game.online.item_info("item:%d" % int(entry.id))
				right.add_item("%s: %s ×%d" % ["You" if int(pid) == int(game.online.player.get("player_id", 0)) else "Them", str(info.get("name", "Item")), int(entry.amount)], game.online._catalog_texture(str(info.get("icon", ""))))
		primary.text = "Add / set offer"
		secondary.text = "Remove offered"
		extra.text = "Unaccept" if bool(state.get("agreed", false)) else "Accept trade"
		details.text = "You: %s   ·   %s: %s\nReview both offers before accepting. Any offer change resets both approvals." % ["Accepted" if bool(state.get("agreed", false)) else "Reviewing", str(state.get("name", "Partner")), "Accepted" if bool(state.get("peer_agreed", false)) else "Reviewing"]
	elif inspect:
		title.text = str(state.get("name", "Player")).to_upper()
		balance.text = "EQUIPMENT INSPECTION"
		inspected = state
		doll.inspection = state
		doll.refresh("")
		var profession: Dictionary = (game.online.catalog.get("classes", {}) as Dictionary).get(str(int(state.get("class_id", 0))), {}) as Dictionary
		var labels: Array[String] = [str(state.get("name", "")), str(state.get("home", "")), str(profession.get("name", "")), str(state.get("partner", "")), str(state.get("title", "")), "–", str(state.get("guild", "")), str(state.get("rank", ""))]
		for i: int in range(labels.size()): doll.information_labels[i].text = labels[i]
		details.text = "Tap an equipment slot to see its item and bonuses."
		primary.text = "Request trade"
		extra.text = "Whisper"
	elif mode == "invitation":
		title.text = "TRADE INVITATION"
		balance.text = str(state.get("name", "Player")) + " wants to trade with you."
		details.text = "Accept to review each other's offers. No items move until both players agree."
		primary.text = "Accept invitation"
		secondary.text = "Decline"
	_selected()

func _selected() -> void:
	primary.disabled = not game.online.session.is_idle()
	secondary.disabled = primary.disabled
	extra.disabled = primary.disabled or (mode == "bank" and not bool(state.get("can_upgrade", false)))
	if mode in ["locker", "chest"]:
		primary.disabled = primary.disabled or left.get_selected_items().is_empty()
		secondary.disabled = secondary.disabled or right.get_selected_items().is_empty()
	elif mode == "trade":
		primary.disabled = primary.disabled or left.get_selected_items().is_empty()
		var selection: PackedInt32Array = right.get_selected_items()
		secondary.disabled = selection.is_empty() or not game.online.session.is_idle()
		if not selection.is_empty(): secondary.disabled = secondary.disabled or int(right_rows[selection[0]].owner) != int(game.online.player.get("player_id", 0))
	if not left.get_selected_items().is_empty():
		var item: Dictionary = left_rows[left.get_selected_items()[0]] as Dictionary
		quantity.max_value = maxi(1, mini(int(item.amount), 16194276) if mode == "chest" else int(item.amount))

func _request(op: String, fields: Dictionary = {}) -> void:
	if not game.online.session.is_idle(): return
	game.online.session.request(op, fields)
	primary.disabled = true
	secondary.disabled = true
	extra.disabled = true

func _primary() -> void:
	match mode:
		"bank": _request("bank_deposit", {"amount": int(quantity.value)})
		"locker", "chest", "trade":
			var selection: PackedInt32Array = left.get_selected_items()
			if selection.is_empty(): return
			_request("chest_deposit" if mode == "chest" else "locker_deposit" if mode == "locker" else "trade_add", {"item_id": int(left_rows[selection[0]].id), "amount": int(quantity.value)})
		"inspect":
			_request("trade_request", {"player_id": int(state.player_id)})
			panel.hide()
		"invitation": _request("trade_accept", {"player_id": int(state.player_id)})

func _secondary() -> void:
	if mode == "bank": _request("bank_withdraw", {"amount": int(quantity.value)})
	elif mode == "invitation": close()
	else:
		var selection: PackedInt32Array = right.get_selected_items()
		if selection.is_empty(): return
		_request("chest_take" if mode == "chest" else "locker_withdraw" if mode == "locker" else "trade_remove", {"item_id": int(right_rows[selection[0]].id)})

func _extra() -> void:
	if mode == "bank": _request("bank_upgrade")
	elif mode == "trade": _request("trade_agree", {"agree": not bool(state.get("agreed", false))})
	elif mode == "inspect":
		panel.hide()
		game.chat_ui.open(str(state.get("name", "")))

func _inspect_item(kind: String) -> void:
	var id: int = int((state.get("equipment", {}) as Dictionary).get(game.online._slot_name(kind), 0))
	if id > 0: game.stats_ui.show_item("item:%d" % id, panel, true)
