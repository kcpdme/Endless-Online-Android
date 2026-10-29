extends RefCounted
## Native summon state and permanent collection; UI never grants a pet or resets a timer.
const DETAILS = preload("res://scripts/pet_details.gd")
var game: Node
var button: Button
var caption: Label
var collection_button: Button
var panel: Control
var list: ItemList
var notice: Label
var preview: TextureRect
var description: RichTextLabel
var bind_button: Button
var chosen: int = 0
var stamp: String = ""
var pending: int = -1
var hatched_by_spell: Dictionary = {}
var catalog_version: int = -1
var described: int = -1

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new();button.set("kind", "pet")
	button.position = Vector2(-262, -100) + game.COMBAT_HUD_SHIFT;button.size = Vector2(76, 76)
	parent.add_child(button);button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true);button.pressed.connect(press)
	caption = game._label(button, "Summon", Vector2(-4, 62), 13, game.GOLD)
	caption.size = Vector2(84, 22);caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_color", Color.WHITE);caption.add_theme_color_override("font_outline_color", Color.BLACK);caption.add_theme_constant_override("outline_size", 4)
	button.hide()
	collection_button=preload("res://scripts/hud_icon_button.gd").new();collection_button.set("kind","egg")
	collection_button.position=Vector2(-640,24);collection_button.size=Vector2(68,68);parent.add_child(collection_button)
	collection_button.set_anchors_preset(Control.PRESET_TOP_RIGHT,true);collection_button.pressed.connect(open);collection_button.tooltip_text="Hatched pet collection";collection_button.hide()
	panel=game._modal(parent,Vector2(1000,620));var card: Control=panel.get_child(0);game._wood_card(card)
	game._label(card,"HATCHED PET COLLECTION",Vector2(30,20),26,game.GOLD)
	game._button(card,"×",Vector2(916,16),Vector2(54,48),func() -> void: panel.hide())
	notice=game._label(card,"",Vector2(30,68),18,game.MUTED);notice.size=Vector2(934,54);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	list=ItemList.new();list.position=Vector2(30,132);list.size=Vector2(392,398);list.fixed_icon_size=Vector2i(52,52);list.add_theme_font_size_override("font_size",20);card.add_child(list)
	list.item_selected.connect(func(index: int) -> void: chosen=int(list.get_item_metadata(index));refresh_details())
	preview=TextureRect.new();preview.position=Vector2(590,124);preview.size=Vector2(210,180);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.add_child(preview)
	description=RichTextLabel.new();description.position=Vector2(456,316);description.size=Vector2(508,208);description.add_theme_font_size_override("normal_font_size",18);card.add_child(description)
	bind_button=game._button(card,"Bind selected pet",Vector2(456,544),Vector2(508,48),bind_selected,true)
	game._label(card,"Permanent unlocks · one bound pet at a time",Vector2(30,552),16,game.MUTED)
	panel.hide()
	game.online.session.message_received.connect(func(message: Dictionary) -> void:
		if pending<0 or int(message.get("id",-1))!=pending:return
		pending=-1;stamp=""
		if not message.get("ok",false):game._toast(str(message.get("error","Pet selection failed")))
	)

func owned() -> Array[Dictionary]:
	var version: int=int(game.online.catalog.get("balance_version",0))
	if version!=catalog_version:
		catalog_version=version;hatched_by_spell.clear()
		for item: Dictionary in (game.online.catalog.get("items",{}) as Dictionary).values():
			if item.get("egg_state","")=="hatched":hatched_by_spell[int(item.hatch_spell)]=item
	var result: Array[Dictionary]=[]
	for row: Dictionary in game.online.player.get("spells",[]):
		if hatched_by_spell.has(int(row.id)):result.append(hatched_by_spell[int(row.id)])
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.get("level_requirement",0))<int(b.get("level_requirement",0)) if a.get("level_requirement",0)!=b.get("level_requirement",0) else int(a.id)<int(b.id))
	return result

func bond() -> int:
	var selected: int=int(game.online.pet_state.get("selected_spell",0))
	for row: Dictionary in game.online.player.get("spells",[]):
		if int(row.id)==selected and selected>0:return selected
	for row: Dictionary in game.online.player.get("spells",[]):
		var spell: Dictionary=game.skills_ui.info(int(row.id))
		if spell.get("effect_kind","")=="companion" and int((spell.get("companion",{}) as Dictionary).get("npc_id",0))>0:return int(row.id)
	return 0

func cooldown() -> int:
	return maxi(0,ceili((game.online.pet_ready_at-Time.get_ticks_msec())/1000.0))

func timer_text() -> String:
	var seconds: int=cooldown();return "%d:%02d" % [seconds/60,seconds%60]

func tick() -> void:
	var summoner: bool=game.online_mode and game.online.active and game.started and not game.welcome.visible and int((game.online.player.get("stats",{}) as Dictionary).get("class_id",0))==7
	button.visible=summoner and not game._modal_open();collection_button.visible=button.visible
	if not summoner:panel.hide()
	var called: bool=not game.online.companion.is_empty()
	caption.text="Dismiss" if called else timer_text() if cooldown()>0 else "Summon"
	button.tooltip_text="Dismiss pet · starts five-minute recovery" if called else "Pet recovery: "+timer_text() if cooldown()>0 else "Call your bound pet" if bond()>0 else "Hatch an Egg from Inventory first"
	button.modulate=Color("b4efff") if called else Color.WHITE
	button.disabled=game.online.defeated or not game.skills_ui.casting.is_empty() or Time.get_ticks_msec()<game.skills_ui.ready_at or (not called and cooldown()>0)
	if panel.visible:refresh()

func contains(point: Vector2) -> bool:
	return (button.visible and button.contains_point(point)) or (collection_button.visible and collection_button.contains_point(point))

func press(point: Vector2=Vector2.INF) -> void:
	if collection_button.visible and collection_button.contains_point(point):open();return
	if not button.visible or button.disabled:return
	var ident: int=35 if not game.online.companion.is_empty() else bond()
	if ident==0:
		game._toggle_inventory();game._toast("Use an Egg to hatch a permanent pet, then choose it from the top egg icon.");return
	game.skills_ui.cast(ident,"self",0)

func open() -> void:
	if not collection_button.visible:return
	game._cancel_controls();game.menu.hide();panel.show();stamp="";refresh()

func refresh() -> void:
	var pets: Array[Dictionary]=owned();var next_stamp: String=str(pets.map(func(i: Dictionary) -> int: return int(i.id)))+":"+str(bond())
	if next_stamp!=stamp:
		stamp=next_stamp;list.clear()
		for item: Dictionary in pets:
			var title: String=str(item.name)+( " · Bound" if int(item.hatch_spell)==bond() else "")
			list.add_item(title,game._texture(str(item.icon)));list.set_item_metadata(list.item_count-1,int(item.id))
		if chosen==0 or not pets.any(func(i: Dictionary) -> bool: return int(i.id)==chosen):chosen=int(pets[0].id) if not pets.is_empty() else 0
		for index: int in range(list.item_count):
			if int(list.get_item_metadata(index))==chosen:list.select(index)
	notice.text="Shared recovery: "+timer_text()+". Binding and summoning unlock together." if cooldown()>0 else "Dismiss the current pet before switching. Its five-minute recovery applies to the whole collection." if not game.online.companion.is_empty() else "Choose a hatched pet to bind. Hatching another species adds to this permanent collection."
	refresh_details()

func refresh_details() -> void:
	var item: Dictionary=(game.online.catalog.get("items",{}) as Dictionary).get(str(chosen),{}) as Dictionary
	if described!=chosen:
		described=chosen
		preview.texture=DETAILS.texture(game,item) if not item.is_empty() else null
		description.text=DETAILS.description(game,item) if not item.is_empty() else "No pets hatched yet.\nBuy or earn an Egg, then hatch it from Inventory.\nHatched Eggs cannot be sold or traded."
	var is_bound: bool=int(item.get("hatch_spell",0))==bond()
	bind_button.text="Already bound" if is_bound else "Bind selected pet"
	bind_button.disabled=item.is_empty() or is_bound or pending>=0 or cooldown()>0 or not game.online.companion.is_empty() or game.online.defeated

func bind_selected() -> void:
	if bind_button.disabled or chosen==0:return
	pending=game.online.session.request("item_use",{"item_id":chosen})
