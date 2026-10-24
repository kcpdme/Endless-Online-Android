extends Control
## Classic inspect labels with screen-resolution, physically aligned glyphs.
const INSPECT_MSEC: int = 3000
var game: Node
var entries: Array[Dictionary] = []
var widths: Dictionary = {}
var frame_bounds: Dictionary = {}
var frame_images: Dictionary = {}
var frame_cache_map: int = -2147483648
var inspected_key: String = ""
var inspected_until: int = 0
var inspected_map: int = -1
var hover_screen: Vector2 = Vector2.ZERO
var hovering: bool = false
var obstructed_key: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	process_priority = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		hover_screen = event.position
		hovering = true
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		hovering = false

func _process(_delta: float) -> void:
	sync()

func inspect_world(point: Vector2) -> void:
	hovering = false
	inspected_key = _hit_actor(_actors(), point)
	inspected_until = Time.get_ticks_msec() + INSPECT_MSEC
	inspected_map = int(game.world.get("id", -1))

func pixel_aligned(point: Vector2) -> Vector2:
	var to_pixels: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return to_pixels.affine_inverse() * (to_pixels * point).round()

func _actors() -> Array[Dictionary]:
	var actors: Array[Dictionary] = []
	var online: Node = game.online
	for record: Dictionary in online.npcs:
		var pose: Dictionary = online.entity_render_pose("online_npc", record)
		var graphic: Dictionary = online.npc_graphic(record)
		if not online.npc_pose_visible(graphic, str(pose.state)): continue
		var info: Dictionary = (online.catalog.get("npcs", {}) as Dictionary).get(str(int(record.id)), {})
		var layout: Dictionary = online.npc_name_layout(graphic, str(pose.direction), false)
		actors.append({"key":"npc:%d" % int(record.index), "id":-int(record.index), "text":str(info.get("name", "NPC")), "pose":pose, "graphic":graphic, "top":layout.classic_top, "font":maxi(1,roundi(10.5*game.camera.zoom.x)), "color":game.TEXT, "health":online.npc_health_fraction(int(record.index)), "sort":game.depth(Vector2i(int(record.x),int(record.y)))*100+70})
	var own_id: int = int(online.player.get("player_id", -1))
	for record: Dictionary in [online.player] + online.players:
		var pid: int = int(record.get("player_id", -1))
		if pid < 0 or (record != online.player and pid == own_id): continue
		var local: bool = pid == own_id
		var pose: Dictionary
		if local:
			var state: String = "frames" if game.moving else "cast" if game.skills_ui.is_chanting(pid) else "attack" if game.swing_clock>0.0 else "idle"
			if online.seated(): state = "sit_chair" if int(online.player.sitting)==1 else "sit_floor"
			pose = {"position":game.player_world, "direction":game.facing, "state":state, "phase":game.ONLINE_ATTACK_SWING_DURATION-game.swing_clock if state=="attack" else game.animation_clock}
		else: pose = online.entity_render_pose("online_player",record)
		# Classic player labels sit above the stable standing body, not equipment.
		var top: Vector2 = Vector2(0, -82 if not str(pose.state).begins_with("sit_") else -72)
		actors.append({"key":"player:%d" % pid, "id":pid, "text":str(record.get("name", "")), "pose":pose, "graphic":online.character_graphic(record), "top":top, "font":maxi(1,roundi(11.0*game.camera.zoom.x)), "color":Color("b9e2c5"), "health":-1.0, "sort":game.depth(game._world_tile(pose.position))*100+(30 if local else 55)})
	return actors

func _frame_parts(actor: Dictionary, standing: bool = false) -> Array:
	var pose: Dictionary = actor.pose
	var frame: Dictionary = game._frame(actor.graphic, str(pose.direction), "idle" if standing else str(pose.state), 0.0 if standing else float(pose.phase))
	return frame.get("layers", [frame]) if not frame.is_empty() else []

func _image(path: String) -> Image:
	if not frame_images.has(path):
		var texture: Texture2D = game._texture(path)
		if texture == null: return null
		frame_images[path] = texture.get_image()
	return frame_images[path] as Image

func _part_rect(part: Dictionary, at: Vector2) -> Rect2:
	var region: Array = part.region
	var size: Vector2 = Vector2(float(region[2]),float(region[3])) / maxf(1.0,float(part.get("pixel_scale",1)))
	return Rect2(at+Vector2(float(part.offset[0]),float(part.offset[1]))-Vector2(size.x/2.0,size.y),size)

func _hit_actor(actors: Array[Dictionary], point: Vector2) -> String:
	var key: String = ""
	var front: int = -2147483648
	for actor: Dictionary in actors:
		if int(actor.sort) < front: continue
		for part: Dictionary in _frame_parts(actor):
			var rect: Rect2 = _part_rect(part, actor.pose.position)
			if not rect.has_point(point): continue
			var image: Image = _image(str(part.path))
			if image == null: continue
			var pixel: Vector2i = Vector2i((point-rect.position)*maxf(1.0,float(part.get("pixel_scale",1))))+Vector2i(int(part.region[0]),int(part.region[1]))
			if image.get_pixelv(pixel).a>.1: key=str(actor.key);front=int(actor.sort);break
	return key

func _actor_bounds(actor: Dictionary) -> Rect2:
	var bounds: Rect2 = Rect2()
	# Standing bounds stabilize walks; include current art for extended attacks.
	for part: Dictionary in _frame_parts(actor, true)+_frame_parts(actor):
		var cache_key: String = JSON.stringify(part)
		if not frame_bounds.has(cache_key):
			var used: Rect2
			if part.has("visible_bounds"):
				var visible_pixels: Array = part.visible_bounds
				used=Rect2(float(visible_pixels[0]),float(visible_pixels[1]),float(visible_pixels[2]),float(visible_pixels[3]))
			else:
				var image: Image = _image(str(part.path))
				if image == null: continue
				var r: Array = part.region
				used=Rect2(image.get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))).get_used_rect())
			var scale_factor: float = maxf(1.0,float(part.get("pixel_scale",1)))
			frame_bounds[cache_key] = Rect2(_part_rect(part,Vector2.ZERO).position+used.position/scale_factor,used.size/scale_factor)
		var relative: Rect2 = frame_bounds[cache_key]
		if not relative.has_area(): continue
		var at: Rect2 = Rect2(relative.position+(actor.pose.position as Vector2),relative.size)
		bounds = bounds.merge(at) if bounds.has_area() else at
	return bounds

func _hover_in_world() -> bool:
	if not hovering: return false
	if get_viewport().gui_get_hovered_control()!=null: return false
	if game.joystick.contains_point(hover_screen) or game.chat_ui.hud_contains(hover_screen) or game.minimap.contains(hover_screen): return false
	for button: Control in [game.attack_button,game.bag_button,game.sit_button,game.chat_button,game.character_button,game.quest_journal.button,game.party_ui.button,game.admin_ui.button]:
		if button.visible and button.contains_point(hover_screen): return false
	return not game.menu_button.get_global_rect().has_point(hover_screen) and game.skills_ui.contains(hover_screen)<0 and game.quick_items.contains(hover_screen)<0

func sync() -> void:
	entries.clear()
	visible = game!=null and game.started and game.online_mode and game.online.active and not game._modal_open()
	if not visible:
		inspected_key="";inspected_until=0;obstructed_key=""
		queue_redraw()
		return
	var map_id: int = int(game.world.get("id",-1))
	if map_id!=frame_cache_map:
		frame_images.clear();frame_bounds.clear();frame_cache_map=map_id
	game.camera.force_update_scroll()
	var world_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse()*game.get_global_transform_with_canvas()
	var actors: Array[Dictionary] = _actors()
	var selected: String = inspected_key if Time.get_ticks_msec()<inspected_until and inspected_map==int(game.world.get("id",-1)) else ""
	if hovering: selected = _hit_actor(actors,game._screen_to_world(hover_screen)) if _hover_in_world() else ""
	for actor: Dictionary in actors:
		var speaking: Dictionary = game.online.chat_bubbles.get(int(actor.id),{})
		var shout: Dictionary = game.online.spell_labels.get(int(actor.id),{})
		var speech_visible: bool = Time.get_ticks_msec()<maxi(int(speaking.get("until",0)),int(shout.get("until",0)))
		var health: float = float(actor.health)
		var text: String = str(actor.text) if str(actor.key)==selected and health<0.0 and not speech_visible else ""
		if text.is_empty() and health<0.0: continue
		var top: Vector2 = world_to_local*((actor.pose.position as Vector2)+(actor.top as Vector2))
		var count: int = entries.size()
		_append(str(actor.key),text,top,int(actor.font),actor.color,health,40.0*game.camera.zoom.x)
		if text.is_empty() or entries.size()==count: continue
		var entry: Dictionary = entries.back()
		var label_rect: Rect2 = Rect2((entry.baseline as Vector2)-Vector2(2,ThemeDB.fallback_font.get_ascent(int(actor.font))+2),Vector2(float(entry.width)+4,ThemeDB.fallback_font.get_height(int(actor.font))+4))
		var blocked: bool = false
		# Require extra clearance before restoring a hidden label, so a moving
		# sprite at the boundary cannot toggle it on and off every pixel.
		label_rect = label_rect.grow(6.0 if obstructed_key==str(actor.key) else 2.0)
		for other: Dictionary in actors:
			if other.key==actor.key: continue
			var body: Rect2 = _actor_bounds(other)
			if body.has_area() and label_rect.intersects(world_to_local*body):
				blocked=true;break
		if blocked:
			entries.pop_back();obstructed_key=str(actor.key)
		elif obstructed_key==str(actor.key): obstructed_key=""
	queue_redraw()

func _append(key: String, text: String, top: Vector2, font_size: int, color: Color, health: float = -1.0, bar_width: float = 0.0) -> void:
	var measurement: String = str(font_size)+":"+text
	if not widths.has(measurement): widths[measurement]=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var baseline: Vector2 = pixel_aligned(top+Vector2(-float(widths[measurement])/2.0,ThemeDB.fallback_font.get_ascent(font_size)))
	if not get_viewport_rect().grow(200).has_point(get_global_transform_with_canvas()*baseline): return
	entries.append({"key":key,"text":text,"baseline":baseline,"font_size":font_size,"color":color,"health":health,"bar_width":bar_width,"anchor":pixel_aligned(top),"width":widths[measurement]})

func _draw() -> void:
	for entry: Dictionary in entries:
		if float(entry.health)>=0.0:
			var top: Vector2 = (entry.anchor as Vector2)-Vector2(float(entry.bar_width)/2.0,0)
			var strip: Rect2 = Rect2(pixel_aligned(top),pixel_aligned(top+Vector2(float(entry.bar_width),7))-pixel_aligned(top))
			draw_rect(strip.grow(1),Color("121b18"));draw_rect(strip,Color("50322e"))
			var edge: Vector2 = pixel_aligned(strip.position+Vector2(strip.size.x*float(entry.health),0))
			draw_rect(Rect2(strip.position,Vector2(edge.x-strip.position.x,strip.size.y)),Color("a6cb6f") if float(entry.health)>.3 else Color("dc6855"))
		if not str(entry.text).is_empty():
			draw_string_outline(ThemeDB.fallback_font,entry.baseline,entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry.font_size),2,Color("15201d"))
			draw_string(ThemeDB.fallback_font,entry.baseline,entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry.font_size),entry.color)
