extends SceneTree
## Opt-in offline feasibility pilot. No changes to the released game or assets.
class Wire extends "res://scripts/online_session.gd":
	var calls:Array[Dictionary]=[]
	func request(op:String,fields:Dictionary={})->int:
		calls.append({"op":op,"fields":fields});return calls.size()
class Probe extends "res://scripts/main.gd":
	var controls:RefCounted
	var slider:HSlider
	var caption:Label
	var pilot_panel:Control
	var taps:int=0
	var attacks:int=0
	var sample_records:Array[Dictionary]=[]
	var quality4:bool=false
	var high_frames:Dictionary={}
	var high_images:Dictionary={}
	var board:bool=false
	var board_state:String="idle"
	var board_direction:String="south"
	var pilot_ui_touches:Dictionary={}
	var pilot_mouse_capture:bool=false
	func _input(event:InputEvent)->void:
		if controls==null:return
		if pilot_mouse_capture and (event is InputEventMouseButton or event is InputEventMouseMotion):
			if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:pilot_mouse_capture=false
			return
		if controls.input(event):get_viewport().set_input_as_handled();return
		# Let the GUI own pilot widgets before the game's world-targeting handler.
		if event is InputEventScreenTouch:
			if event.pressed and pilot_panel.get_global_rect().has_point(event.position):pilot_ui_touches[event.index]=true;return
			if pilot_ui_touches.has(event.index):
				if not event.pressed:pilot_ui_touches.erase(event.index)
				return
		if event is InputEventScreenDrag and pilot_ui_touches.has(event.index):return
		if (event is InputEventMouseButton or event is InputEventMouseMotion) and pilot_panel.get_global_rect().has_point(event.position):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:pilot_mouse_capture=true
			return
		super._input(event)
	func _unhandled_input(event:InputEvent)->void:
		if event is InputEventMagnifyGesture:return
		if event is InputEventKey and event.pressed and event.keycode==KEY_H:
			quality4=not quality4;textures.clear();head_images.clear();queue_redraw()
		super._unhandled_input(event)
	func _notification(what:int)->void:
		if controls!=null and what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:controls.cancel();pilot_mouse_capture=false;pilot_ui_touches.clear()
		super._notification(what)
	func _request_path(_target:Vector2i)->void:taps+=1
	func _attack()->void:attacks+=1
	func _collect_loot(_force:bool=false)->void:pass
	func _process(delta:float)->void:
		if controls==null:return
		animation_clock+=delta;time_alive+=delta;camera.position=player_world;queue_redraw()
	func _frame(character:Dictionary,direction:String,state:String,phase:float=-1.0)->Dictionary:
		var frame:Dictionary=super._frame(character,direction,state,phase)
		if not quality4 or frame.is_empty() or frame.has("layers"):return frame
		if not frame.has("region"):return frame
		var key:String=player_item_art.frame_key(str(frame.get("path","")),frame.region)
		if not high_frames.has(key):return frame
		var spec:Dictionary=high_frames[key];var result:Dictionary=frame.duplicate()
		result.path=spec.path;result.region=spec.region;result.pixel_scale=4;result.visible_bounds=spec.visible_bounds.duplicate()
		if bool(result.get("flip_h",false)):result.visible_bounds[0]=result.region[2]-result.visible_bounds[0]-result.visible_bounds[2]
		return result
	func _texture(path:String)->Texture2D:
		if not path.begins_with("pilot4x://"):return super._texture(path)
		if textures.has(path):return textures[path]
		var image:Image=Image.load_from_file(high_images[path])
		var smooth:CanvasTexture=CanvasTexture.new();smooth.diffuse_texture=ImageTexture.create_from_image(image);smooth.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		textures[path]=smooth;return smooth
	func _draw_player()->void:
		_draw_character_frame(online.character_graphic(sample_records[0]),player_world,"south","idle",Color.WHITE,0)
	func _draw()->void:
		if not board:super._draw();return
		draw_rect(Rect2(0,0,1544,720),Color("182924"))
		var font:Font=ThemeDB.fallback_font
		draw_string(font,Vector2(28,40),"ZOOM PILOT / 150% VIEW / CURRENT 2× → SAMPLE 4×",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("ead0a0"))
		draw_string(font,Vector2(28,72),board_state+" / "+board_direction+" · same native proportions · actual runtime renderer",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("acb8ac"))
		var saved:bool=quality4
		for i:int in range(sample_records.size()):
			var x:float=25+(i%3)*512;var y:float=95+(i/3)*305
			draw_string(font,Vector2(x,y+22),sample_records[i].role,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("ead0a0"))
			for side:int in range(2):
				quality4=side==1
				draw_set_transform(Vector2(x+125+side*235,y+230),0,Vector2.ONE*2.475)
				_draw_character_frame(online.character_graphic(sample_records[i]),Vector2.ZERO,board_direction,board_state,Color.WHITE,.12)
				draw_set_transform(Vector2.ZERO)
				draw_string(font,Vector2(x+68+side*235,y+272),"Current 2×" if side==0 else "Pilot 4×",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("acb8ac"))
		quality4=saved
	func zoom_to(value:float)->void:
		camera.zoom=Vector2.ONE*controls.BASE*value;camera.position=player_world;camera.align_to_display_pixels()
		if slider!=null:slider.set_value_no_signal(value*100)
		if caption!=null:caption.text="Zoom %d%% · pinch empty world or drag"%roundi(value*100)
		queue_redraw()
	func free_world(point:Vector2)->bool:
		if pilot_panel!=null and pilot_panel.get_global_rect().has_point(point):return false
		if chat_ui.hud_contains(point) or minimap.contains(point) or joystick.contains_point(point):return false
		if skills_ui.contains(point)>=0 or quick_items.contains(point)>=0 or pet_ui.contains(point):return false
		for button:Control in [attack_button,bag_button,sit_button,chat_button,character_button,quest_journal.button,party_ui.button,admin_ui.button,menu_button,online.loot_button]:
			if button.is_visible_in_tree() and button.get_global_rect().has_point(point):return false
		return true
	func build_pilot()->void:
		controls=preload("res://tests/zoom_pilot_controls.gd").new()
		controls.available=func()->bool:return started and not _modal_open() and touch_move_id==-1 and attack_touch_id==-1 and owned_touches.is_empty() and not chat_ui.typing()
		controls.eligible=free_world;controls.changed.connect(zoom_to)
		controls.tapped.connect(func(_p:Vector2)->void:taps+=1)
		pilot_panel=PanelContainer.new();pilot_panel.position=Vector2(380,24);pilot_panel.size=Vector2(720,110);hud_root.add_child(pilot_panel)
		var column:VBoxContainer=VBoxContainer.new();pilot_panel.add_child(column)
		caption=Label.new();caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.add_theme_font_size_override("font_size",20);column.add_child(caption)
		var row:HBoxContainer=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;column.add_child(row)
		for percent:int in [100,125,130,150]:
			var button:Button=Button.new();button.text=str(percent)+"%";button.custom_minimum_size=Vector2(112,44);row.add_child(button)
			button.pressed.connect(func()->void:controls.set_scale(percent/100.0))
		slider=HSlider.new();slider.min_value=90;slider.max_value=150;slider.step=.1;slider.custom_minimum_size=Vector2(650,40);column.add_child(slider)
		slider.value_changed.connect(func(v:float)->void:controls.set_scale(v/100))
		controls.set_scale(1)

var game:Probe
var checks:int=0
var failed:bool=false
var output:String
var render_view:Viewport
func _initialize()->void:call_deferred("run")
func check(ok:bool,reason:String)->void:
	checks+=1
	if not ok:failed=true;push_error(reason)
func capture(name:String)->void:
	if output.is_empty():return
	await process_frame;await RenderingServer.frame_post_draw
	check(render_view.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Render capture "+name)
func touch(index:int,point:Vector2,pressed:bool,canceled:bool=false)->void:
	var e:InputEventScreenTouch=InputEventScreenTouch.new();e.index=index;e.position=point;e.pressed=pressed;e.canceled=canceled;game._input(e)
func drag(index:int,point:Vector2)->void:
	var e:InputEventScreenDrag=InputEventScreenDrag.new();e.index=index;e.position=point;game._input(e)
func ui_touch(point:Vector2,pressed:bool)->void:
	var e:InputEventScreenTouch=InputEventScreenTouch.new();e.index=0;e.position=point;e.pressed=pressed;Input.parse_input_event(e);await process_frame
func required_frames()->Dictionary:
	var required:Dictionary={}
	for record:Dictionary in game.sample_records:game.player_item_art.collect(game.online.character_graphic(record),required)
	return required
func run()->void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1544,720)
	render_view=root
	output=OS.get_environment("ASTER_VALE_ZOOM_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=Probe.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.enabled=false;game.music.stop();game.music.player.stream=null
	game.online.session.queue_free();var wire:Wire=Wire.new();game.online.add_child(wire);wire.set_process(false);game.online.session=wire
	game.welcome.hide();game.online.panel.hide();game.menu.hide();game.started=true;game.online_mode=true
	game.npc_art.select(true,false);game.player_item_art.select(true,false)
	game.player_tile=Vector2i(40,40);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	for spec:Dictionary in [
		{"role":"Warrior","gender":1,"hair":7,"color":4,"body":509,"boots":598,"head":0,"offhand":416,"weapon":498},
		{"role":"Magician","gender":1,"hair":5,"color":2,"body":501,"boots":574,"head":173,"offhand":0,"weapon":493},
		{"role":"Archer","gender":0,"hair":11,"color":4,"body":508,"boots":590,"head":0,"offhand":425,"weapon":496},
		{"role":"Rogue","gender":1,"hair":3,"color":0,"body":505,"boots":582,"head":0,"offhand":0,"weapon":497},
		{"role":"Priest","gender":0,"hair":10,"color":8,"body":500,"boots":566,"head":0,"offhand":0,"weapon":495},
		{"role":"Summoner","gender":1,"hair":14,"color":6,"body":503,"boots":606,"head":0,"offhand":0,"weapon":494}]:
		var equipment:Array=[]
		for id:int in [spec.boots,0,0,0,spec.body,0,spec.head,spec.offhand,spec.weapon]:equipment.append(int(game.online.catalog.items.get(str(id),{}).get("doll_graphic",0)))
		game.sample_records.append({"role":spec.role,"gender":spec.gender,"race":0,"hairstyle":spec.hair,"haircolor":spec.color,"equipment_graphics":equipment})
	if "--prepare-zoom-art" in OS.get_cmdline_user_args():
		FileAccess.open(output.path_join("required-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(required_frames()))
		game.queue_free();await process_frame;quit();return
	var sample_path:String=output.path_join("high-res.json")
	if FileAccess.file_exists(sample_path):
		var sample:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(sample_path))
		game.high_frames=sample.frames;game.high_images=sample.images
	game.online.player=game.sample_records[0].duplicate(true)
	game.online.player.merge({"player_id":9000,"name":"Offline zoom fixture","x":40,"y":40,"direction":0,"hp":500,"max_hp":500,"tp":200,"max_tp":200,"stats":{}})
	game.online.players.assign([game.sample_records[1].merged({"player_id":9001,"x":38,"y":40,"direction":1}),game.sample_records[2].merged({"player_id":9002,"x":40,"y":38,"direction":0})])
	game.online.npcs.assign([{"id":230,"index":8001,"x":43,"y":40,"direction":1},{"id":209,"index":8002,"x":43,"y":43,"direction":0}])
	game.online.drops.assign([{"id":457,"amount":1,"x":39,"y":41,"uid":7001},{"id":460,"amount":1,"x":41,"y":39,"uid":7002}])
	game.online.active=true;game.online.streaming=true;game.camera.force_update_scroll();game.build_pilot();await process_frame
	var c:RefCounted=game.controls
	# Free world points are deliberately outside all real HUD hit zones.
	var p:Vector2=Vector2(650,280);var q:Vector2=Vector2(850,280)
	check(game.free_world(p) and game.free_world(q),"Pinch fixture is in free world")
	var initial_taps:int=game.taps
	var emulated:InputEventMouseButton=InputEventMouseButton.new();emulated.position=p;emulated.device=InputEvent.DEVICE_ID_EMULATION;emulated.pressed=true;emulated.button_index=MOUSE_BUTTON_LEFT
	check(c.input(emulated),"Synthetic mouse cannot target the world before native touch")
	touch(11,p,true);check(game.taps==initial_taps,"First finger defers world targeting")
	touch(37,q,true);drag(37,q+Vector2(60,0));check(is_equal_approx(c.scale,1.3),"Indexed pinch zooms to 130%")
	check(game.camera.zoom==Vector2.ONE*2.145,"Uniform camera zoom preserves aspect ratio")
	touch(11,p,false);drag(37,q+Vector2(80,0));touch(37,q,false);check(game.taps==initial_taps,"No accidental tap when either pinch finger remains")
	c.set_scale(1);touch(8,p,true);touch(19,q,true);drag(19,p+Vector2(40,0));check(is_equal_approx(c.scale,.9),"Pinch-in clamps safely at 90%")
	drag(19,q+Vector2(2000,0));check(is_equal_approx(c.scale,1.5),"Pinch-out clamps at 150%")
	touch(8,p,false);touch(19,q,false)
	# Third finger, tiny gap, interrupted drag and cancelled touch cannot trigger taps.
	touch(6,p,true);touch(27,q,true);touch(91,Vector2(750,340),true);drag(27,q+Vector2(50,0));touch(27,q,false);touch(6,p,false);touch(91,Vector2(750,340),false)
	check(game.taps==initial_taps and c.points.is_empty(),"Third finger cancels the gesture until all releases")
	touch(5,p,true);touch(55,p+Vector2(1,0),true);drag(55,p+Vector2(1,0));check(is_finite(c.scale),"Near-zero span never produces infinite zoom")
	touch(55,p,false);touch(5,p,false)
	touch(4,p,true);game.menu.show();drag(4,p+Vector2(20,0));game.menu.hide();touch(4,p,false)
	check(game.taps==initial_taps,"Modal interruption suppresses latent world taps")
	touch(3,p,true);game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);touch(3,p,false)
	check(game.taps==initial_taps,"Focus loss consumes remaining release")
	touch(2,p,true);touch(2,p,false,true);check(game.taps==initial_taps,"OS cancelled touch is not a world tap")
	touch(2,p,true);touch(2,p,false);check(game.taps==initial_taps+1,"Single world tap fires once on release")
	c.set_scale(1);var z:float=c.scale
	game.touch_move_id=41;touch(12,p,true);touch(13,q,true);drag(13,q+Vector2(80,0));touch(12,p,false);touch(13,q,false);game._cancel_controls()
	check(c.scale==z,"Joystick plus another finger never becomes pinch")
	game.attack_touch_id=44;touch(22,p,true);touch(23,q,true);drag(23,q+Vector2(80,0));touch(22,p,false);touch(23,q,false);game._cancel_controls()
	check(c.scale==z,"Held attack plus another finger never becomes pinch")
	var pad:Vector2=game._joystick_zone().get_center()
	touch(41,pad,true);drag(41,pad+Vector2(35,0));touch(51,p,true);drag(51,q);touch(51,q,false)
	check(game.touch_move_id==41 and game.stick.length()>.9 and c.scale==z,"Real joystick capture survives another world finger")
	touch(41,pad,false)
	var bag_at:Vector2=game.bag_button.get_global_rect().get_center();check(not game.free_world(bag_at),"Bag touch area is excluded from zoom")
	var taps_before_hud:int=game.taps
	touch(42,p,true);touch(61,bag_at,true);touch(61,bag_at,false);touch(42,p,false)
	check(game.inventory.visible and c.scale==z and game.taps==taps_before_hud,"HUD bag opens normally and cancels a pending world tap")
	game.inventory.hide()
	var slider_rect:Rect2=game.slider.get_global_rect()
	check(not game.free_world(slider_rect.get_center()),"Thumb zoom slider cannot target the world underneath")
	game.slider.value=125;check(is_equal_approx(c.scale,1.25),"One-thumb slider drives 125% camera zoom")
	var taps_before_ui:int=game.taps
	await ui_touch(Vector2(slider_rect.position.x+slider_rect.size.x*.25,slider_rect.get_center().y),true)
	var slider_drag:InputEventScreenDrag=InputEventScreenDrag.new();slider_drag.index=0;slider_drag.position=Vector2(slider_rect.position.x+slider_rect.size.x*.66667,slider_rect.get_center().y);Input.parse_input_event(slider_drag);await process_frame
	await ui_touch(Vector2(slider_rect.position.x+slider_rect.size.x*.66667,slider_rect.get_center().y),false)
	check(absf(c.scale-1.3)<.015 and game.taps==taps_before_ui,"Actual thumb slider touch changes zoom without a world tap")
	check(game.pilot_ui_touches.is_empty() and not game.pilot_mouse_capture,"Thumb slider releases both native and emulated pointer ownership")
	# Match the connected Samsung's native pixel count while retaining its logical
	# 1544×720 game layout. Input tests above use a 1:1 viewport for deterministic taps.
	if not "--interactive-zoom-pilot" in OS.get_cmdline_user_args():
		var phone:SubViewport=SubViewport.new();phone.size=Vector2i(2316,1080);phone.size_2d_override=Vector2i(1544,720);phone.size_2d_override_stretch=true;phone.world_2d=World2D.new();phone.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(phone);game.reparent(phone);render_view=phone;await process_frame
	for ratio:float in [1.0,1.25,1.3,1.5]:
		c.set_scale(ratio);await process_frame;game.queue_redraw()
		var before:Vector2=game.player_world;var camera_at:Vector2=game.camera.position
		for phase:int in range(24):
			game.camera.position=camera_at+Vector2(phase/24.0,phase/48.0);game.camera.align_to_display_pixels()
			var pixels:Transform2D=render_view.get_final_transform()*render_view.get_canvas_transform()
			check((pixels.origin-game.camera.PIXEL_PHASE).distance_to((pixels.origin-game.camera.PIXEL_PHASE).round())<.003,"Pixel-phase camera alignment survives zoom")
		check(game.player_world==before,"Zoom never changes world/player coordinates")
		game.camera.position=game.player_world;game.camera.align_to_display_pixels();await capture("world-%d"%roundi(ratio*100))
	if not game.high_frames.is_empty():
		# Higher pixel density must not enlarge the character or shift hands/feet.
		for record:Dictionary in game.sample_records:
			for state:String in ["idle","frames","attack","cast","sit_floor"]:
				for direction:String in ["south","east","north","west"]:
					game.quality4=false;var low:Dictionary=game._frame(game.online.character_graphic(record),direction,state,.12)
					game.quality4=true;var high:Dictionary=game._frame(game.online.character_graphic(record),direction,state,.12)
					var low_parts:Array=low.get("layers",[low]);var high_parts:Array=high.get("layers",[high])
					check(low_parts.size()==high_parts.size(),"4x sample preserves all equipped layers")
					for i:int in range(low_parts.size()):
						check(game.nameplates._part_rect(low_parts[i],Vector2.ZERO)==game.nameplates._part_rect(high_parts[i],Vector2.ZERO),"4x artwork preserves native pose geometry")
		game.quality4=true;game.textures.clear();game.head_images.clear();game.queue_redraw();await capture("world-150-4x")
		game.board=true;game.camera.enabled=false;game.hud_root.hide()
		for state:String in ["idle","frames","attack","cast","sit_floor"]:
			for direction:String in ["south","east","north","west"]:
				game.board_state=state;game.board_direction=direction;game.queue_redraw();await capture("art-"+state+"-"+direction)
		game.board=false;game.camera.enabled=true;game.hud_root.show();game.quality4=false
	check(FileAccess.file_exists("res://content/visual_enhanced/pack.json"),"Released enhanced art stays installed")
	check(wire.calls.is_empty(),"Gesture pilot sends no gameplay/network requests")
	var report:Dictionary={"result":"failed" if failed else "passed","checks":checks,"rendered":DisplayServer.get_name()!="headless","capture_pixels":[render_view.get_texture().get_width(),render_view.get_texture().get_height()],"base_camera_zoom":1.65,"relative_range":[.9,1.5],"presets":[1,1.25,1.3,1.5],"high_resolution_sample":not game.high_frames.is_empty(),"normal_main_scene_unchanged":true,"network_gameplay_requests":wire.calls.size(),"device_installation":false}
	if not output.is_empty():FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("ZOOM PILOT: ",JSON.stringify(report))
	if "--interactive-zoom-pilot" in OS.get_cmdline_user_args() and not failed:
		game.set_process(true);return
	game.online.active=false;game.started=false;game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
