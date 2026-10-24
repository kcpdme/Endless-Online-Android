extends SceneTree
# Exercise the real main.gd draw pipeline with real Classic character artwork.
class WorldProbe extends "res://scripts/main.gd":
	var show_actor: bool = true
	var show_sprites: bool = true
	func _draw_character_frame(character: Dictionary, at: Vector2, direction: String, state: String, tint: Color = Color.WHITE, phase: float = -1.0) -> bool:
		if not show_sprites: return true
		return super._draw_character_frame(character,at,direction,state,tint,phase)
	func _draw_player() -> void:
		if show_actor: super._draw_player()
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed=true; push_error(message)
func capture(view: SubViewport, game: Node, captions: bool = true) -> Image:
	game.nameplates.sync();game.nameplates.visible=captions;game.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func channel_delta(a: Color, b: Color) -> int:
	# Allow one 8-bit rounding step at antialiased/blended edges.
	return roundi(255.0*maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),maxf(absf(a.b-b.b),absf(a.a-b.a))))
func run() -> void:
	var view: SubViewport=SubViewport.new();view.size=Vector2i(600,360);view.transparent_bg=true;view.world_2d=World2D.new();view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var game: WorldProbe=WorldProbe.new();view.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop()
	game.started=true;game.online_mode=true;game.menu.hide();game.welcome.hide();game.online.panel.hide()
	for child: Node in game.hud_root.get_children():
		if child is Control and child!=game.nameplates:child.hide();child.set_process(false)
	game.nameplates.set_process(false);game.world={};game.decorations.clear();game.ground.clear()
	var online: Node=game.online;online.active=true
	online.player={"player_id":100,"gender":1,"race":0,"hairstyle":1,"haircolor":0,"equipment_graphics":[1,0,0,0,1,0,0,0,0]}
	var record: Dictionary={"id":1,"index":1,"x":40,"y":40,"direction":0}
	var peer: Dictionary=online.player.duplicate();peer.merge({"player_id":101,"x":40,"y":40,"direction":0,"name":"Nearby player"},true)
	var results: Array[Dictionary]=[]
	for scale_factor: float in [1.0,1.5]:
		view.size=Vector2i(Vector2(400,240)*scale_factor);view.size_2d_override=Vector2i(400,240);view.size_2d_override_stretch=true
		for kind: String in ["crow","player"]:
			for zoom: float in [1.0,1.65,2.5]:
				online.npcs.clear();online.players.clear();online.render_pose_cache.clear()
				if kind=="crow":online.npcs.assign([record])
				else:online.players.assign([peer])
				game.player_tile=Vector2i(40,40) if kind=="crow" else Vector2i(39,40)
				game.player_world=game.tile_position(game.player_tile)
				game.camera.zoom=Vector2(zoom,zoom);game.camera.position=game.tile_position(Vector2i(40,40))-Vector2(0,48)
				game.show_actor=false;game.show_sprites=false
				var labels: Image=await capture(view,game)
				check(game.nameplates.entries.size()==1,"One caption in overlap fixture")
				var entry: Dictionary=game.nameplates.entries[0]
				var transform: Transform2D=view.get_final_transform()*game.nameplates.get_global_transform_with_canvas()
				var baseline: Vector2=entry.baseline
				var width: float=ThemeDB.fallback_font.get_string_size(entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry.font_size)).x
				var bounds: Rect2i=Rect2i(transform*Vector2(baseline.x-2,baseline.y-ThemeDB.fallback_font.get_ascent(int(entry.font_size))-2),transform.basis_xform(Vector2(width+4,ThemeDB.fallback_font.get_height(int(entry.font_size))+4)))
				bounds=bounds.intersection(Rect2i(Vector2i.ZERO,labels.get_size()))
				game.show_actor=true;game.show_sprites=true
				var actor: Image=await capture(view,game,false)
				var combined: Image=await capture(view,game)
				var covered: int=0;var exposed: int=0;var incorrect: int=0;var max_delta: int=0
				for y: int in range(bounds.position.y,bounds.end.y):
					for x: int in range(bounds.position.x,bounds.end.x):
						var label: Color=labels.get_pixel(x,y);var body: Color=actor.get_pixel(x,y)
						if label.a<.1:continue
						if body.a>.999:
							covered+=1
							var delta: int=channel_delta(combined.get_pixel(x,y),body);max_delta=maxi(max_delta,delta)
							if delta>1:incorrect+=1
						elif body.a<.001:
							exposed+=1
							var delta: int=channel_delta(combined.get_pixel(x,y),label);max_delta=maxi(max_delta,delta)
							if delta>1:incorrect+=1
				check(covered>0,"Real actor overlaps "+kind+" caption at zoom "+str(zoom))
				check(incorrect==0,"Actor covers caption only inside its silhouette: "+kind+" / "+str(zoom))
				results.append({"kind":kind,"display_scale":scale_factor,"zoom":zoom,"covered_caption_pixels":covered,"exposed_caption_pixels":exposed,"incorrect_pixels":incorrect,"max_channel_delta":max_delta})
				if scale_factor==1.5 and zoom==1.65:combined.save_png("res://../work/nameplate-occlusion-"+kind+".png")
	var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"real_world_pipeline":true,"pixel_render_test":DisplayServer.get_name()!="headless","cases":results}
	var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("NAMEPLATE OCCLUSION: ",JSON.stringify(report));online.active=false;view.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
