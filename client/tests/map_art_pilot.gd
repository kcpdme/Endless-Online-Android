extends SceneTree
## Offline environment-only comparison. Does not load a live account or ship art.
class Pilot extends "res://scripts/main.gd":
	var enhanced:bool=false
	var pilot_graphics:Dictionary={}
	var pilot_cache:Dictionary={}
	func _draw_player()->void:pass
	func _graphic(gfx:int, ident:int)->Texture2D:
		var key:String="%d:%d"%[gfx,ident]
		if not enhanced or not pilot_graphics.has(key):return super._graphic(gfx,ident)
		if pilot_cache.has(key):return pilot_cache[key]
		var row:Dictionary=pilot_graphics[key]
		var pixels:Image=Image.load_from_file(str(row.path))
		var texture:ImageTexture=ImageTexture.create_from_image(pixels)
		texture.set_size_override(Vector2i(int(row.native_size[0]),int(row.native_size[1])))
		var filtered:CanvasTexture=CanvasTexture.new();filtered.diffuse_texture=texture
		filtered.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST if bool(row.get("floor",false)) else CanvasItem.TEXTURE_FILTER_LINEAR
		assert(filtered.get_size()==Vector2(row.native_size[0],row.native_size[1]),"Map geometry must retain native texture dimensions")
		pilot_cache[key]=filtered
		return filtered
var game:Pilot
func _initialize()->void:call_deferred("run")
func capture(path:String)->void:
	game.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
func run()->void:
	var folder:String=OS.get_environment("ASTER_VALE_MAP_PILOT")
	assert(not folder.is_empty() and DisplayServer.get_name()!="headless")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("preview.json")))
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1920,1080)
	game=Pilot.new();root.add_child(game);await process_frame
	game.set_process(false);game.online.set_process(false);game.online.session.set_process(false);game.music.stop();game.music.enabled=false
	game.pilot_graphics=data.graphics;game.load_map(int(data.report.map_id));game.started=true;game.online_mode=true
	game.player_tile=Vector2i(9,7);game.player_world=game.tile_position(game.player_tile);game.camera.position=game.player_world
	game.camera.zoom=Vector2.ONE*1.65;game.camera.align_to_display_pixels();game.ui.hide();game.time_alive=0;game.animation_clock=0
	await capture(folder.path_join("original.png"))
	game.enhanced=true;await capture(folder.path_join("smoothed.png"))
	# Show the same close view in both modes so the changed edges are assessable.
	root.size=Vector2i(1280,720);await process_frame;game.camera.zoom=Vector2.ONE*3.3;game.camera.position=game.tile_position(Vector2i(8,5));game.camera.align_to_display_pixels()
	game.enhanced=false;await capture(folder.path_join("detail-original.png"))
	game.enhanced=true;await capture(folder.path_join("detail-smoothed.png"))
	print("MAP ART PILOT: ",JSON.stringify(data.report))
	game.queue_free();await process_frame;quit()
