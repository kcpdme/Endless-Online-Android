extends RefCounted
## Original map signs and native haircutter purchases.
var game: Node
var barber_panel: Control
var sign_panel: Control
var style: OptionButton
var color: OptionButton
var preview: Control
var price: Label
var status: Label
var buy: Button
var confirm: ConfirmationDialog
var sign_title: Label
var sign_text: RichTextLabel
var sign_map: int = -1
var state: Dictionary = {}
var busy: bool = false

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	barber_panel = game._modal(parent,Vector2(900,620)); var card: Control = barber_panel.get_child(0); game._wood_card(card)
	game._label(card,"Haircutter",Vector2(30,22),30,game.GOLD)
	game._button(card,"×",Vector2(816,16),Vector2(54,48),close_barber)
	game._label(card,"Hair style",Vector2(30,105),21)
	style = choice(card,Vector2(30,142),true)
	game._label(card,"Hair color",Vector2(30,242),21)
	color = choice(card,Vector2(30,279),false)
	price = game._label(card,"",Vector2(30,374),22,game.GOLD);price.size=Vector2(430,64);price.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview = preload("res://scripts/character_preview.gd").new();preview.game=game;preview.position=Vector2(480,88);preview.size=Vector2(360,350);preview.zoom=3.5;preview.fit_to_rect=true;card.add_child(preview)
	game._label(card,"Tap preview to turn",Vector2(550,452),18,game.MUTED)
	status = game._label(card,"Choose a new look, then confirm the price.",Vector2(30,492),18,game.TEXT);status.size=Vector2(840,40);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	buy = game._button(card,"Buy haircut",Vector2(30,548),Vector2(840,52),func() -> void:
		if busy or state.is_empty():return
		confirm.dialog_text="Apply this hairstyle and color for %d Gold?" % int(state.price);confirm.popup_centered(Vector2i(560,220))
	,true)
	confirm=ConfirmationDialog.new();confirm.title="Buy haircut";confirm.dialog_autowrap=true;confirm.confirmed.connect(purchase);barber_panel.add_child(confirm);barber_panel.hide()
	sign_panel=game._modal(parent,Vector2(760,460));card=sign_panel.get_child(0);game._wood_card(card)
	sign_title=game._label(card,"Road sign",Vector2(30,25),28,game.GOLD);sign_title.size=Vector2(620,75);sign_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game._button(card,"×",Vector2(676,16),Vector2(54,48),func() -> void:sign_panel.hide())
	sign_text=RichTextLabel.new();sign_text.position=Vector2(30,112);sign_text.size=Vector2(700,250);sign_text.add_theme_font_size_override("normal_font_size",24);sign_text.bbcode_enabled=false;card.add_child(sign_text)
	game._button(card,"OK",Vector2(30,382),Vector2(700,52),func() -> void:sign_panel.hide(),true);sign_panel.hide()

func choice(card: Control, at: Vector2, hair: bool) -> OptionButton:
	var option: OptionButton=OptionButton.new();option.position=at+Vector2(64,0);option.size=Vector2(294,58);option.add_theme_font_size_override("font_size",22);card.add_child(option)
	for i: int in range(21 if hair else 10):option.add_item(("Bald" if i==0 else "Style %d" % i) if hair else "Color %d" % (i+1),i)
	game._button(card,"‹",at,Vector2(56,58),func() -> void:option.select(posmod(option.selected-1,option.item_count));update_preview())
	game._button(card,"›",at+Vector2(366,0),Vector2(56,58),func() -> void:option.select(posmod(option.selected+1,option.item_count));update_preview())
	option.item_selected.connect(func(_i: int) -> void:update_preview());return option

func update_preview() -> void:
	var appearance: Dictionary=game.online.player.duplicate(true)
	appearance.hairstyle=style.get_selected_id();appearance.haircolor=color.get_selected_id()
	# Preview the hair with the hat removed; purchasing never changes equipment.
	var equipment: Array=(appearance.get("equipment_graphics",[0,0,0,0,0,0,0,0,0]) as Array).duplicate()
	if equipment.size()==9:equipment[6]=0
	appearance.equipment_graphics=equipment;preview.appearance=appearance;preview.queue_redraw()
	var same: bool=int(game.online.player.get("hairstyle",1))==int(appearance.hairstyle) and int(game.online.player.get("haircolor",0))==int(appearance.haircolor)
	buy.disabled=busy or state.is_empty() or same or game.online.bag_amount(1)<int(state.get("price",0))

func purchase() -> void:
	if busy or state.is_empty():return
	busy=game.online.session.request("barber_buy",{"style":style.get_selected_id(),"color":color.get_selected_id()})>=0
	status.text="Applying your haircut…" if busy else "Connection lost. Reconnect before buying."
	update_preview()

func receive(data: Dictionary) -> void:
	if sign_panel.visible and int(game.world.get("id",-1))!=sign_map:sign_panel.hide()
	if not data.has("barber"):return
	if not data.barber is Dictionary:state.clear();barber_panel.hide();confirm.hide();busy=false;return
	var opening: bool=state.is_empty() or state.get("npc_index")!=data.barber.get("npc_index") or state.get("map_id")!=data.barber.get("map_id")
	state=(data.barber as Dictionary).duplicate(true)
	if opening:
		game._cancel_controls();game.inventory.hide();game.character_panel.hide();game.skills_ui.panel.hide();game.guild_ui.panel.hide();game.services_ui.panel.hide();game.quest_journal.dismiss();sign_panel.hide()
		style.select(clampi(int(game.online.player.get("hairstyle",1)),0,20));color.select(clampi(int(game.online.player.get("haircolor",0)),0,9))
		for i: int in range(style.item_count):style.set_item_disabled(i,i>int(state.max_style))
		for i: int in range(color.item_count):color.set_item_disabled(i,i>int(state.max_color))
		status.text="Choose a new look, then confirm the price.";barber_panel.show()
	price.text="Haircut: %d Gold\nYou have: %d Gold" % [int(state.price),game.online.bag_amount(1)];update_preview()

func response(message: Dictionary) -> void:
	if str(message.get("op","")) not in ["barber_open","barber_buy","barber_close"]:return
	busy=false
	if not bool(message.get("ok",true)):status.text=str(message.get("error","Haircutter unavailable"))
	elif message.op=="barber_buy":status.text="Your new haircut is ready."
	if buy!=null:update_preview()

func open_sign(sign: Dictionary) -> void:
	game._cancel_controls();var length: int=int(sign.get("title_length",0))
	# Title length indexes original text, before control-character filtering.
	var source: String=str(sign.get("text",""));sign_title.text=clean(source.substr(0,length)) if length>0 else "Road sign";sign_text.text=clean(source.substr(length))
	sign_map=int(game.world.get("id",-1));sign_panel.show()
	if game.sfx!=null:game.sfx.play_named("ChestOpen","sign")

func clean(value: String) -> String:
	var result: String=""
	for i: int in range(value.length()):
		if value.unicode_at(i)>=32 and value.unicode_at(i)!=127:result+=value[i]
	return result

func close_barber() -> void:
	confirm.hide();barber_panel.hide();state.clear();busy=false
	if game.online.active:game.online.session.request("barber_close")

func disconnected() -> void:
	state.clear();busy=false;barber_panel.hide();sign_panel.hide();confirm.hide()
