extends SceneTree
## Compare actual church and NPC pixels after removing whole-pixel camera travel.
class WorldProbe extends "res://scripts/main.gd":
	var probe_frame: Dictionary = {}
	var probe_at: Vector2 = Vector2.ZERO
	var aligned_actor: bool = false
	func _draw() -> void:
		if probe_frame.is_empty(): return
		if aligned_actor:
			_draw_character_frame({"idle":{"south":probe_frame}},probe_at,"south","idle",Color.WHITE,0.0)
		else:
			for part: Dictionary in probe_frame.get("layers",[probe_frame]): _paint_character_frame(part,probe_at,Color.WHITE)
var checks: int = 0
var failed: bool = false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
# Allow at most two 8-bit channel levels for GPU float/alpha-edge rounding.
# Search only whole-pixel translations; any resampling or changing texel widths still fails.
func stable_crop(image: Image, used: Rect2i, reference: Image, size: Vector2i) -> int:
	for shift: Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		var candidate: Image = image.get_region(Rect2i(used.position-Vector2i(4,4)+shift,size))
		var maximum: int = int(candidate.compute_image_metrics(reference,false)["max"])
		if maximum<=2:return maximum
	return 255
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(DisplayServer.get_name() != "headless", "This acceptance requires actual rendered pixels")
	if failed: quit(1); return
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(640,800); view.transparent_bg = true; view.world_2d = World2D.new(); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var game: WorldProbe = WorldProbe.new(); view.add_child(game); await process_frame
	game.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	game.set_process(false); game.online.set_process(false); game.online.session.set_process(false); game.music.stop(); game.hud_root.hide()
	game.nameplates.set_process(false)
	var camera: Camera2D = game.camera; camera.set_process(false)
	var church: Texture2D = game._graphic(6,342)
	var sources: Dictionary = {
		"church_window":{"path":"res://content/gfx/006_00342.png","region":[0,0,church.get_width(),church.get_height()],"offset":[0,0]},
		"stationary_npc":game._frame(game.online.npc_graphic({"id":127}),"south","idle",0.0),
		"followed_player":game._frame(game._active_hero(),"south","idle",0.0)}
	if game.npc_art.ready():
		for gid:String in ["134","154"]:
			sources["enhanced_npc_"+gid]=game._frame(game.npc_art.enhanced[gid],"south","idle",0.0)
	var results: Array[Dictionary] = []
	var reproduced: bool = false
	for key: String in sources:
		game.probe_frame = sources[key]
		check(not game.probe_frame.is_empty(),"Actual source artwork is available")
		for display_scale: float in [1.0,1.25,1.5]:
			view.size = Vector2i(Vector2(640,800)*display_scale); view.size_2d_override = Vector2i(640,800); view.size_2d_override_stretch = true
			await process_frame; await process_frame
			for zoom: float in [1.0,1.65,2.5]:
				camera.zoom = Vector2(zoom,zoom)
				var variants: Dictionary = {}
				for aligned: bool in [false,true]:
					var images: Dictionary = {}
					var reference: Image
					var reference_rect: Rect2i
					var unstable_frames: int = 0
					var max_delta: int = 0
					for phase: int in range(24):
						var origin: Vector2 = Vector2(1376,2192)
						var target: Vector2 = origin+Vector2(phase/24.0,phase/48.0)
						game.probe_at = Vector2(22,110 if key=="church_window" else 14) + (target if key=="followed_player" else origin)
						game.aligned_actor = aligned and key!="church_window"
						game.queue_redraw()
						camera.position = target; camera.offset = Vector2(3.14,-2.71); camera.force_update_scroll()
						var before_alignment: Vector2 = (view.get_final_transform()*view.get_canvas_transform()).origin
						if aligned: camera.align_to_display_pixels()
						var pixels: Transform2D = view.get_final_transform()*view.get_canvas_transform()
						if aligned:
							check((pixels.origin-camera.PIXEL_PHASE).distance_to((pixels.origin-camera.PIXEL_PHASE).round())<.002,"Camera aligns after device scaling, zoom and quake offset")
							check(pixels.origin.distance_to(before_alignment)<=.710,"Render adjustment stays within half a display pixel per axis")
						await process_frame; await RenderingServer.frame_post_draw
						var image: Image = view.get_texture().get_image(); var used: Rect2i = image.get_used_rect()
						check(used.has_area() and used.position.x>0 and used.position.y>0 and used.end.x<image.get_width() and used.end.y<image.get_height(),"Complete source texture renders without viewport clipping")
						var data: PackedByteArray = image.get_region(used.grow(4)).get_data()
						images[str(used.size)+data.hex_encode()] = true
						if reference==null: reference_rect=used.grow(4); reference=image.get_region(reference_rect)
						var difference: int = stable_crop(image,used,reference,reference_rect.size)
						max_delta = maxi(max_delta,difference)
						if difference>2: unstable_frames+=1

					variants["aligned" if aligned else "original"] = images.size()
					if aligned: variants["max_aligned_channel_delta"] = max_delta
					else: variants["unstable_original_frames"] = unstable_frames
				check(int(variants.max_aligned_channel_delta)<=2,"Static artwork keeps identical pixels through fractional camera movement: "+str([key,display_scale,zoom,variants]))
				reproduced = reproduced or int(variants.unstable_original_frames)>0
				results.append({"source":key,"display_scale":display_scale,"zoom":zoom,"distinct_original_images":variants.original,"distinct_aligned_images":variants.aligned,"max_aligned_channel_delta":variants.max_aligned_channel_delta,"unstable_original_frames":variants.unstable_original_frames})
	check(reproduced,"Original camera reproduces changing static texture pixels")
	var report: Dictionary = {"result":"failed" if failed else "passed","checks":checks,"rendered_cases":results,"original_shimmer_reproduced":reproduced,"phases_per_case":24}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty():var file: FileAccess = FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n")
	print("WORLD SAMPLING: ",JSON.stringify(report));view.queue_free();await process_frame;quit(1 if failed else 0)
