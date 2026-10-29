extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary]=[]
	func request(op: String, fields: Dictionary={}) -> int:
		serial+=1;calls.append({"op":op,"fields":fields.duplicate()});return serial
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(why)
func tap(control: Control) -> void:
	await process_frame;await process_frame
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=85;e.position=root.get_final_transform()*control.get_global_rect().get_center();e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func shot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1600,720)
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.set_process(false);game.music.stop();game.started=true;game.welcome.hide();game.online.panel.hide();game.online_mode=true
	var c: Node=game.online;c.set_process(false);c.active=true;c.streaming=true;c.session.queue_free()
	var wire: Capture=Capture.new();c.add_child(wire);wire.set_process(false);c.session=wire
	c.player={"name":"devfixture","player_id":100,"character_id":1,"map_id":5,"x":40,"y":40,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"inventory":[],"spells":[],"equipment":{}}
	var journal: RefCounted=game.quest_journal
	check(game._graphic(2,68)!=null,"Original quest icon atlas is imported")
	for dimensions: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720),Vector2i(1920,1080)]:
		root.size=dimensions;await process_frame;await process_frame
		var icons: Array=[game.skills_ui.buttons[2],journal.button,game.stats_button,game.character_button]
		for control: Control in icons:check(root.get_visible_rect().encloses(control.get_global_rect()),"Top icons fit landscape safe area")
		for i: int in range(icons.size()-1):check(icons[i].get_global_rect().end.x < icons[i+1].get_global_rect().position.x,"Quests, stats and equipment icons stay separate")
		journal.panel.show();await process_frame;check(root.get_visible_rect().encloses(journal.panel.get_child(0).get_global_rect()),"Quest journal fits landscape");journal.dismiss()
	root.size=Vector2i(1600,720);await process_frame;await process_frame;await shot("quests-hud-icon")
	await tap(journal.button)
	check(journal.panel.visible and game._modal_open() and not game.joystick.active,"Quest touch opens a movement-blocking journal")
	check(wire.calls.size()==1 and wire.calls[0]=={"op":"quest_list","fields":{"page":"progress"}},"One native touch sends one progress request")
	check(journal.busy and journal.refresh_button.disabled,"Pending query disables duplicate requests")
	var rows: Array=[{"name":"Pjedro's Son","description":"Talk to Pjedro's Wife","icon":5,"progress":0,"target":0},{"name":"Aeven hunting","description":"Defeat rats","icon":8,"progress":3,"target":10}]
	c._on_message({"op":"quest_list","ok":true,"data":{"quest_journal":{"page":"progress","entries":rows}}})
	check(not journal.busy and journal.body.get_child_count()==2,"Native rows display with no optimistic objectives")
	var labels: String=""
	for label: Node in journal.body.find_children("*","Label",true,false):labels+=label.text+"\n"
	check(labels.contains("Talk to Pjedro's Wife") and labels.contains("3 / 10"),"Native objective and counters are readable")
	check(journal.body.find_children("*","ProgressBar",true,false).size()==1,"Only native numeric targets get a progress meter")
	await shot("quests-ongoing")
	await tap(journal.tabs[1]);check(wire.calls.back().fields.page=="history","Completed tab requests native history")
	c._on_message({"op":"quest_list","ok":true,"data":{"quest_journal":{"page":"history","entries":[{"name":"Pjedro's Son"}]}}})
	check(journal.title.text=="Completed quests" and journal.body.get_child_count()==1,"Native completed list is separate from ongoing")
	await shot("quests-completed")
	await tap(journal.tabs[0]);c._on_message({"op":"quest_list","ok":true,"data":{"quest_journal":{"page":"progress","entries":[]}}})
	check((journal.body.get_child(0) as Label).text.begins_with("No ongoing quests"),"Empty native list has an honest empty state")
	await tap(journal.refresh_button);c._on_message({"op":"quest_list","ok":false,"error":"Quest service unavailable"})
	check(journal.panel.visible and not journal.busy and journal.status.text=="Quest service unavailable","Errors keep retry and dismissal available")
	game._handle_back();check(not journal.panel.visible and not game._modal_open(),"Android Back dismisses quest journal")
	journal.receive({"quest_journal":{"page":"progress","entries":rows}});check(not journal.panel.visible,"Late quest reply never reopens a dismissed journal")
	journal.open();c.log_out();check(not journal.panel.visible and journal.state.is_empty(),"Logout clears another character's quest cache")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"quest_icon_beside_stats":true,"four_landscape_sizes":true,"native_progress_and_history":true,"single_touch_no_movement":true,"no_optimistic_quests":true,"back_late_reply_logout":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var out: FileAccess=FileAccess.open(path,FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ")+"\n")
	print("QUEST JOURNAL: ",JSON.stringify(report));game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
