extends Control
## Rasterize overhead names at HUD resolution, then align only their baselines
## to physical pixels. World sprites and camera retain fractional movement.
var game: Node
var entries: Array[Dictionary] = []
var widths: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = -1 # Above the world CanvasLayer, below HUD controls and dialogs.
	process_priority = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	sync()

func pixel_aligned(point: Vector2) -> Vector2:
	var to_pixels: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return to_pixels.affine_inverse() * (to_pixels * point).round()

func sync() -> void:
	entries.clear()
	visible = game != null and game.started and game.online_mode and game.online.active and not game._modal_open()
	if not visible:
		queue_redraw()
		return
	game.camera.force_update_scroll()
	var world_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse() * game.get_global_transform_with_canvas()
	var online: Node = game.online
	for record: Dictionary in online.npcs:
		var pose: Dictionary = online.entity_render_pose("online_npc",record)
		var graphic: Dictionary = online.npc_graphic(record)
		if not online.npc_pose_visible(graphic,str(pose.state)): continue
		var info: Dictionary = (online.catalog.get("npcs",{}) as Dictionary).get(str(int(record.id)),{}) as Dictionary
		var layout: Dictionary = online.npc_name_layout(graphic,str(pose.direction),false)
		_append("npc:%d" % int(record.index),str(info.get("name","NPC %s" % record.id)),world_to_local * ((pose.position as Vector2)+(layout.name as Vector2)),17,game.TEXT,online.npc_health_fraction(int(record.index)),(layout.health as Rect2).size.x*game.camera.zoom.x)
	for record: Dictionary in online.players:
		if int(record.get("player_id",-1)) == int(online.player.get("player_id",-2)): continue
		var pose: Dictionary = online.entity_render_pose("online_player",record)
		_append("player:%d" % int(record.player_id),str(record.get("name","Player")),world_to_local * ((pose.position as Vector2)+Vector2(0,-66)),18,Color("b9e2c5"))
	queue_redraw()

func _append(key: String, text: String, anchor: Vector2, font_size: int, color: Color, health: float = -1.0, bar_width: float = 0.0) -> void:
	if text.is_empty(): return
	var measurement: String = str(font_size)+":"+text
	if not widths.has(measurement): widths[measurement] = ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var baseline: Vector2 = pixel_aligned(anchor-Vector2(float(widths[measurement])/2.0,0))
	if not get_viewport_rect().grow(200).has_point(get_global_transform_with_canvas()*baseline): return
	entries.append({"key":key,"text":text,"baseline":baseline,"font_size":font_size,"color":color,"health":health,"bar_width":bar_width,"anchor":anchor})

func _draw() -> void:
	for entry: Dictionary in entries:
		if float(entry.health)>=0.0:
			# Keep a clear gap above the screen-sized name at every camera zoom.
			var top: Vector2 = Vector2(float(entry.anchor.x)-float(entry.bar_width)/2.0,float(entry.baseline.y)-ThemeDB.fallback_font.get_ascent(int(entry.font_size))-13)
			var strip: Rect2 = Rect2(pixel_aligned(top),pixel_aligned(top+Vector2(float(entry.bar_width),7))-pixel_aligned(top))
			draw_rect(strip.grow(1),Color("121b18"));draw_rect(strip,Color("50322e"))
			var edge: Vector2 = pixel_aligned(strip.position+Vector2(strip.size.x*float(entry.health),0))
			draw_rect(Rect2(strip.position,Vector2(edge.x-strip.position.x,strip.size.y)),Color("a6cb6f") if float(entry.health)>.3 else Color("dc6855"))
		draw_string_outline(ThemeDB.fallback_font,entry.baseline,entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry.font_size),2,Color("15201d"))
		draw_string(ThemeDB.fallback_font,entry.baseline,entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry.font_size),entry.color)
