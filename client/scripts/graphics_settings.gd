extends RefCounted
var game: Node
var panel: Control
var choice: OptionButton
var note: Label
var previews: Array[Control] = []
var pose_choice: OptionButton
var return_to_login: bool = false
const POSES: Array[String] = ["idle","frames","attack","cast","sit_chair","sit_floor","ranged_attack"]

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(960, 640))
	var card: Control = panel.get_child(0)
	game._wood_card(card)
	game._label(card, "Character graphics", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(876, 16), Vector2(54, 48), close)
	choice = OptionButton.new(); choice.position = Vector2(30, 80); choice.size = Vector2(900, 54)
	choice.add_item("Classic"); choice.add_item("Enhanced")
	choice.add_theme_font_size_override("font_size", 22); card.add_child(choice)
	for index: int in range(2):
		var gender: int = 1-index
		game._label(card,"Male · Peasant Suit" if gender == 1 else "Female · Peasant Clothes",Vector2(130+index*450,145),20,game.GOLD)
		var preview: Control = preload("res://scripts/character_preview.gd").new()
		preview.game = game; preview.position = Vector2(60+index*450,170); preview.size = Vector2(390,270); preview.fit_to_rect = true; preview.zoom = 3.5; preview.bottom_margin = 8; preview.animate = true
		preview.appearance = {"gender":gender,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[4,0,0,0,16 if gender == 1 else 14,0,0,0,0]}
		card.add_child(preview); previews.append(preview)
	game._label(card,"Animation",Vector2(30,461),20)
	pose_choice = OptionButton.new(); pose_choice.position = Vector2(162,448); pose_choice.size = Vector2(300,54); pose_choice.add_theme_font_size_override("font_size",20); card.add_child(pose_choice)
	for label: String in ["Idle","Walk","Melee","Cast","Sit on chair","Sit on floor","Reach"]: pose_choice.add_item(label)
	pose_choice.item_selected.connect(func(index: int) -> void:
		for preview: Control in previews: preview.pose = POSES[index]; preview.animation_phase = 0; preview.queue_redraw()
	)
	game._button(card,"Turn both",Vector2(492,448),Vector2(438,54),func() -> void:
		for preview: Control in previews: preview.turn(1)
	)
	note = game._label(card, "", Vector2(30, 516), 18, game.MUTED)
	note.size = Vector2(900, 48); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice.item_selected.connect(func(index: int) -> void:
		if not game.art_profile.select_mode("classic" if index == 0 else "enhanced"):
			game._toast("Your graphics choice could not be saved.")
		game.textures.clear(); game.head_images.clear(); redraw_previews(game)
		game.queue_redraw(); refresh()
	)
	game._button(card, "Done", Vector2(30, 578), Vector2(900, 48), close, true)
	panel.hide()

func redraw_previews(node: Node) -> void:
	if node.get_script() == preload("res://scripts/character_preview.gd"):
		node.art_cache.clear(); node.queue_redraw()
	for child: Node in node.get_children(): redraw_previews(child)

func refresh() -> void:
	choice.set_item_disabled(1, not game.art_profile.ready())
	choice.select(1 if game.art_profile.mode == "enhanced" and game.art_profile.ready() else 0)
	if not game.art_profile.ready(): note.text = "Classic artwork is active. Enhanced character art is being prepared."
	elif game.art_profile.mode == "classic": note.text = "Classic is active. Choose Enhanced to compare these painted starter outfits."
	elif not game.art_profile.appearance(game.online.player).is_empty(): note.text = "Your current outfit uses Enhanced. Switch back to Classic at any time."
	else: note.text = "Pilot: default skin/hair, Peasant Suit/Clothes + Brown Boots, unarmed. Other looks use Classic."

func open() -> void:
	game._cancel_controls(); game.menu.hide()
	return_to_login = game.online.panel.visible and not game.online.active
	if return_to_login: game.online.panel.hide()
	refresh(); panel.get_parent().move_child(panel,-1); panel.show()

func disconnected() -> void:
	choice.get_popup().hide(); pose_choice.get_popup().hide(); panel.hide()

func close() -> void:
	disconnected()
	if return_to_login: game.online.panel.show()
	else: game.menu.show()
	return_to_login = false
