extends SceneTree
class Wire extends "res://scripts/online_session.gd":
	var calls:Array=[]
	func request(op:String,fields:Dictionary={})->int:calls.append([op,fields]);return calls.size()
var game:Node
var checks:int=0
var failed:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func run()->void:
	root.size=Vector2i(1544,720);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop()
	for card:Control in game.modal_cards:card.get_parent().hide()
	game.online.session.queue_free();var wire:Wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	game.started=true;game.online_mode=true;game.online.active=true
	game.online.player={"player_id":100,"name":"Fixture","level":1,"x":40,"y":40,"hp":10,"max_hp":10,"tp":10,"max_tp":10,"inventory":[],"equipment":{},"stats":{"class_id":0,"experience":705,"stat_points":0,"skill_points":3}}
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	var ui:RefCounted=game.chat_ui;ui.clear();wire.calls.clear()
	game.online._process_events([{"kind":"npc_killed","player_id":100,"npc_index":10,"exp_gain":8,"drop":{"uid":7,"id":258,"amount":2,"x":40,"y":40}},{"kind":"pickup","item_id":258,"amount":2,"uid":7},{"kind":"quest_stats","exp_gain":500,"level_up":2},{"kind":"party_exp","exp_gain":8}]);ui.tick()
	check(not ui.feed.visible and ui.feed_until==0,"Reward receipts do not constantly reopen the compact feed")
	ui.open();ui.select_tab(4)
	var text:String=ui.history.get_parsed_text()
	for fragment:String in ["Monster dropped Goat Horn ×2","Gained 8 EXP (monster)","Picked up Goat Horn ×2","Gained 500 EXP (quest)","Level 2 reached","Gained 8 EXP (party)"]:
		check(text.contains(fragment),"System history contains "+fragment)
	check(ui.tabs.size()==5 and ui.tabs[4].text=="System","Conversations has a dedicated System tab")
	check(not ui.entry.visible and not ui.panel.get_child(0).get_node("ChatSend").visible,"System is read-only")
	ui.entry.text="Cannot send this";ui.send_message();check(wire.calls.is_empty() and ui.entry.text=="Cannot send this","A hidden system composer cannot send any network message")
	ui.receive({"channel":"local","name":"Peer","message":"Nearby chat fixture"})
	check(not ui.history.get_parsed_text().contains("Nearby chat fixture"),"System does not mix player chat into receipts")
	ui.select_tab(0);check(ui.history.get_parsed_text().contains("Nearby chat fixture") and not ui.history.get_parsed_text().contains("Gained 8 EXP"),"Nearby chat stays distinct from System")
	ui.select_tab(4)
	for size:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=size;await process_frame
		for lift:float in [0.0,300.0]:
			ui._layout(lift);var card:Control=ui.panel.get_child(0)
			for tab:Button in ui.tabs:check(card.get_global_rect().encloses(tab.get_global_rect()),"Five tabs fit every layout")
			check(card.get_global_rect().encloses(ui.history.get_global_rect()),"Read-only history fits the card")
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"system_tab":true,"read_only":true,"monster_quest_party_exp":true,"drops_and_pickups":true,"quiet_reward_receipts":true,"viewports":3}
	var path:String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("SYSTEM HISTORY: ",JSON.stringify(report));game.queue_free();await process_frame;quit(1 if failed else 0)
