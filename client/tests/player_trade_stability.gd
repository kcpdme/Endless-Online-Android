extends SceneTree
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields.duplicate(true)});return calls.size()
var game:Node
var wire:Wire
var checks:int=0
var failed:bool=false
var folder:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func shot(name:String)->void:
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func hide_dialogs()->void:
	for card:Control in game.modal_cards:card.get_parent().hide()
	game.services_ui.mode="";game.modal_input_until=0
func run()->void:
	folder=OS.get_environment("ASTER_VALE_STABILITY_OUTPUT")
	if not folder.is_empty():DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1544,720)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop()
	game.online.session.queue_free();wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	hide_dialogs();game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true
	game.online.player={"player_id":100,"character_id":1,"name":"Fixture","map_id":5,"x":40,"y":40,"gender":1,"race":0,"hairstyle":7,"haircolor":4,"equipment_graphics":[1,0,0,0,1,0,0,0,4],"hp":500,"max_hp":500,"tp":100,"max_tp":100,"spells":[],"inventory":[],"equipment":{"weapon":21},"stats":{"admin":0,"class_id":6,"level":50,"stat_points":0}}
	var peer:Dictionary={"player_id":200,"name":"Nearby","x":41,"y":40,"gender":0,"level":25}
	game.online.players.assign([peer]);game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	game._process(0);wire.calls.clear()
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame;game._layout_safe_area()
		game.online.map_click(Vector2i(41,40),"player");game._process(0)
		check(game.player_actions.panel.visible and game._modal_open() and wire.calls.is_empty(),"Player tap opens choices before sending any social action")
		check(game.player_actions.buttons.keys()==["Paperdoll","Trade","Party","Whisper"],"Exactly the requested four choices")
		check(game.player_actions.card.size==Vector2(244,236),"Player dropdown stays compact")
		for i:int in range(4):
			var row:Button=game.player_actions.buttons.values()[i]
			check(row.position==Vector2(8,36+i*48) and row.size==Vector2(228,48),"Four readable full-width touch rows")
		check(game.get_viewport_rect().encloses(game.player_actions.card.get_global_rect()),"Player menu fits "+str(dimensions))
		for button:Button in game.player_actions.buttons.values():check(game.player_actions.card.get_global_rect().encloses(button.get_global_rect()),"Large player action stays inside its frame")
		var menu_rect:Rect2=game.player_actions.card.get_global_rect()
		var menu_events:Array[int]=[0]
		var menu_changed:Callable=func()->void:menu_events[0]+=1
		game.player_actions.buttons.Paperdoll.theme_changed.connect(menu_changed)
		for update:int in range(60):
			game.online.player.tp=100-update;game._refresh_ui();game._process(0);await process_frame
			check(game.player_actions.card.get_global_rect().is_equal_approx(menu_rect),"Player choices stay fixed through live stat refreshes")
		check(menu_events[0]==0,"Player choices do not repeatedly replace their skin")
		game.player_actions.buttons.Paperdoll.theme_changed.disconnect(menu_changed)
		game._handle_back();check(not game.player_actions.panel.visible,"Android Back closes player choices")
		for corner:Vector2 in [Vector2(1,1),Vector2(dimensions)-Vector2.ONE]:
			game.player_actions.open(peer,corner)
			check(game.get_viewport_rect().encloses(game.player_actions.card.get_global_rect()),"Dropdown clamps to screen edges")
		game.player_actions.open(peer,Vector2(30,30))
		var away:InputEventScreenTouch=InputEventScreenTouch.new();away.pressed=true;away.position=Vector2(dimensions)-Vector2(3,3)
		game.player_actions._outside_input(away);check(not game.player_actions.panel.visible and wire.calls.is_empty(),"Outside tap dismisses without sending or walking")
	game.online.map_click(Vector2i(41,40),"player");await shot("player-menu")
	game.online.pending_inputs.assign([{"seq":1}]);game.player_actions.choose("Trade")
	check(game.player_actions.panel.visible and wire.calls.is_empty(),"An unconfirmed walking step cannot send a premature standing action")
	game.online.pending_inputs.clear()
	game.player_actions.buttons["Paperdoll"].pressed.emit();check(wire.calls.size()==1 and wire.calls[-1]=={"op":"inspect_player","fields":{"player_id":200}},"Paperdoll requests exact selected native player")
	game.player_actions.choose("Trade");check(wire.calls.size()==1,"A disappearing menu cannot send a duplicate choice")
	game.player_actions.open(peer);game.player_actions.choose("Trade");check(wire.calls[-1]=={"op":"trade_request","fields":{"player_id":200}},"Trade addresses selected native player")
	game.player_actions.open(peer);game.player_actions.choose("Party");check(wire.calls[-1].op=="party_invite" and wire.calls[-1].fields.player_id==200,"Party sends the selected invite")
	hide_dialogs();game.player_actions.open(peer);var before:int=wire.calls.size();game.player_actions.choose("Whisper")
	check(wire.calls.size()==before and game.chat_ui.panel.visible and game.chat_ui.target.text=="nearby" and game.chat_ui.channel.selected==2,"Whisper opens the selected private recipient without sending a message")
	hide_dialogs();game.player_actions.open(peer);game.online.players.clear();game.player_actions.choose("Trade");check(wire.calls.size()==before and not game.player_actions.panel.visible,"A departed player is never replaced by a stale menu target")
	game.online.players.assign([peer]);hide_dialogs()
	var inventory:Array=[{"id":1,"amount":1000}]
	for ident:int in range(21,43):inventory.append({"id":ident,"amount":5})
	game.online.player.inventory=inventory;game.online._sync_inventory()
	var trade:Dictionary={"player_id":200,"name":"Nearby","offers":{"100":[{"id":21,"amount":1}],"200":[{"id":21,"amount":2}]},"agreed":false,"peer_agreed":false}
	var ui:RefCounted=game.services_ui
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame;game._layout_safe_area();game.online.trade=trade.duplicate(true);ui.open("trade",trade);await process_frame;await process_frame
		ui.left.select(14);ui.right.select(1);ui.quantity.value=3;ui.left.get_v_scroll_bar().value=150;ui.quantity.get_line_edit().grab_focus();await process_frame
		var geometry:Rect2=ui.card.get_global_rect();var scroll:float=ui.left.get_v_scroll_bar().value
		var left_builds:int=int(ui.left.get_meta("service_rebuilds",0));var right_builds:int=int(ui.right.get_meta("service_rebuilds",0))
		var style:StyleBox=ui.left.get_theme_stylebox("panel");var theme_events:Array[int]=[0]
		var changed:Callable=func()->void:theme_events[0]+=1
		ui.left.theme_changed.connect(changed)
		for update:int in range(60):
			ui.receive({"trade":trade.duplicate(true)});ui.refresh()
			check(ui.card.get_global_rect().is_equal_approx(geometry),"Trade does not jump before the next frame")
			game._layout_dialogs();await process_frame
		check(int(ui.left.get_meta("service_rebuilds",0))==left_builds and int(ui.right.get_meta("service_rebuilds",0))==right_builds,"Identical native/world snapshots do not rebuild either trade list")
		check(ui.left.get_selected_items()==PackedInt32Array([14]) and ui.right.get_selected_items()==PackedInt32Array([1]),"Trade selections survive live refreshes")
		check(is_equal_approx(ui.left.get_v_scroll_bar().value,scroll) and ui.quantity.value==3 and ui.quantity.get_line_edit().has_focus(),"Trade retains scroll, quantity and typing focus")
		check(theme_events[0]==0 and ui.left.get_theme_stylebox("panel")==style,"Shared skin does not emit repeated theme changes")
		ui.left.theme_changed.disconnect(changed)
		trade.offers["200"][0].amount+=1;ui.state=trade;ui.refresh();await process_frame
		check(int(ui.right.get_meta("service_rebuilds",0))==right_builds+1 and ui.right.get_selected_items()==PackedInt32Array([1]),"Real offer changes rebuild once and preserve the correct owner's selection")
		check(ui.card.get_global_rect().is_equal_approx(geometry),"Changed offers keep trade geometry stable")
		trade.peer_agreed=true;ui.state=trade;ui.refresh();check(ui.details.text.contains("Accepted"),"Native approvals still update immediately")
	await shot("trade")
	ui.panel.hide();ui.mode="";game.online.trade.clear()
	var inspected:Dictionary={"player_id":200,"name":"Nearby","class_id":4,"equipment":{"weapon":21},"home":"Aeven"}
	ui.open("inspect",inspected);await process_frame;game._layout_dialogs();var inspected_rect:Rect2=ui.card.get_global_rect();var outline:StyleBox=ui.doll.slots.weapon.get_theme_stylebox("normal")
	check(ui.doll.visible and ui.doll.position==Vector2.ZERO and ui.doll.scale==Vector2(2,2) and ui.card.size==Vector2(760,580),"Inspection shows only the large original paperdoll")
	check(not ui.primary.visible and not ui.secondary.visible and not ui.extra.visible and not ui.quantity.visible and not ui.close_button.visible and not ui.title.visible and not ui.balance.visible and not ui.details.visible,"Paperdoll has no trade, party, book or whisper buttons")
	for update:int in range(60):ui.refresh();check(ui.card.get_global_rect().is_equal_approx(inspected_rect),"Inspection window stays fixed during world updates");game._layout_dialogs();await process_frame
	check(ui.doll.slots.weapon.get_theme_stylebox("normal")==outline,"Inspection reuses paperdoll outlines")
	await shot("inspection");ui.panel.hide();ui.mode="";game.character_panel.show();game._layout_dialogs();game._refresh_ui();var own_outline:StyleBox=game.paperdoll.slots.weapon.get_theme_stylebox("normal");var own_rect:Rect2=game.character_panel.get_child(0).get_global_rect()
	for update:int in range(60):game._refresh_ui();game._layout_dialogs();check(game.character_panel.get_child(0).get_global_rect().is_equal_approx(own_rect),"Own paperdoll stays fixed while live stats refresh");await process_frame
	check(game.paperdoll.slots.weapon.get_theme_stylebox("normal")==own_outline,"Own paperdoll does not recreate styles on every packet")
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"viewports":3,"player_menu_unchanged_frames":180,"trade_unchanged_frames":180,"paperdoll_unchanged_frames":120,"four_player_actions":true,"live_offer_updates":true,"offline":true}
	if not folder.is_empty():FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("PLAYER/TRADE STABILITY: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
