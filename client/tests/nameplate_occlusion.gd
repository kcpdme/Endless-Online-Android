extends SceneTree
# Real render-pipeline regression: hide an entire colliding label, not letters.
class SceneryProbe extends "res://scripts/main.gd":
	var obscure_name: bool=false
	func _draw() -> void:
		super._draw()
		if not obscure_name or nameplates==null or nameplates.entries.is_empty():return
		var entry: Dictionary=nameplates.entries[0]
		var to_world: Transform2D=get_global_transform_with_canvas().affine_inverse()*nameplates.get_global_transform_with_canvas()
		var bounds: Rect2=Rect2((entry.baseline as Vector2)-Vector2(3,ThemeDB.fallback_font.get_ascent(int(entry.font_size))+3),Vector2(float(entry.width)+6,ThemeDB.fallback_font.get_height(int(entry.font_size))+6))
		draw_rect(to_world*bounds,Color("c02020"))
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func capture(view: SubViewport, game: Node, captions: bool=true) -> Image:
	game.nameplates.sync();game.nameplates.visible=captions;game.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	var view: SubViewport=SubViewport.new();view.size=Vector2i(600,360);view.transparent_bg=true;view.world_2d=World2D.new();view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game: SceneryProbe=SceneryProbe.new();view.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop()
	game.started=true;game.online_mode=true;game.menu.hide();game.welcome.hide();game.online.panel.hide()
	for child: Node in game.hud_root.get_children():
		if child is Control and child!=game.nameplates:child.hide();child.set_process(false)
	game.nameplates.set_process(false);game.nameplates.set_process_input(false);game.world={};game.decorations.clear();game.ground.clear()
	var online: Node=game.online;online.active=true
	online.player={"player_id":100,"name":"Self","gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,0,0,0]}
	var record: Dictionary={"id":1,"index":1,"x":40,"y":40,"direction":0}
	var peer: Dictionary=online.player.duplicate();peer.merge({"player_id":101,"x":40,"y":40,"direction":0,"name":"Nearby player"},true)
	var results: Array[Dictionary]=[]
	var scenery_checks: int=0
	for scale_factor: float in [1.0,1.5]:
		view.size=Vector2i(Vector2(400,240)*scale_factor);view.size_2d_override=Vector2i(400,240);view.size_2d_override_stretch=true
		for kind: String in ["crow","player","guild_bob"]:
			for zoom: float in [1.0,1.65,2.5]:
				online.npcs.clear();online.players.clear();online.render_pose_cache.clear()
				if kind!="player":
					record.id=1 if kind=="crow" else 46
					online.npcs.assign([record])
				else:online.players.assign([peer])
				var labels: Node=game.nameplates
				labels.inspected_key="npc:1" if kind!="player" else "player:101";labels.inspected_until=Time.get_ticks_msec()+60000;labels.inspected_map=-1
				game.player_world=game.tile_position(Vector2i(20,20))
				game.camera.zoom=Vector2(zoom,zoom);game.camera.position=game.tile_position(Vector2i(40,40))-Vector2(0,48)
				var clear: Image=await capture(view,game)
				if kind=="guild_bob" and scale_factor==1.5 and zoom==1.65:clear.save_png("res://../work/classic-guild-name-clear.png")
				check(labels.entries.size()==1,"Clear inspected label is whole and visible")
				if kind=="guild_bob":
					game.obscure_name=true
					var over_scenery: Image=await capture(view,game)
					if scale_factor==1.5 and zoom==1.65:over_scenery.save_png("res://../work/classic-guild-name-scenery.png")
					var entry: Dictionary=labels.entries[0]
					var to_pixels: Transform2D=view.get_final_transform()*labels.get_global_transform_with_canvas()
					var bounds: Rect2i=Rect2i(to_pixels*Rect2((entry.baseline as Vector2)-Vector2(0,ThemeDB.fallback_font.get_ascent(int(entry.font_size))),Vector2(float(entry.width),ThemeDB.fallback_font.get_height(int(entry.font_size)))))
					bounds=bounds.intersection(Rect2i(Vector2i.ZERO,clear.get_size()))
					var glyph_pixels: int=0;var lost_pixels: int=0
					for y: int in range(bounds.position.y,bounds.end.y):
						for x: int in range(bounds.position.x,bounds.end.x):
							var color: Color=clear.get_pixel(x,y)
							if color.r>.85 and color.g>.85 and color.b>.75 and color.a>.99:
								glyph_pixels+=1
								var actual: Color=over_scenery.get_pixel(x,y)
								if actual.r<.80 or actual.g<.80 or actual.b<.70:lost_pixels+=1
					check(glyph_pixels>0 and lost_pixels==0,"Scenery never cuts or flickers inspected glyphs")
					scenery_checks+=1;game.obscure_name=false
				game.player_world=game.tile_position(Vector2i(40,40) if kind=="crow" else Vector2i(39,39))
				var combined: Image=await capture(view,game)
				if kind=="guild_bob" and scale_factor==1.5 and zoom==1.65:combined.save_png("res://../work/classic-guild-name-blocked.png")
				check(labels.entries.is_empty(),"Name disappears completely when it overlaps a character")
				var actors: Image=await capture(view,game,false)
				check(combined.get_data()==actors.get_data(),"Rendered collision leaves no floating name fragments")
				# A one-pixel clearance does not immediately re-enable a hidden name.
				game.player_world+=Vector2(.1,.1);await capture(view,game)
				check(labels.entries.is_empty(),"Subpixel movement does not flicker the blocked name")
				game.player_world=game.tile_position(Vector2i(20,20));await capture(view,game)
				check(labels.entries.size()==1,"Whole name returns after the other character clears it")
				results.append({"kind":kind,"display_scale":scale_factor,"zoom":zoom,"no_fragments":true,"clearance_hysteresis":true})
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"real_world_pipeline":true,"scenery_checks":scenery_checks,"pixel_render_test":DisplayServer.get_name()!="headless","cases":results}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("NAMEPLATE OCCLUSION: ",JSON.stringify(report));online.active=false;view.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
