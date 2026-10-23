extends RefCounted
## Original native quest pages/links, with readable mobile scrolling.
var game: Node
var panel: Control
var title: Label
var selector: OptionButton
var body: VBoxContainer
var scroll: ScrollContainer
var previous: Button
var next: Button
var page_label: Label
var state: Dictionary = {}
var page: int = 0

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(850, 610))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	title = game._label(card, "", Vector2(30, 22), 28, game.GOLD)
	game._button(card, "×", Vector2(766, 16), Vector2(54, 48), close)
	selector = OptionButton.new()
	selector.position = Vector2(30, 72)
	selector.size = Vector2(730, 42)
	selector.add_theme_font_size_override("font_size", 18)
	selector.item_selected.connect(func(index: int) -> void:
		game.online.session.request("quest_open", {"npc_index":int(state.npc_index),"quest_id":selector.get_item_id(index)})
		panel.hide()
	)
	card.add_child(selector)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(30, 130)
	scroll.size = Vector2(790, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	previous = game._button(card, "Previous", Vector2(30, 526), Vector2(190, 52), func() -> void: page -= 1; refresh())
	page_label = game._label(card, "", Vector2(240, 540), 17, game.MUTED)
	next = game._button(card, "", Vector2(610, 526), Vector2(210, 52), func() -> void:
		if page + 1 < (state.get("pages", []) as Array).size(): page += 1; refresh()
		else: reply()
	, true)
	panel.hide()

func receive(data: Dictionary) -> void:
	if not data.has("quest_dialog"): return
	if not data.quest_dialog is Dictionary:
		state.clear()
		panel.hide()
		return
	state = (data.quest_dialog as Dictionary).duplicate(true)
	page = 0
	game._cancel_controls()
	game.quest_journal.dismiss()
	game.shop_ui.close()
	game.services_ui.panel.hide()
	game.inventory.hide()
	game.character_panel.hide()
	game.stats_ui.dismiss()
	game.skills_ui.panel.hide()
	refresh()
	panel.show()

func refresh() -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var info: Dictionary = (game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(state.get("npc_id", 0))), {}) as Dictionary
	title.text = str(info.get("name", "Conversation"))
	selector.clear()
	for quest: Dictionary in state.get("quests", []):
		selector.add_item(str(quest.name), int(quest.id))
		if int(quest.id) == int(state.quest_id): selector.select(selector.item_count - 1)
	selector.disabled = selector.item_count <= 1
	var pages: Array = state.get("pages", []) as Array
	page = clampi(page, 0, maxi(0, pages.size() - 1))
	var text: Label = Label.new()
	text.text = str(pages[page]) if not pages.is_empty() else ""
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 22)
	text.add_theme_color_override("font_color", game.TEXT)
	body.add_child(text)
	if page + 1 >= pages.size():
		for link: Dictionary in state.get("links", []):
			var action: int = int(link.id)
			var button: Button = Button.new()
			button.text = str(link.text)
			button.custom_minimum_size = Vector2(0, 54)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 20)
			button.add_theme_stylebox_override("normal", game._wood_style(Color("654525"), Color("ad854c"), 2))
			button.pressed.connect(func() -> void: reply(action))
			body.add_child(button)
	previous.disabled = page == 0
	next.text = "Next" if page + 1 < pages.size() else "OK"
	page_label.text = "%d / %d" % [page + 1, maxi(1, pages.size())]
	scroll.scroll_vertical = 0

func reply(action: int = 0) -> void:
	if state.is_empty(): return
	var fields: Dictionary = {} if action == 0 else {"action":action}
	game.online.session.request("quest_reply", fields)
	panel.hide()

func close() -> void:
	if not state.is_empty() and game.online.active: game.online.session.request("quest_close")
	state.clear()
	panel.hide()
