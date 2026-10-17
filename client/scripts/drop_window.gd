extends RefCounted
## Original Item_Drop amount chooser; inventory changes only on native acknowledgement.
var game: Node
var panel: Control
var heading: Label
var quantity: SpinBox
var submit: Button
var item_id: int = 0
var submitting: bool = false
var operation: String = "drop"

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(600, 300))
	panel.z_index = 20
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	heading = game._label(card, "Drop item", Vector2(28, 24), 25, game.GOLD)
	heading.size = Vector2(540, 70)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(card, "Quantity", Vector2(28, 124), 21)
	quantity = SpinBox.new()
	quantity.position = Vector2(230, 108)
	quantity.size = Vector2(330, 56)
	quantity.min_value = 1
	quantity.step = 1
	quantity.rounded = true
	quantity.add_theme_font_size_override("font_size", 22)
	card.add_child(quantity)
	game._button(card, "Cancel", Vector2(28, 214), Vector2(252, 56), func() -> void: panel.hide())
	submit = game._button(card, "Drop", Vector2(310, 214), Vector2(252, 56), confirm, true)
	panel.hide()

func open(kind: String, action: String = "drop") -> void:
	operation = action if action in ["drop", "junk"] else "drop"
	if not game.online_mode or not game.online._action_ready(): return
	item_id = game.online.item_id(kind)
	var amount: int = game.online.bag_amount(item_id)
	if amount <= 0: return
	if operation == "drop" and int(game.online.item_info(kind).get("special", 0)) == 4:
		game._toast("This item cannot be dropped.")
		return
	submitting = false
	game._cancel_controls()
	heading.text = ("Permanently junk %s?" if operation == "junk" else "Drop %s on the ground") % str(game.online.item_info(kind).get("name", "item"))
	submit.text = "Junk" if operation == "junk" else "Drop"
	quantity.max_value = mini(amount, 16194276)
	quantity.value = 1
	submit.disabled = false
	panel.show()

func refresh() -> void:
	if not panel.visible: return
	var amount: int = game.online.bag_amount(item_id)
	if amount <= 0:
		panel.hide()
		return
	quantity.max_value = mini(amount, 16194276)
	submit.disabled = submitting or not game.online._action_ready()

func confirm() -> void:
	if submitting or not game.online._action_ready(): return
	submitting = true
	submit.disabled = true
	game.online.session.request("item_" + operation, {"item_id": item_id, "amount": int(quantity.value)})
