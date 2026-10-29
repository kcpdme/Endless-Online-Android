extends RefCounted
var game: Node
var panel: Control
var choice: OptionButton
var note: Label
var npc_choice: CheckButton
var npc_note: Label

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(740, 520))
	var card: Control = panel.get_child(0)
	game._wood_card(card)
	game._label(card, "Graphics", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(656, 16), Vector2(54, 48), close)
	choice = OptionButton.new(); choice.position = Vector2(30, 100); choice.size = Vector2(680, 58)
	choice.add_item("Characters: Classic"); choice.add_item("Characters: Enhanced")
	choice.add_theme_font_size_override("font_size", 22); card.add_child(choice)
	note = game._label(card, "", Vector2(30, 174), 18, game.MUTED)
	note.size = Vector2(680, 65); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_choice = CheckButton.new(); npc_choice.position = Vector2(30, 250); npc_choice.size = Vector2(680, 58)
	npc_choice.text = "Enhanced NPC samples"; npc_choice.add_theme_font_size_override("font_size", 22); card.add_child(npc_choice)
	npc_note = game._label(card, "", Vector2(30, 326), 18, game.MUTED)
	npc_note.size = Vector2(680, 85); npc_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_choice.toggled.connect(func(value: bool) -> void:
		if not game.npc_art.select(value): game._toast("Your NPC graphics choice could not be saved.")
		game.textures.clear(); game.queue_redraw(); refresh()
	)
	choice.item_selected.connect(func(index: int) -> void:
		if not game.art_profile.select_mode("classic" if index == 0 else "enhanced"):
			game._toast("Your graphics choice could not be saved.")
		game.textures.clear(); game.head_images.clear(); redraw_previews(game)
		game.queue_redraw(); refresh()
	)
	game._button(card, "Done", Vector2(30, 440), Vector2(680, 52), close, true)
	panel.hide()

func redraw_previews(node: Node) -> void:
	if node.get_script() == preload("res://scripts/character_preview.gd"):
		node.art_cache.clear(); node.queue_redraw()
	for child: Node in node.get_children(): redraw_previews(child)

func refresh() -> void:
	choice.set_item_disabled(1, not game.art_profile.ready())
	choice.select(1 if game.art_profile.mode == "enhanced" and game.art_profile.ready() else 0)
	note.text = "Switch back to Classic at any time. Characters without enhanced art use Classic." if game.art_profile.ready() else "Classic artwork is active. Enhanced character art is being prepared."
	npc_choice.disabled = not game.npc_art.ready()
	npc_choice.set_pressed_no_signal(game.npc_art.enabled and game.npc_art.ready())
	npc_note.text = "Piglet and Banshi use smoother artwork. Other NPCs keep their original look. Switch this off to compare with Classic." if game.npc_art.ready() else "Original NPC artwork is active. Enhanced samples are not installed."

func open() -> void:
	game._cancel_controls(); game.menu.hide(); refresh(); panel.show()

func disconnected() -> void:
	choice.get_popup().hide(); panel.hide()

func close() -> void:
	disconnected(); game.menu.show()
