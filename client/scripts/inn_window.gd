extends RefCounted
## Original innkeeper sleep flow: native quote first, then explicit purchase.
var game: Node
var panel: Control
var title: Label
var detail: Label
var sleep_button: Button
var state: Dictionary = {}
func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(700, 400))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	title = game._label(card, "Innkeeper", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(614, 18), Vector2(54, 48), close)
	detail = game._label(card, "", Vector2(30, 98), 22)
	detail.size = Vector2(640, 160)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sleep_button = game._button(card, "Sleep", Vector2(30, 292), Vector2(640, 64), func() -> void:
		if state.has("cost"): game.online.session.request("inn_sleep")
		else: game.online.session.request("inn_quote")
	, true)
	panel.hide()
func receive(data: Dictionary) -> void:
	if not data.has("inn"): return
	if not data.inn is Dictionary:
		state.clear()
		panel.hide()
		return
	state = (data.inn as Dictionary).duplicate()
	game._cancel_controls()
	game.quest_ui.panel.hide()
	game.shop_ui.close()
	game.services_ui.panel.hide()
	var npc: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(state.npc_id)), {}) as Dictionary
	title.text = str(npc.get("name", "Innkeeper"))
	detail.text = "Rest at the inn to fully recover HP and TP.\nThe innkeeper will take you to a bed after payment."
	sleep_button.text = "Sleep · Ask price"
	sleep_button.disabled = false
	if state.has("cost"):
		detail.text += "\n\nA night’s rest: %d Gold" % int(state.cost)
		sleep_button.text = "Sleep · %d Gold" % int(state.cost)
		sleep_button.disabled = game.online.bag_amount(1) < int(state.cost)
	panel.show()
func close() -> void:
	game.online.session.request("inn_close")
	state.clear()
	panel.hide()
