extends Button
## Circular translucent hit target with an independently opaque, drawn HUD icon.
var unread: bool = false:
	set(value):
		unread = value
		queue_redraw()
var kind: String = "bag":
	set(value):
		kind = value
		queue_redraw()

func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)
	tooltip_text = {"bag": "Inventory bag", "person": "Character equipment", "chat": "Chat"}.get(kind, "")

func _has_point(point: Vector2) -> bool:
	var radius: float = minf(size.x, size.y) * 0.5
	return point.distance_squared_to(size * 0.5) <= radius * radius

func contains_point(global_point: Vector2) -> bool:
	return _has_point(get_global_transform_with_canvas().affine_inverse() * global_point)

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.5
	var down: bool = button_pressed
	var hovered: bool = is_hovered()
	draw_circle(center, radius, Color(0.055, 0.12, 0.13, 0.61 if down else 0.42))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.98, 0.88, 0.64, 0.90) if down or hovered else Color(0.82, 0.88, 0.79, 0.64), 1.5, true)
	# Base alpha never multiplies the icon. Every icon fill and stroke below is opaque.
	var scale_factor: float = minf(size.x, size.y) / 76.0
	draw_set_transform(center + Vector2(0, 1 if down else 0), 0.0, Vector2.ONE * scale_factor)
	var ink: Color = Color("20312e")
	var light: Color = Color("f2e8c7")
	var gold: Color = Color("e7bd70")
	if kind == "skills":
		draw_colored_polygon(PackedVector2Array([Vector2(-19, -15), Vector2(-3, -12), Vector2(0, -9), Vector2(3, -12), Vector2(19, -15), Vector2(19, 15), Vector2(3, 17), Vector2(0, 20), Vector2(-3, 17), Vector2(-19, 15)]), light)
		draw_line(Vector2(0, -9), Vector2(0, 17), ink, 2.0, true)
		for y: int in [-5, 1, 7]:
			draw_line(Vector2(-14, y), Vector2(-5, y + 2), gold, 1.8, true)
			draw_line(Vector2(5, y + 2), Vector2(14, y), gold, 1.8, true)
	elif kind == "chat":
		var bubble: PackedVector2Array = PackedVector2Array([Vector2(-17, -13), Vector2(17, -13), Vector2(17, 10), Vector2(-2, 10), Vector2(-12, 18), Vector2(-9, 10), Vector2(-17, 10)])
		draw_colored_polygon(bubble, light)
		for x: int in [-9, 0, 9]: draw_circle(Vector2(x, -1), 2.2, ink)
		if unread: draw_circle(Vector2(18, -17), 5.5, Color("ef6872"))
	elif kind == "person":
		draw_circle(Vector2(0, -10), 8.0, ink)
		draw_circle(Vector2(0, -11), 7.0, light)
		var shoulders: PackedVector2Array = PackedVector2Array([Vector2(-15, 16), Vector2(-14, 9), Vector2(-9, 3), Vector2(-5, 0), Vector2(5, 0), Vector2(9, 3), Vector2(14, 9), Vector2(15, 16)])
		draw_colored_polygon(shoulders, light)
		draw_polyline(PackedVector2Array([Vector2(-15, 16), Vector2(15, 16)]), gold, 2.0, true)
	else:
		# Sturdy satchel: handle, closed flap, contrasting strap and metal clasp.
		draw_arc(Vector2(0, -13), 7.0, PI, TAU, 20, light, 3.0, true)
		var body: PackedVector2Array = PackedVector2Array([Vector2(-15, -11), Vector2(15, -11), Vector2(18, 17), Vector2(-18, 17)])
		draw_colored_polygon(body, light)
		draw_polyline(PackedVector2Array([Vector2(-15, -11), Vector2(15, -11), Vector2(18, 17), Vector2(-18, 17), Vector2(-15, -11)]), ink, 1.8, true)
		draw_colored_polygon(PackedVector2Array([Vector2(-16, -10), Vector2(16, -10), Vector2(12, 1), Vector2(0, 6), Vector2(-12, 1)]), gold)
		draw_line(Vector2(0, -9), Vector2(0, 14), ink, 3.0, true)
		draw_rect(Rect2(-3, 1, 6, 6), light)
		draw_rect(Rect2(-2, 2, 4, 4), ink, false, 1.0)
	draw_set_transform(Vector2.ZERO)
