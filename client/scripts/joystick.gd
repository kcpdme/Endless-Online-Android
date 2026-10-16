extends Control
## Draw-only floating stick. Main owns pointer capture so a second finger can attack.
var active: bool = false
var vector: Vector2 = Vector2.ZERO
var radius: float = 110.0
var resting_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(radius * 2.0, radius * 2.0)

func _draw() -> void:
	if not active: return
	var center: Vector2 = Vector2.ONE * radius
	var opacity: float = 0.85 if active else 0.70
	draw_circle(center, radius, Color(0.04, 0.10, 0.11, 0.21 * opacity))
	draw_arc(center, radius - 2.0, 0.0, TAU, 64, Color(0.88, 0.93, 0.81, 0.55 * opacity), 2.0, true)
	draw_arc(center, 66.0, 0.0, TAU, 64, Color(0.88, 0.93, 0.81, 0.16 * opacity), 1.0, true)
	for axis: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + axis * 85.0, center + axis * 94.0, Color(0.90, 0.93, 0.84, 0.45 * opacity), 2.0, true)
	var knob: Vector2 = center + vector * 76.0
	draw_circle(knob, 34.0, Color(0.77, 0.85, 0.75, 0.26 if active else 0.16))
	draw_arc(knob, 34.0, 0.0, TAU, 48, Color(0.93, 0.95, 0.86, 0.70 if active else 0.35), 1.5, true)

func begin(center: Vector2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = get_parent().get_global_transform_with_canvas().affine_inverse() * center - Vector2.ONE * radius
	active = true
	vector = Vector2.ZERO
	queue_redraw()

func update_pointer(pointer: Vector2) -> Vector2:
	var displacement: Vector2 = pointer - (global_position + Vector2.ONE * radius)
	# Slide the base with a long drag, retaining a maximum thumb travel of 84 px.
	if displacement.length() > 84.0:
		var shift: Vector2 = displacement - displacement.normalized() * 84.0
		position += shift
		displacement = displacement.normalized() * 84.0
	vector = (displacement / 84.0).limit_length(1.0)
	queue_redraw()
	return vector if displacement.length() > 16.0 else Vector2.ZERO

func reset() -> void:
	active = false
	vector = Vector2.ZERO
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = Vector2(resting_position.x, (get_parent() as Control).size.y + resting_position.y)
	queue_redraw()
