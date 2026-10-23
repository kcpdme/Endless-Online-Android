extends Control
## Uses the same original appearance layers as characters in the online world.
var game: Node
var appearance: Dictionary = {}
var direction: String = "south"
var zoom: float = 2.0
var bottom_margin: float = 34.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			var directions: Array[String] = ["south", "west", "north", "east"]
			direction = directions[(directions.find(direction) + 1) % 4]
			queue_redraw()
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
	var frame: Dictionary = game._frame(character, direction, "idle")
	var layers: Array = frame.get("layers", [frame]) as Array
	var at: Vector2 = Vector2(size.x / 2.0, size.y - bottom_margin)
	draw_circle(at + Vector2(0, -2), 34, Color(0, 0, 0, 0.18))
	for layer: Dictionary in layers:
		if layer.is_empty(): continue
		var texture: Texture2D = game._texture(str(layer.get("path", "")))
		if texture == null: continue
		var r: Array = layer.region
		var region: Rect2 = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var offset: Array = layer.get("offset", [0, 0])
		var dimensions: Vector2 = region.size * zoom
		draw_texture_rect_region(texture, Rect2(at + Vector2(float(offset[0]), float(offset[1])) * zoom - Vector2(dimensions.x / 2.0, dimensions.y), dimensions), region)
