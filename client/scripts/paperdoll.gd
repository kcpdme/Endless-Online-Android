extends Control
## Live preview uses exactly the same precomposed appearance as the world character.
var game: Node
var direction: String = "south"
var preview_clock: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	preview_clock += delta
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	if game == null: return
	var source: Dictionary = game._active_hero()
	var frame: Dictionary = game._frame(source, direction, "idle")
	if frame.is_empty(): return
	var scale_factor: float = 2.30
	var at: Vector2 = Vector2(size.x / 2.0, size.y - 6.0)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 29.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO)
	for part: Dictionary in frame.get("layers", [frame]):
		var texture: Texture2D = game._texture(str(part.get("path", "")))
		if texture == null: continue
		var r: Array = part.get("region", [0, 0, texture.get_width(), texture.get_height()]) as Array
		var region: Rect2 = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var o: Array = part.get("offset", [0, 0]) as Array
		var offset: Vector2 = Vector2(float(o[0]), float(o[1])) * scale_factor
		var dimensions: Vector2 = region.size * scale_factor
		draw_texture_rect_region(texture, Rect2(at + offset - Vector2(dimensions.x / 2.0, dimensions.y), dimensions), region)

func turn() -> void:
	var sequence: Array[String] = ["south", "west", "north", "east"]
	direction = sequence[(sequence.find(direction) + 1) % sequence.size()]
	queue_redraw()
