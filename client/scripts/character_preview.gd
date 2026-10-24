extends Control
## Uses the same original appearance layers as characters in the online world.
var game: Node
var appearance: Dictionary = {}
var direction: String = "south"
var art_cache: Dictionary = {}
var fit_to_rect: bool = false
var rendered_bounds: Rect2 = Rect2()
var zoom: float = 2.0
var bottom_margin: float = 34.0
var pose: String = "idle"
var animate: bool = false
var animation_phase: float = -1.0

func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree(): return
	animation_phase = fposmod(maxf(0,animation_phase) + delta,.4 if pose == "frames" else .48)
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			turn(1)
			accept_event()
	)

func appearance_record() -> Dictionary:
	var record: Dictionary = appearance.duplicate()
	var graphics: Array = record.get("equipment_graphics",[]) as Array
	if graphics.size() == 5:
		# Login BAHSW -> world B...A.HSW appearance order.
		record.equipment_graphics = [graphics[0],0,0,0,graphics[1],0,graphics[2],graphics[3],graphics[4]]
	elif graphics.size() != 9: record.equipment_graphics = [0,0,0,0,0,0,0,0,0]
	return record

func _draw() -> void:
	if game == null: return
	var character: Dictionary = game.online.character_graphic(appearance_record())
	var frame: Dictionary = game._frame(character,direction,pose,animation_phase)
	var layers: Array = frame.get("layers",[frame]) as Array
	var visible_layers: Array[Dictionary] = []
	var bounds: Rect2 = Rect2()
	var first: bool = true
	for layer: Dictionary in layers:
		if layer.is_empty(): continue
		var texture: Texture2D = game._texture(str(layer.get("path","")))
		if texture == null: continue
		var r: Array = layer.region
		var source: Rect2 = Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
		var key: String = str(layer.get("path",""))+str(r)
		if not art_cache.has(key):
			var image: Image = texture.get_image()
			art_cache[key] = Rect2(image.get_region(Rect2i(source)).get_used_rect()) if image != null and not image.is_empty() else Rect2(Vector2.ZERO,source.size)
		var used: Rect2 = art_cache[key]
		if not used.has_area(): continue
		var offset: Array = layer.get("offset",[0,0])
		var pixel_scale: float = maxf(1.0, float(layer.get("pixel_scale", 1)))
		var rectangle: Rect2 = Rect2(game._frame_rectangle(layer,source.size).position+used.position/pixel_scale,used.size/pixel_scale)
		bounds = rectangle if first else bounds.merge(rectangle); first = false
		visible_layers.append({"texture":texture,"source":Rect2(source.position+used.position,used.size),"rectangle":rectangle})
	var scale: float = zoom
	if fit_to_rect and bounds.has_area():
		scale = minf(zoom,minf(maxf(1,size.x-32)/bounds.size.x,maxf(1,size.y-bottom_margin-16)/bounds.size.y))
	var at: Vector2 = Vector2(size.x/2.0,size.y-bottom_margin)
	if fit_to_rect:
		at.x -= bounds.get_center().x*scale
		at.y -= maxf(0,bounds.end.y)*scale
	rendered_bounds = Rect2(at+bounds.position*scale,bounds.size*scale)
	draw_circle(at+Vector2(0,-2),34,Color(0,0,0,0.18))
	for layer: Dictionary in visible_layers:
		var rectangle: Rect2 = layer.rectangle
		draw_texture_rect_region(layer.texture,Rect2(at+rectangle.position*scale,rectangle.size*scale),layer.source)

func turn(step: int) -> void:
	var directions: Array[String] = ["south","west","north","east"]
	direction = directions[posmod(directions.find(direction)+step,directions.size())]
	queue_redraw()
