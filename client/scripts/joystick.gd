extends Control
## Four native tile directions with floating/fixed bases and optional isometric steering.
var active: bool = false
var vector: Vector2 = Vector2.ZERO
var direction: Vector2i = Vector2i.ZERO
@export_range(0.0, 40.0, 1.0) var dead_zone_pixels: float = 14.0
@export_range(0.0, 40.0, 1.0) var release_zone_pixels: float = 10.0
@export_range(1.0, 2.0, 0.05) var direction_switch_ratio: float = 1.20
const INPUT_RADIUS: float = 64.0
const SETTINGS_PATH: String = "user://movement_controls.cfg"
var isometric: bool = false
var fixed_base: bool = false
var radius: float = 128.0
var resting_position: Vector2 = Vector2(24, -282)
var pointer_origin: Vector2 = Vector2.ZERO
var visual_origin_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	size = Vector2.ONE * radius * 2.0
	load_preferences()
	reset()

func load_preferences(path: String = SETTINGS_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK: return
	var mapping: Variant = config.get_value("joystick", "isometric", false)
	var base: Variant = config.get_value("joystick", "fixed_base", false)
	isometric = mapping if mapping is bool else false
	fixed_base = base if base is bool else false

func set_preferences(screen_directions: bool, fixed: bool, path: String = SETTINGS_PATH) -> void:
	isometric = screen_directions; fixed_base = fixed
	reset()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("joystick", "isometric", isometric)
	config.set_value("joystick", "fixed_base", fixed_base)
	config.save(path)

func activation_area() -> Rect2:
	var bounds: Rect2 = (get_parent() as Control).get_global_rect()
	return Rect2(bounds.position + Vector2(12, bounds.size.y - 356), Vector2(344, 344))

func contains_point(pointer: Vector2) -> bool:
	return activation_area().has_point(pointer)

func _display_direction(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - tile.y) * 2.0, tile.x + tile.y).normalized() if isometric else Vector2(tile)

func _draw() -> void:
	var center: Vector2 = Vector2.ONE * radius
	draw_circle(center, radius - 2, Color(0.035, 0.085, 0.09, 0.34 if active else 0.20))
	draw_arc(center, radius - 3, 0, TAU, 64, Color(0.84, 0.90, 0.83, 0.52 if active else 0.30), 2, true)
	draw_arc(center, 76, 0, TAU, 64, Color(0.84, 0.90, 0.83, 0.14), 1, true)
	for tile: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var ray: Vector2 = _display_direction(tile)
		draw_line(center + ray * 97, center + ray * 109, Color(0.91, 0.78, 0.52, 0.85) if active and direction == tile else Color(0.84, 0.90, 0.83, 0.13), 5 if active and direction == tile else 2, true)
	var knob: Vector2 = center + vector * INPUT_RADIUS
	draw_circle(knob, 42, Color(0.77, 0.85, 0.75, 0.30 if active else 0.15))
	draw_arc(knob, 42, 0, TAU, 48, Color(0.93, 0.95, 0.86, 0.70 if active else 0.32), 1.5, true)

func _place_center(center: Vector2) -> void:
	var bounds: Rect2 = (get_parent() as Control).get_global_rect().grow(-radius - 12)
	var safe: Vector2 = Vector2(clampf(center.x, bounds.position.x, bounds.end.x), clampf(center.y, bounds.position.y, bounds.end.y))
	position = get_parent().get_global_transform_with_canvas().affine_inverse() * safe - Vector2.ONE * radius

func begin(pointer: Vector2) -> void:
	active = true
	vector = Vector2.ZERO; direction = Vector2i.ZERO
	# A landing position is not movement intent, including with a fixed base.
	# Measure the first drag from touch-down rather than the circle's centre.
	pointer_origin = pointer
	if not fixed_base: _place_center(pointer)
	visual_origin_offset = global_position + Vector2.ONE * radius - pointer_origin
	queue_redraw()

func _snap_direction(delta: Vector2) -> Vector2i:
	var threshold: float = minf(release_zone_pixels, dead_zone_pixels) if direction != Vector2i.ZERO else dead_zone_pixels
	if delta.length() <= threshold: return Vector2i.ZERO
	var candidate: Vector2i
	if not isometric:
		if absf(delta.x) > absf(delta.y): candidate = Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
		else: candidate = Vector2i.DOWN if delta.y > 0 else Vector2i.UP
	else:
		# Isometric rays tie at straight up/down/left/right. Resolve a narrow
		# cardinal cone explicitly so small thumb jitter cannot pick another ray.
		if minf(absf(delta.x), absf(delta.y)) <= maxf(absf(delta.x), absf(delta.y)) * 0.20:
			if absf(delta.x) > absf(delta.y): return Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
			return Vector2i.DOWN if delta.y > 0 else Vector2i.UP
		var strongest: float = -INF
		for tile: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var strength: float = delta.dot(_display_direction(tile))
			if strength > strongest: strongest = strength; candidate = tile
	if direction == Vector2i.ZERO or candidate == direction: return candidate
	var held_strength: float = maxf(0.0, delta.dot(_display_direction(direction)))
	return candidate if delta.dot(_display_direction(candidate)) > held_strength * direction_switch_ratio else direction

func update_pointer(pointer: Vector2) -> Vector2:
	var delta: Vector2 = pointer - pointer_origin
	if delta.length() > INPUT_RADIUS:
		var shift: Vector2 = delta - delta.normalized() * INPUT_RADIUS
		pointer_origin += shift
		if not fixed_base: _place_center(pointer_origin + visual_origin_offset)
		delta = delta.normalized() * INPUT_RADIUS
	direction = _snap_direction(delta)
	vector = (delta / INPUT_RADIUS).limit_length(1.0) if direction != Vector2i.ZERO else Vector2.ZERO
	queue_redraw()
	return Vector2(direction)

func reset() -> void:
	active = false; vector = Vector2.ZERO; direction = Vector2i.ZERO; pointer_origin = Vector2.ZERO; visual_origin_offset = Vector2.ZERO
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = Vector2(resting_position.x, (get_parent() as Control).size.y + resting_position.y)
	_place_center(global_position + Vector2.ONE * radius)
	queue_redraw()
