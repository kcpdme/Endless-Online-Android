extends RefCounted
var game: Node
var panel: Control
var choice: OptionButton
var note: Label
var npc_choice: CheckButton
var npc_note: Label
var player_choice:CheckButton
var card:Control
var done:Button

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(740, 520))
	card = panel.get_child(0)
	game._wood_card(card)
	game._label(card, "Graphics", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(656, 16), Vector2(54, 48), close)
	choice = OptionButton.new(); choice.position = Vector2(30, 88); choice.size = Vector2(680, 58)
	choice.add_item("Illustrated style: Classic"); choice.add_item("Illustrated style: Enhanced")
	choice.add_theme_font_size_override("font_size", 22); card.add_child(choice)
	player_choice=CheckButton.new();player_choice.position=Vector2(30,100);player_choice.size=Vector2(680,58)
	player_choice.text="Enhanced players and items";player_choice.add_theme_font_size_override("font_size",22);card.add_child(player_choice)
	note = game._label(card, "", Vector2(30, 174), 18, game.MUTED)
	note.size = Vector2(680, 65); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_choice = CheckButton.new(); npc_choice.position = Vector2(30, 250); npc_choice.size = Vector2(680, 58)
	npc_choice.text = "Enhanced NPC artwork"; npc_choice.add_theme_font_size_override("font_size", 22); card.add_child(npc_choice)
	npc_note = game._label(card, "", Vector2(30, 326), 18, game.MUTED)
	npc_note.size = Vector2(680, 85); npc_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_choice.toggled.connect(func(value: bool) -> void:
		if not game.npc_art.select(value): game._toast("Your NPC graphics choice could not be saved.")
		game.textures.clear(); game.queue_redraw(); refresh()
	)
	player_choice.toggled.connect(func(value:bool)->void:
		if not game.player_item_art.select(value):game._toast("Your player graphics choice could not be saved.")
		game.textures.clear();game.head_images.clear();game.nameplates.frame_images.clear();game.nameplates.frame_bounds.clear()
		redraw_previews(game);game.queue_redraw();refresh()
	)
	choice.item_selected.connect(func(index: int) -> void:
		if not game.art_profile.select_mode("classic" if index == 0 else "enhanced"):
			game._toast("Your graphics choice could not be saved.")
		game.textures.clear(); game.head_images.clear(); redraw_previews(game)
		game.queue_redraw(); refresh()
	)
	done=game._button(card, "Done", Vector2(30, 440), Vector2(680, 52), close, true)
	panel.hide()

func redraw_previews(node: Node) -> void:
	if node.get_script() == preload("res://scripts/character_preview.gd"):
		node.art_cache.clear(); node.queue_redraw()
	for child: Node in node.get_children(): redraw_previews(child)

func refresh() -> void:
	choice.set_item_disabled(1, not game.art_profile.ready())
	choice.select(1 if game.art_profile.mode == "enhanced" and game.art_profile.ready() else 0)
	choice.visible=game.art_profile.ready()
	# Keep all three choices inside the same phone-sized card when an optional
	# illustrated pack is installed; its presence must not enlarge the dialog.
	player_choice.position.y=156.0 if choice.visible else 100.0
	note.position.y=228.0 if choice.visible else 174.0
	note.size.y=52.0 if choice.visible else 65.0
	npc_choice.position.y=294.0 if choice.visible else 250.0
	npc_note.position.y=366.0 if choice.visible else 326.0
	npc_note.size.y=65.0 if choice.visible else 85.0
	player_choice.disabled=not game.player_item_art.ready()
	player_choice.set_pressed_no_signal(game.player_item_art.enabled and game.player_item_art.ready())
	note.text="Smooth player bodies, hair, clothes, armour, equipment and items. Switch off to return to Classic." if game.player_item_art.ready() else "Original player and item artwork is active. Enhanced artwork is not installed."
	npc_choice.disabled = not game.npc_art.ready()
	npc_choice.set_pressed_no_signal(game.npc_art.enabled and game.npc_art.ready())
	npc_note.text = "NPCs and pets use smoother artwork. Switch this off at any time to return to Classic." if game.npc_art.ready() else "Original NPC artwork is active. Enhanced NPC artwork is not installed."

func open() -> void:
	game._cancel_controls(); game.menu.hide(); refresh(); panel.show()

func disconnected() -> void:
	choice.get_popup().hide(); panel.hide()

func close() -> void:
	disconnected(); game.menu.show()
