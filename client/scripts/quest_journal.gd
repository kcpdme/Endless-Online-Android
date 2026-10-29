extends RefCounted
## Native Quest_List progress/history, separate from NPC conversation choices.
var game: Node
var button: Control
var panel: Control
var title: Label
var status: Label
var body: VBoxContainer
var scroll: ScrollContainer
var tabs: Array[Button] = []
var refresh_button: Button
var current_page: String = "progress"
var state: Dictionary = {}
var busy: bool = false

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new(); button.kind = "quests"
	button.position = Vector2(-356,24); button.size = Vector2(68,68)
	button.pressed.connect(open); parent.add_child(button); button.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	panel = game._modal(parent,Vector2(950,620)); var card: Control = panel.get_child(0)
	game._wood_card(card,"quests")
	title = game._label(card,"Ongoing quests",Vector2(30,22),28,game.GOLD)
	game._button(card,"×",Vector2(866,14),Vector2(54,48),dismiss)
	for index: int in range(2):
		var page: String = "progress" if index==0 else "history"
		var tab: Button = game._button(card,"Ongoing" if index==0 else "Completed",Vector2(30+index*300,78),Vector2(284,52),func() -> void: request_page(page))
		tabs.append(tab)
	refresh_button = game._button(card,"Refresh",Vector2(650,78),Vector2(270,52),func() -> void: request_page(current_page))
	scroll = ScrollContainer.new(); scroll.position = Vector2(30,148); scroll.size = Vector2(890,376); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; card.add_child(scroll)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",14); scroll.add_child(body)
	status = game._label(card,"",Vector2(30,544),18,game.MUTED); status.size = Vector2(890,54); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.hide()

func open() -> void:
	if not game.online.active: game.online.show_login(); return
	game._cancel_controls(); game.chat_ui.close(); game.shop_ui.close()
	game.inventory.hide(); game.character_panel.hide(); game.stats_ui.dismiss()
	game.skills_ui.panel.hide(); game.skills_ui.target_panel.hide(); game.skills_ui.bard_panel.hide()
	game.services_ui.panel.hide(); game.party_ui.panel.hide(); game.menu.hide()
	if game.guild_ui.panel.visible: game.guild_ui.close()
	if game.quest_ui.panel.visible: game.quest_ui.close()
	if game.inn_ui.panel.visible: game.inn_ui.close()
	panel.show(); request_page("progress")

func request_page(page: String) -> void:
	if busy: return
	current_page = page
	if game.online.session.request("quest_list",{"page":page}) < 0:
		status.text = "Connection lost. Reconnect to view your quests."; return
	busy = true; title.text = "Ongoing quests" if page=="progress" else "Completed quests"
	status.text = "Loading your quests…"; refresh()

func response(message: Dictionary) -> void:
	if str(message.get("op","")) != "quest_list": return
	busy = false
	if not bool(message.get("ok",true)):
		status.text = str(message.get("error","Could not load quests. Tap Refresh to retry."))
		refresh()

func receive(data: Dictionary) -> void:
	if not data.has("quest_journal") or not data.quest_journal is Dictionary: return
	var incoming: Dictionary = data.quest_journal
	if str(incoming.get("page","")) != current_page: return
	state = incoming.duplicate(true); busy = false
	status.text = "%d %s" % [(state.get("entries",[]) as Array).size(),"ongoing quests" if current_page=="progress" else "completed quests"]
	refresh()

func label(parent: Node, text: String, font: int, color: Color) -> Label:
	var result: Label = Label.new(); result.text = text; result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; result.size_flags_horizontal = Control.SIZE_EXPAND_FILL; result.add_theme_font_size_override("font_size",font); result.add_theme_color_override("font_color",color); parent.add_child(result); return result

func icon(parent: Node, index: int) -> void:
	var source: Texture2D = game._graphic(2,68)
	if source == null: return
	var atlas: AtlasTexture = AtlasTexture.new(); atlas.atlas = source; atlas.region = Rect2(clampi(index,0,7)*15,0,15,15)
	var control: TextureRect = TextureRect.new(); control.texture = atlas; control.custom_minimum_size = Vector2(34,34); control.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; control.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; parent.add_child(control)

func refresh() -> void:
	for control: Button in tabs: control.disabled = busy
	refresh_button.disabled = busy
	for child: Node in body.get_children(): body.remove_child(child); child.queue_free()
	var entries: Array = state.get("entries",[]) as Array if str(state.get("page",""))==current_page else []
	if busy: label(body,"Loading your quests…",22,game.MUTED); return
	if entries.is_empty():
		label(body,"No ongoing quests. Talk to a quest NPC to begin." if current_page=="progress" else "You have not completed any quests yet.",22,game.TEXT); return
	for quest: Dictionary in entries:
		var card: PanelContainer = PanelContainer.new(); card.add_theme_stylebox_override("panel",game._wood_style(Color("503921"),Color("987749"),2)); body.add_child(card)
		var margin: MarginContainer = MarginContainer.new(); card.add_child(margin)
		for edge: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,14)
		var column: VBoxContainer = VBoxContainer.new(); column.add_theme_constant_override("separation",8); margin.add_child(column)
		var heading: HBoxContainer = HBoxContainer.new(); heading.add_theme_constant_override("separation",12); column.add_child(heading)
		icon(heading,0 if current_page=="progress" else 5); label(heading,str(quest.name),23,game.GOLD)
		if current_page=="history": label(column,"Completed",20,game.TEXT); continue
		var objective: HBoxContainer = HBoxContainer.new(); objective.add_theme_constant_override("separation",12); column.add_child(objective)
		icon(objective,int({3:2,5:1,8:3,10:4}.get(int(quest.get("icon",0)),1))); label(objective,str(quest.get("description","")),21,game.TEXT)
		var target: int = int(quest.get("target",0))
		if target > 0:
			label(column,"%d / %d" % [int(quest.get("progress",0)),target],20,game.TEXT)
			var meter: ProgressBar = ProgressBar.new(); meter.custom_minimum_size.y = 14; meter.max_value = target; meter.value = clampi(int(quest.get("progress",0)),0,target); meter.show_percentage = false; column.add_child(meter)
	# Native rows without a numeric target keep their objective, without an invented counter.
	scroll.scroll_vertical = 0

func dismiss() -> void:
	panel.hide()

func disconnected() -> void:
	busy = false; state.clear(); current_page = "progress"; panel.hide(); refresh()
