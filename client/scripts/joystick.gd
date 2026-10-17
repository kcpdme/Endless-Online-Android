extends Control
## Floating translucent stick. Main captures its finger before world/NPC targeting.
var active: bool = false
var vector: Vector2 = Vector2.ZERO
var radius: float = 128.0
var resting_position: Vector2 = Vector2(24, -282)
var pointer_origin: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	size = Vector2.ONE * radius * 2.0
	reset()

func activation_area() -> Rect2:
	var bounds: Rect2 = (get_parent() as Control).get_global_rect()
	return Rect2(bounds.position + Vector2(12, bounds.size.y - 356), Vector2(344, 344))

func contains_point(pointer: Vector2) -> bool:
	return activation_area().has_point(pointer)

func _draw() -> void:
	var center: Vector2 = Vector2.ONE * radius
	draw_circle(center, radius - 2, Color(0.035, 0.085, 0.09, 0.34 if active else 0.20))
	draw_arc(center, radius - 3, 0, TAU, 64, Color(0.84, 0.90, 0.83, 0.52 if active else 0.30), 2, true)
	draw_arc(center, 76, 0, TAU, 64, Color(0.84, 0.90, 0.83, 0.14), 1, true)
	var knob: Vector2 = center + vector * 76
	draw_circle(knob, 42, Color(0.77, 0.85, 0.75, 0.30 if active else 0.15))
	draw_arc(knob, 42, 0, TAU, 48, Color(0.93, 0.95, 0.86, 0.70 if active else 0.32), 1.5, true)

func _place_center(center: Vector2) -> void:
	var bounds: Rect2 = (get_parent() as Control).get_global_rect().grow(-radius - 12)
	var safe: Vector2 = Vector2(clampf(center.x, bounds.position.x, bounds.end.x), clampf(center.y, bounds.position.y, bounds.end.y))
	position = get_parent().get_global_transform_with_canvas().affine_inverse() * safe - Vector2.ONE * radius

func begin(pointer: Vector2) -> void:
	active = true
	pointer_origin = pointer
	_place_center(pointer)
	vector = Vector2.ZERO
	queue_redraw()

func update_pointer(pointer: Vector2) -> Vector2:
	var delta: Vector2 = pointer - pointer_origin
	# Follow a long drag without losing capture or letting the circle leave screen.
	if delta.length() > 84:
		var shift: Vector2 = delta - delta.normalized() * 84
		pointer_origin += shift
		_place_center(global_position + Vector2.ONE * radius + shift)
		delta = delta.normalized() * 84
	vector = (delta / 84).limit_length(1.0) if delta.length() > 18 else Vector2.ZERO
	queue_redraw()
	return vector

func reset() -> void:
	active = false
	vector = Vector2.ZERO
	pointer_origin = Vector2.ZERO
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = Vector2(resting_position.x, (get_parent() as Control).size.y + resting_position.y)
	queue_redraw()
