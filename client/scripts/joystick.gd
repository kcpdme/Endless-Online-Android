extends Control
## Floating translucent stick. Main captures its finger before world/NPC targeting.
var active: bool = false
var vector: Vector2 = Vector2.ZERO
var direction: Vector2i = Vector2i.ZERO
# Visual thumb travel stays analog; gameplay receives one held keyboard axis.
@export_range(0.0, 40.0, 1.0) var dead_zone_pixels: float = 18.0
@export_range(1.0, 2.0, 0.05) var direction_switch_ratio: float = 1.25
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
	direction = Vector2i.ZERO
	queue_redraw()

func _snap_direction(delta: Vector2) -> Vector2i:
	if delta.length() <= dead_zone_pixels: return Vector2i.ZERO
	var candidate: Vector2i
	if absf(delta.x) > absf(delta.y): candidate = Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
	else: candidate = Vector2i.DOWN if delta.y > 0 else Vector2i.UP
	# Stay on the held key around diagonal boundaries, until the thumb clearly
	# selects the neighbouring axis. A deliberate opposite input switches at once.
	if direction == Vector2i.ZERO or candidate == direction: return candidate
	var held_strength: float = maxf(0.0, delta.dot(Vector2(direction)))
	return candidate if delta.dot(Vector2(candidate)) > held_strength * direction_switch_ratio else direction

func update_pointer(pointer: Vector2) -> Vector2:
	var delta: Vector2 = pointer - pointer_origin
	# Follow a long drag without losing capture or letting the circle leave screen.
	if delta.length() > 84:
		var shift: Vector2 = delta - delta.normalized() * 84
		pointer_origin += shift
		_place_center(global_position + Vector2.ONE * radius + shift)
		delta = delta.normalized() * 84
	vector = (delta / 84).limit_length(1.0) if delta.length() > dead_zone_pixels else Vector2.ZERO
	direction = _snap_direction(delta)
	queue_redraw()
	return Vector2(direction)

func reset() -> void:
	active = false
	vector = Vector2.ZERO
	direction = Vector2i.ZERO
	pointer_origin = Vector2.ZERO
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = Vector2(resting_position.x, (get_parent() as Control).size.y + resting_position.y)
	queue_redraw()
