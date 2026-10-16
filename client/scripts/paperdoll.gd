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
	var texture: Texture2D = game._texture(str(frame.get("path", "")))
	if texture == null: return
	var region_data: Array = frame.get("region", [0, 0, texture.get_width(), texture.get_height()]) as Array
	var region: Rect2 = Rect2(float(region_data[0]), float(region_data[1]), float(region_data[2]), float(region_data[3]))
	var scale_factor: float = 2.30
	var at: Vector2 = Vector2(size.x / 2.0, size.y - 6.0)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 29.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO)
	var offset_data: Array = frame.get("offset", [0, 0]) as Array
	var offset: Vector2 = Vector2(float(offset_data[0]), float(offset_data[1])) * scale_factor
	var dimensions: Vector2 = region.size * scale_factor
	# Subtle idle motion keeps the preview alive without inventing extra sprite frames.
	at.y += sin(preview_clock * 2.0) * 0.6
	draw_texture_rect_region(texture, Rect2(at + offset - Vector2(dimensions.x / 2.0, dimensions.y), dimensions), region)

func turn() -> void:
	var sequence: Array[String] = ["south", "west", "north", "east"]
	direction = sequence[(sequence.find(direction) + 1) % sequence.size()]
	queue_redraw()
