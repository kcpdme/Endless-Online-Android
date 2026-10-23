extends SceneTree
var game: Node
var observer: Node
var checks: int=0
var events: Array[Dictionary]=[]
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
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=81;e.position=root.get_final_transform()*control.get_global_rect().get_center();e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func join(scene: Node, fixture: Dictionary) -> bool:
	var c: Node=scene.online;c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fixture.username;c.password_field.text=fixture.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Soda fixture login failed"):return false
	c.character_list.select(0);c._enter_selected()
	return check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Soda fixture entry failed")
func screenshot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1600,720)
	var fs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SODA_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	if not await join(game,fs.actor):return
	observer=load("res://main.tscn").instantiate();root.add_child(observer);await process_frame
	observer.set_process_input(false);observer.set_process_unhandled_input(false)
	if not await join(observer,fs.observer):return
	observer.hide();observer.hud_root.hide();observer.camera.enabled=false;game.camera.make_current()
	var c: Node=game.online;var pid: int=int(c.player.player_id)
	c.session.message_received.connect(func(m: Dictionary) -> void:
		for row: Dictionary in (m.get("data",{}) as Dictionary).get("events",[]):events.append(row)
	)
	if not check(c.bag_amount(210)==3 and c.bag_amount(211)==1,"Fixture requires both sodas"):return
	game.inventory.show();game._select_item("item:210");game._refresh_ui();await process_frame
	await tap(game.equip_button)
	if not check(await wait_for(func() -> bool:return c.bag_amount(210)==2 and game.drink_effects.drunk()),"Small soda was not consumed or timer absent"):return
	if not check(events.any(func(e: Dictionary) -> bool:return e.get("kind")=="item_used" and int(e.get("item_id",0))==210 and is_equal_approx(float(e.get("drunk_seconds",0)),25)),"Small soda native duration incorrect"):return
	game.inventory.hide()
	if not check(await wait_for(func() -> bool:return game.drink_effects.emotes.has(pid) and observer.drink_effects.emotes.has(pid)),"Native drunk emote absent for player or observer"):return
	if not check(game._graphic(2,38)!=null,"Original drunk emote sheet missing"):return
	await screenshot("fairy-soda-emote")
	var hiccup: bool=false;var slurred: String=""
	for attempt: int in range(5):
		var phrase: String="hello everyone i am exploring aeven with fairy soda"
		c.chat_bubbles.erase(pid);observer.online.chat_bubbles.erase(pid)
		game.chat_ui.quick_entry.text=phrase;game.chat_ui.send_quick()
		if not check(await wait_for(func() -> bool:return c.chat_bubbles.has(pid) and observer.online.chat_bubbles.has(pid) and game.chat_ui.pending_chat.is_empty()),"Native chat or nearby bubbles absent"):return
		var bubble: Dictionary=c.chat_bubbles[pid];slurred=str(bubble.text)
		if not check(slurred!=phrase and bool(bubble.get("drunk",false)),"Original drunk-chat transformation missing"):return
		if not check(slurred==str(observer.online.chat_bubbles[pid].text),"Sender and observer see different soda speech"):return
		hiccup=hiccup or slurred.contains("*hic*")
		if hiccup:break
		await create_timer(.8).timeout
	if not check(hiccup,"Original random hiccup never appeared across long messages"):return
	game.speech_layer.sync();await process_frame
	if not check(game.speech_layer.visible and game.speech_layer.bubbles.has(pid),"Speech overlay not visible"):return
	var panel: Panel=game.speech_layer.bubbles[pid]
	if not check((panel.get_node("Message") as Label).text==slurred and (panel.get_node("Haze") as Label).visible,"Hiccups/stars or hazy soda text missing from bubble"):return
	# Regression: a Bard note must not replace the active soda chat bubble.
	var expiry: int=int(c.chat_bubbles[pid].until);c.session.request("bard_note",{"note":12})
	if not check(await wait_for(func() -> bool:return game.drink_effects.music_emotes.has(pid)),"Native Bard music emote absent"):return
	if not check(str(c.chat_bubbles[pid].text)==slurred and int(c.chat_bubbles[pid].until)==expiry,"Music note overwrote soda speech or shortened its lifetime"):return
	await screenshot("fairy-soda-chat-with-music")
	if not check(await wait_for(func() -> bool:return c.session.is_idle()),"Native actions did not settle"):return
	game.inventory.show();game._select_item("item:211");game._refresh_ui();await process_frame;await tap(game.equip_button)
	if not check(await wait_for(func() -> bool:return c.bag_amount(211)==0),"Big soda not consumed"):return
	if not check(events.any(func(e: Dictionary) -> bool:return e.get("kind")=="item_used" and int(e.get("item_id",0))==211 and is_equal_approx(float(e.get("drunk_seconds",0)),137.5)),"Big soda native duration incorrect"):return
	game.inventory.hide();c.log_out();observer.online.log_out()
	if not check(not game.drink_effects.drunk() and game.drink_effects.emotes.is_empty() and game.drink_effects.music_emotes.is_empty(),"Logout did not clear drink/music effects"):return
	var report: Dictionary={"result":"passed","checks":checks,"actual_native_small_and_big_soda_use":true,"small_seconds":25,"big_seconds":137.5,"native_drunk_emote_player_and_observer":true,"hiccups_and_slur_match_native_observer":true,"visible_overhead_hazy_chat":true,"bard_music_preserves_chat_text_and_expiry":true,"dev_accounts_only":true}
	var out: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ")+"\n")
	print("FAIRY SODA LIVE: ",JSON.stringify(report));game.queue_free();observer.queue_free()
	# Let final world/audio callbacks and websocket resources retire before exit.
	await create_timer(.2).timeout
	quit(0)
