extends SceneTree
class EmptyWorld extends "res://scripts/main.gd":
	func _draw() -> void: pass
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
func run() -> void:
	var view: SubViewport = SubViewport.new(); view.size = Vector2i(600,360); view.transparent_bg = true; view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var game: EmptyWorld = EmptyWorld.new(); view.add_child(game); await process_frame
	game.set_process(false); game.music.stop(); game.online.set_process(false); game.online.session.set_process(false)
	game.started=true;game.online_mode=true;game.menu.hide();game.welcome.hide();game.online.panel.hide()
	for child: Node in game.hud_root.get_children():
		if child is Control and child != game.nameplates: child.hide(); child.set_process(false)
	game.nameplates.set_process(false)
	var online: Node=game.online;online.active=true;online.player={"player_id":100}
	var record: Dictionary={"id":127,"index":1,"x":40,"y":40,"direction":0};online.npcs.assign([record])
	var at: Vector2=game.tile_position(Vector2i(40,40))
	var font_images: Dictionary={}
	for scale_factor: float in [1.0,1.5]:
		view.size=Vector2i(Vector2(400,240)*scale_factor);view.size_2d_override=Vector2i(400,240);view.size_2d_override_stretch=true
		await process_frame;await process_frame
		var images: Dictionary={}
		for phase: int in range(24):
			game.camera.position=at-Vector2(0,55)+Vector2(phase/24.0,phase/48.0)
			game.nameplates.sync()
			check(game.nameplates.entries.size()==1,"Exactly one NPC name, without duplicate world text")
			if game.nameplates.entries.is_empty():continue
			var entry: Dictionary=game.nameplates.entries[0]
			var pixels: Vector2=view.get_final_transform()*game.nameplates.get_global_transform_with_canvas()*(entry.baseline as Vector2)
			check(pixels.distance_to(pixels.round())<.001,"Baseline aligned after viewport/device scaling")
			if DisplayServer.get_name()!="headless":
				await process_frame;await RenderingServer.frame_post_draw
				var image: Image=view.get_texture().get_image();var rect: Rect2i=image.get_used_rect()
				check(rect.has_area(),"Actual name glyphs are visible")
				if rect.has_area():images[image.get_region(rect).get_data().hex_encode()]=true
		if DisplayServer.get_name()!="headless":check(images.size()==1,"Glyph image is unchanged across 24 fractional camera positions")
		font_images[str(scale_factor)]=images.size()
	# The shared sample keeps label and sprite together even when sampling time differs.
	var now: float=Time.get_ticks_msec()/1000.0
	online.remote_motion["npc:1"]={"to":at+Vector2(32,16),"tile":Vector2i(41,40),"walk_start":now,"steps":[{"from":at,"to":at+Vector2(32,16),"start":now-.15,"direction":"east"}]}
	online.render_pose_cache.clear();game.nameplates.sync()
	var pose: Dictionary=online.entity_render_pose("online_npc",record)
	check((pose.position as Vector2)!=at and (pose.position as Vector2)!=at+Vector2(32,16),"Name follows the smooth intermediate position")
	var cached: Vector2=pose.position
	online.remote_motion["npc:1"].steps[0].start=now-.25
	check(online.entity_render_pose("online_npc",record).position==cached,"Sprite and name share one sample per rendered frame")
	var idle_baseline: Vector2=game.nameplates.entries[0].baseline
	online.npc_health[1]={"percent":50,"until":Time.get_ticks_msec()+10000};game.nameplates.sync()
	check(game.nameplates.entries.size()==1 and game.nameplates.entries[0].baseline==idle_baseline,"Combat does not duplicate or reposition the name")
	if DisplayServer.get_name()!="headless":
		online.remote_motion.clear();online.render_pose_cache.clear()
		for zoom: float in [1.0,1.65,2.5]:
			game.camera.zoom=Vector2(zoom,zoom);game.camera.position=at-Vector2(0,55)
			game.nameplates.sync();await process_frame;await RenderingServer.frame_post_draw
			var image: Image=view.get_texture().get_image()
			var bar_bottom: int=-1;var text_top: int=image.get_height()
			for y: int in range(image.get_height()):
				for x: int in range(image.get_width()):
					var color: Color=image.get_pixel(x,y)
					if color.a<.5:continue
					if color.g-color.r>.10 and color.g>.6:bar_bottom=maxi(bar_bottom,y)
					if color.r>.75 and color.g>.75 and color.b>.75:text_top=mini(text_top,y)
			check(bar_bottom>=0 and text_top<image.get_height() and bar_bottom+2<text_top,"Rendered health bar clears the entire name at zoom "+str(zoom))
	game.camera.zoom=Vector2(1.65,1.65)
	# Transparent Wraith art still controls the visibility of its caption.
	record.id=255;online.remote_motion.clear();online.npc_attack_until.clear();online.render_pose_cache.clear();game.nameplates.sync()
	check(game.nameplates.entries.is_empty(),"Idle invisible Wraith has no name, even with a health record")
	online.remote_motion["npc:1"]={"to":at,"tile":Vector2i(40,40),"walk_start":now,"steps":[{"from":at,"to":at,"start":now,"direction":"south"}]}
	online.render_pose_cache.clear();game.nameplates.sync();check(game.nameplates.entries.is_empty(),"Walking invisible Wraith has no name")
	online.npc_attack_until[1]=Time.get_ticks_msec()/1000.0+.3;online.render_pose_cache.clear();game.nameplates.sync()
	check(game.nameplates.entries.size()==1,"Wraith name appears during its visible attack")
	online.npc_attack_until.clear();online.remote_motion.clear();online.render_pose_cache.clear();game.nameplates.sync()
	check(game.nameplates.entries.is_empty(),"Wraith name disappears after its visible attack")
	online.npcs.clear();online.players.assign([{"player_id":101,"x":40,"y":40,"name":"devpeer","direction":0}]);online.render_pose_cache.clear();game.nameplates.sync()
	check(game.nameplates.entries.size()==1 and game.nameplates.entries[0].color==Color("b9e2c5"),"Nearby player name keeps its color")
	check(game.nameplates.mouse_filter==Control.MOUSE_FILTER_IGNORE and game.nameplates.z_index<0,"Names stay below HUD and never consume touches")
	var first: Dictionary=online.entity_render_pose("online_item",{"uid":1,"x":1,"y":2})
	var second: Dictionary=online.entity_render_pose("online_item",{"uid":2,"x":3,"y":4})
	check(first.position!=second.position,"Independent ground items retain distinct positions")
	game.menu.show();game.nameplates.sync();check(not game.nameplates.visible and game.nameplates.entries.is_empty(),"Modal opening hides names immediately")
	game.menu.hide();online.active=false;game.nameplates.sync();check(not game.nameplates.visible and game.nameplates.entries.is_empty(),"Disconnect clears nameplates")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"pixel_render_test":DisplayServer.get_name()!="headless","distinct_glyph_images_by_scale":font_images,"shared_interpolation":true,"wraith_visibility_preserved":true,"input_and_modals_preserved":true}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("NAMEPLATES: ",JSON.stringify(report));view.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
