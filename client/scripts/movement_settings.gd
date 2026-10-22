extends RefCounted
var game: Node
var panel: Control
var mapping: OptionButton
var base: OptionButton
func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(740, 500))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "Movement controls", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(656, 16), Vector2(54, 48), close)
	game._label(card, "Direction mapping", Vector2(30, 90), 20)
	mapping = OptionButton.new(); mapping.position = Vector2(30, 124); mapping.size = Vector2(680, 54)
	mapping.add_item("Classic · joystick follows the original tile keys")
	mapping.add_item("Isometric · drag along the visible diagonal direction")
	mapping.add_theme_font_size_override("font_size", 20); card.add_child(mapping)
	game._label(card, "Joystick base", Vector2(30, 200), 20)
	base = OptionButton.new(); base.position = Vector2(30, 234); base.size = Vector2(680, 54)
	base.add_item("Floating · starts where you touch and follows long drags")
	base.add_item("Fixed · press around the resting circle to move")
	base.add_theme_font_size_override("font_size", 20); card.add_child(base)
	var explanation: Label = game._label(card, "Touch turns respond sooner; keyboard timing stays classic.\nBoth modes use the same four tile directions and walking speed.\nYour choices are saved on this device.", Vector2(30, 316), 19, game.MUTED)
	explanation.size = Vector2(680, 90); explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mapping.item_selected.connect(func(_index: int) -> void: save())
	base.item_selected.connect(func(_index: int) -> void: save())
	game._button(card, "Done", Vector2(30, 422), Vector2(680, 52), close, true)
	panel.hide()
func open() -> void:
	game._cancel_controls(); game.menu.hide()
	mapping.select(1 if game.joystick.isometric else 0); base.select(1 if game.joystick.fixed_base else 0)
	panel.show()
func save() -> void:
	game._cancel_controls()
	game.joystick.set_preferences(mapping.selected == 1, base.selected == 1)
func disconnected() -> void:
	mapping.get_popup().hide(); base.get_popup().hide()
	panel.hide()
func close() -> void:
	disconnected(); game.menu.show()
