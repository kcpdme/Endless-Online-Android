extends SceneTree
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields});return calls.size()
class Probe extends "res://scripts/main.gd":
	var paths:int=0
	var strikes:int=0
	func _request_path(_at:Vector2i)->void:paths+=1
	func _attack()->void:strikes+=1
var checks:int=0
var failed:bool=false
var game:Probe
var output:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func touch(at:Vector2,pressed:bool,index:int=51)->void:
	var e:InputEventScreenTouch=InputEventScreenTouch.new();e.index=index;e.position=at;e.pressed=pressed;game._input(e)
func mouse(at:Vector2,pressed:bool,emulated:bool=false)->void:
	var e:InputEventMouseButton=InputEventMouseButton.new();e.position=at;e.pressed=pressed;e.button_index=MOUSE_BUTTON_LEFT
	if emulated:e.device=InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(e);await process_frame
func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Saved "+name)
func run()->void:
	output=OS.get_environment("ASTER_VALE_CHAT_ZOOM_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1544,720)
	game=Probe.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop();game.music.player.stream=null
	game.online.session.queue_free();var wire:Wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	game.welcome.hide();game.online.panel.hide();game.menu.hide();game.started=true;game.online_mode=true;game.online.active=true;game.online.streaming=true
	game.online.player={"player_id":9000,"name":"Offline fixture","x":40,"y":40,"gender":1,"race":0,"hairstyle":7,"haircolor":4,"equipment_graphics":[1,0,0,0,1,0,0,0,4],"hp":500,"max_hp":500,"tp":100,"max_tp":100,"stats":{"class_id":6,"level":50}}
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	game.zoom_button.show();game.admin_ui.button.show();game.party_ui.button.show();game.pet_ui.collection_button.show()
	var ui:RefCounted=game.chat_ui;ui.clear();ui.tick()
	check(ui.feed.get_v_scroll_bar().custom_minimum_size.x==6,"Compact feed retains its slim indicator without the modal-list styling")
	check(not ui.feed.visible and not ui.feed_close.visible and ui.quick_bar.is_visible_in_tree(),"Empty chat leaves only the composer")
	game.online._process_events([{"kind":"npc_speech","npc_id":127,"npc_index":37,"message":"Welcome to Aeven. This is an offline NPC fixture."}]);ui.tick()
	check(ui.feed.visible and ui.feed_close.visible and not ui.panel.visible,"NPC speech briefly opens the feed without a conversation modal")
	check(ui.feed_until-Time.get_ticks_msec()>7500 and ui.feed_until-Time.get_ticks_msec()<=8000,"Message starts an eight-second timeout")
	check(ui.feed.get_parsed_text().contains("Welcome to Aeven"),"NPC message remains readable")
	await capture("normal-message")
	ui.feed_until=Time.get_ticks_msec()-1;ui.tick()
	check(not ui.feed.visible and not ui.feed_background.visible and not ui.feed_close.visible,"Expired feed and its arrow collapse together")
	check(ui.messages.size()==1 and ui.feed.get_parsed_text().contains("Welcome to Aeven"),"Collapsing retains message history")
	check(not ui.hud_contains(ui.feed.get_global_rect().get_center()),"Collapsed feed no longer captures world taps")
	ui.receive({"channel":"global","name":"Fixture","message":"A new message briefly reveals chat again."});ui.tick()
	check(ui.feed.visible,"Later incoming message reveals the feed again")
	ui.quick_entry.text="Unsent draft";ui.quick_entry.grab_focus();await process_frame
	ui.feed_until=Time.get_ticks_msec()-1;ui.tick();check(ui.feed.visible,"Feed stays open while typing")
	ui.blur_quick();ui.tick();check(ui.feed_until>Time.get_ticks_msec()+7500,"Typing leaves time to read after keyboard closes")
	var held:InputEventScreenTouch=InputEventScreenTouch.new();held.index=88;held.pressed=true
	ui._scroll_input(ui.feed,held);ui.feed_until=Time.get_ticks_msec()-1;ui.tick();check(ui.feed.visible,"Feed stays open while a reader holds its scrollbar gesture")
	held.pressed=false;ui._scroll_input(ui.feed,held);ui.feed_until=Time.get_ticks_msec()-1;ui.tick();check(not ui.feed.visible,"Feed closes after reading ends")
	ui.receive({"channel":"system","name":"Server","message":"Temporary information"});ui.tick()
	var close_at:Vector2=ui.feed_close.get_global_rect().get_center();var before_paths:int=game.paths;var before_attacks:int=game.strikes
	await mouse(close_at,true,true);check(ui.feed.visible,"Synthetic mouse press waits for native arrow touch")
	touch(close_at,true);check(not ui.feed.visible and ui.feed_pointer==51,"Native down arrow collapses immediately and owns the touch")
	touch(close_at+Vector2(0,80),false);await mouse(close_at,true,true);await mouse(close_at,false,true)
	check(game.paths==before_paths and game.strikes==before_attacks and wire.calls.is_empty(),"Disappearing arrow and duplicate mouse never interact with the world")
	check(ui.quick_entry.text=="Unsent draft" and ui.quick_bar.is_visible_in_tree(),"Manual collapse preserves draft and composer")
	ui.receive({"channel":"local","name":"Fixture","message":"Focus-loss fixture"});ui.tick()
	touch(close_at,true,53);game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(ui.feed_pointer==-1 and ui.scroll_fingers.is_empty(),"Focus loss releases the disappearing chat button's touch ownership")
	touch(close_at,false,53)
	ui.open();check(ui.panel.visible and ui.history.get_parsed_text().contains("Temporary information"),"Full conversations retain hidden feed history")
	ui.feed_until=Time.get_ticks_msec()-1;ui.tick();check(ui.panel.visible,"Manually opened conversations do not auto-close")
	ui.close();ui.tick()
	var config_path:String="user://chat-zoom-fixture.cfg";game.camera.settings_path=config_path
	var config:ConfigFile=ConfigFile.new();config.set_value("graphics","enhanced_npcs",false);config.set_value("graphics","players_and_items",true);config.save(config_path)
	game.camera.select_view(false,false);game.zoom_button.set_pressed_no_signal(false)
	check(game.camera.zoom==Vector2.ONE*1.65,"Normal mode retains the original camera size")
	var zoom_at:Vector2=game.zoom_button.get_global_rect().get_center()
	await mouse(zoom_at,true,true);check(not game.camera.zoomed,"Synthetic zoom press cannot double-toggle")
	touch(zoom_at,true,52);touch(zoom_at,false,52);await mouse(zoom_at,false,true)
	check(game.camera.zoomed and game.camera.zoom==Vector2.ONE*2.0625 and game.zoom_button.button_pressed,"Touch toggles to exactly 125% on both axes")
	var target:Vector2=game.tile_position(Vector2i(41,40))+Vector2(0,-30)
	check(game._screen_to_world(game.get_global_transform_with_canvas()*target).distance_to(target)<.01,"Zoomed screen taps retain the exact world target")
	check(not game.moving and game.route.is_empty() and game.paths==before_paths and wire.calls.is_empty(),"Zoom button cannot walk, target or make a server request")
	var restored:Camera2D=preload("res://scripts/world_camera.gd").new();restored.settings_path=config_path;restored.load_view()
	check(restored.zoomed and restored.zoom==game.camera.zoom,"Zoom view survives a new camera/launch")
	config.load(config_path);check(config.get_value("graphics","enhanced_npcs",true)==false and config.get_value("graphics","players_and_items",false)==true,"Zoom preserves the artwork preferences")
	restored.free()
	# Real desktop GUI press/release exercises Button.toggle_mode too.
	await mouse(zoom_at,true);await mouse(zoom_at,false)
	check(not game.camera.zoomed and not game.zoom_button.button_pressed,"Desktop click returns to Normal once")
	game._toggle_camera_view();check(game.camera.zoomed,"Normal can be switched back to 125% repeatedly")
	game.menu.show();game._toggle_camera_view();check(game.camera.zoomed,"Open dialogs block zoom input")
	game.menu.hide();game._set_camera_view(false)
	for factor:float in [1.1,.85,3.0,.1]:
		var gesture:InputEventMagnifyGesture=InputEventMagnifyGesture.new();gesture.factor=factor;game._unhandled_input(gesture)
		check(game.camera.zoom in [Vector2.ONE*1.65,Vector2.ONE*2.0625],"Supported magnify input cannot introduce a third camera scale")
	for dimensions:Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1544,720)]:
		root.size=dimensions;await process_frame;ui.tick()
		var icon:Rect2=game.zoom_button.get_global_rect()
		check(game.get_viewport_rect().encloses(icon),"Zoom icon fits "+str(dimensions))
		for other:Control in [game.admin_ui.button,game.party_ui.button,game.skills_ui.buttons[2],game.pet_ui.collection_button,game.character_button,game.menu_button]:
			check(not icon.intersects(other.get_global_rect()),"Zoom icon does not overlap another top control")
		check(not icon.intersects(game.stats_ui.vitals.get_global_rect()),"Zoom icon clears HP/TP")
		ui.receive({"channel":"local","name":"Fixture","message":"Messages fold away after eight seconds. Use the down arrow to hide them sooner."});ui.tick()
		check(ui.feed.size.x==480 and ui.feed_close.size==Vector2(30,30),"Small arrow keeps the original full-width message area")
		check(ui.feed_close.get_global_rect().end.y<=ui.feed_background.get_global_rect().position.y,"Arrow sits on the upper-right edge without reserving a text column")
		check(not ui.feed.get_global_rect().intersects(ui.feed_close.get_global_rect()),"Down arrow does not cover message text")
		game._set_camera_view(true);await capture("zoomed-%dx%d"%[dimensions.x,dimensions.y])
		ui.collapse_feed();await capture("collapsed-%dx%d"%[dimensions.x,dimensions.y])
	check(game.paths==before_paths and game.strikes==before_attacks and wire.calls.is_empty(),"All UI checks leave gameplay and network idle")
	DirAccess.remove_absolute(config_path)
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"feed_timeout_seconds":8,"typing_and_scrolling_protected":true,"manual_collapse_preserves_history_and_draft":true,"zoom_modes":[1,1.25],"touch_and_mouse_verified":true,"zoom_preference_persists":true,"network_requests":wire.calls.size(),"rendered":DisplayServer.get_name()!="headless"}
	if not output.is_empty():FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("CHAT/ZOOM: ",JSON.stringify(report));game.online.active=false;game.started=false;game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
