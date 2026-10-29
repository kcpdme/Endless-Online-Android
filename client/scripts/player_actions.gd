extends RefCounted
## Compact player context menu, anchored to the tap and kept inside the screen.
var game:Node
var panel:Control
var card:Control
var heading:Label
var buttons:Dictionary={}
var target:Dictionary={}
var map_id:int=0
var anchor_fraction:Vector2=Vector2(.5,.5)

func build(owner_game:Node,parent:Control)->void:
	game=owner_game
	panel=game._modal(parent,Vector2(244,236));card=panel.get_child(0)
	card.set_meta("dialog_layout",layout)
	heading=game._label(card,"Player",Vector2(16,9),18,game.GOLD)
	heading.size=Vector2(212,26);heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var actions:Array[String]=["Paperdoll","Trade","Party","Whisper"]
	for i:int in range(actions.size()):
		var action:String=actions[i]
		var button:Button=game._button(card,action,Vector2(8,36+i*48),Vector2(228,48),func()->void:choose(action))
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.add_theme_font_size_override("font_size",20)
		buttons[action]=button
	panel.gui_input.connect(_outside_input)
	panel.hide()

func layout()->void:
	var available:Vector2=panel.size
	card.scale=Vector2.ONE
	var at:Vector2=anchor_fraction*available+Vector2(12,8)
	card.position=Vector2(clampf(at.x,12,maxf(12,available.x-card.size.x-12)),clampf(at.y,12,maxf(12,available.y-card.size.y-12)))

func _outside_input(event:InputEvent)->void:
	var pressed:bool=(event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT)
	if pressed and not card.get_global_rect().has_point(event.position):
		close();panel.accept_event()

func open(peer:Dictionary,point:Vector2=Vector2(-1,-1))->void:
	if int(peer.get("player_id",0))==int(game.online.player.get("player_id",-1)):return
	game._cancel_controls();game.menu.hide()
	if point.x<0:
		point=game.get_global_transform_with_canvas()*(game.tile_position(Vector2i(int(peer.x),int(peer.y)))+Vector2(0,-30))
	anchor_fraction=point/game.get_viewport_rect().size
	target=peer.duplicate(true);map_id=int(game.online.player.get("map_id",game.world.get("id",0)))
	heading.text=str(peer.get("name","Player")).capitalize();panel.show();game._layout_dialogs()

func close()->void:
	panel.hide();target.clear()

func choose(action:String)->void:
	if not panel.visible or target.is_empty():return
	var peer:Dictionary={}
	for row:Dictionary in game.online.players:
		if int(row.get("player_id",0))==int(target.get("player_id",-1)) and str(row.get("name",""))==str(target.get("name","")):peer=row;break
	if peer.is_empty() or int(game.online.player.get("map_id",game.world.get("id",0)))!=map_id:
		close();game._toast("That player is no longer nearby.");return
	if not game.online.mobile_action_ready():game._toast("Wait for the current action to finish.");return
	if action!="Whisper" and (game.moving or not game.online.pending_inputs.is_empty()):
		game._toast("Wait for your step to finish, then choose again.");return
	var pid:int=int(peer.player_id);var name:String=str(peer.name)
	close()
	match action:
		"Paperdoll":game.online.session.request("inspect_player",{"player_id":pid})
		"Trade":game.online.session.request("trade_request",{"player_id":pid})
		"Party":game.party_ui.invite(pid)
		"Whisper":game.chat_ui.open(name)
