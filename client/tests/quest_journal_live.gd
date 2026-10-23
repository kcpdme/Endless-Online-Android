extends SceneTree
var game: Node
var checks: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:push_error(why);quit(1)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func tap(control: Control) -> void:
	await process_frame;await process_frame
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=86;e.position=root.get_final_transform()*control.get_global_rect().get_center();e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func shot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1600,720)
	var fs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_QUEST_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c: Node=game.online;c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fs.username;c.password_field.text=fs.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Quest fixture login failed"):return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Quest fixture entry failed"):return
	var ui: RefCounted=game.quest_journal
	await tap(ui.button)
	if not check(await wait_for(func() -> bool:return ui.panel.visible and not ui.busy and ui.state.get("page")=="progress"),"Native quest progress did not arrive: "+ui.status.text):return
	var rows: Array=ui.state.entries
	var pjedro: Dictionary={};var ayla: Dictionary={}
	for row: Dictionary in rows:
		if str(row.name)=="Pjedro's Son":pjedro=row
		if str(row.name)=="Rat Problems":ayla=row
	if not check(not pjedro.is_empty() and str(pjedro.description)=="Talk to Pjedro's Wife","Native saved ongoing quest or objective missing"):return
	if not check(not ayla.is_empty() and int(ayla.target)==20 and int(ayla.progress)==3,"Native saved kill counter must show 3 / 20: "+JSON.stringify(rows)):return
	if not check(game._graphic(2,68)!=null and ui.body.find_children("*","TextureRect",true,false).size()>=4,"Original quest objective icons missing"):return
	await shot("quests-native-ongoing")
	await tap(ui.tabs[1])
	if not check(await wait_for(func() -> bool:return not ui.busy and ui.state.get("page")=="history"),"Native quest history did not arrive"):return
	if not check((ui.state.entries as Array).any(func(row: Dictionary) -> bool:return str(row.name)=="Pirate Quest"),"Native saved completed quest missing"):return
	await shot("quests-native-completed")
	game._handle_back()
	if not check(not ui.panel.visible and not game._modal_open(),"Native journal does not close through Android Back"):return
	c.log_out();game.queue_free();await create_timer(.2).timeout
	var report: Dictionary={"result":"passed","checks":checks,"native_saved_ongoing_objective":true,"native_saved_kill_progress_3_of_20":true,"native_saved_completed_history":true,"original_quest_icons":true,"actual_hud_touch_and_back":true,"dev_character_only":true}
	var f: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n")
	print("QUEST JOURNAL LIVE: ",JSON.stringify(report));quit(0)
