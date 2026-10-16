extends Button
## An opaque action icon over a translucent touch surface; cooldown lives on the rim.
var weapon: Texture2D
var collecting: bool = false
var holding: bool = false:
	set(value):
		holding = value
		queue_redraw()
var cooldown_fraction: float = 0.0:
	set(value):
		cooldown_fraction = clampf(value, 0.0, 1.0)
		queue_redraw()

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func contains_point(point: Vector2) -> bool:
	return _has_point(point - global_position)

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= minf(size.x, size.y) / 2.0

func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 - 3.0
	var pressed_now: bool = is_pressed() or holding
	draw_circle(center, radius, Color(0.10, 0.075, 0.04, 0.42 if pressed_now else 0.23))
	draw_arc(center, radius, 0.0, TAU, 72, Color(0.91, 0.79, 0.57, 0.60 if pressed_now else 0.38), 2.0, true)
	draw_arc(center, radius - 7.0, 0.0, TAU, 72, Color(0.96, 0.88, 0.69, 0.13), 1.0, true)
	if cooldown_fraction > 0.0 and not collecting:
		draw_arc(center, radius - 2.0, -PI / 2.0, -PI / 2.0 + TAU * cooldown_fraction, 72, Color(0.97, 0.81, 0.43, 0.92), 3.0, true)
	# The opaque art grows with the larger touch surface.
	draw_set_transform(center, 0.0, Vector2.ONE * size.x / 120.0)
	center = Vector2.ZERO
	if collecting:
		# Opaque leather pouch indicates pickup without a text banner.
		draw_colored_polygon(PackedVector2Array([center + Vector2(-13, -17), center + Vector2(12, -17), center + Vector2(23, 13), center + Vector2(16, 24), center + Vector2(-17, 24), center + Vector2(-23, 12)]), Color("a46f35"))
		draw_style_box(_icon_style(Color("c99a50")), Rect2(center + Vector2(-15, -23), Vector2(30, 10)))
		draw_line(center + Vector2(-13, -14), center + Vector2(13, -14), Color("f5d890"), 3.0, true)
		draw_circle(center + Vector2(1, 4), 7.0, Color("f4cf73"))
	elif weapon != null:
		var icon_size: Vector2 = weapon.get_size()
		icon_size *= minf(62.0 / icon_size.y, 55.0 / icon_size.x)
		# Do not fade the icon with the background or cooldown.
		draw_texture_rect(weapon, Rect2(center - icon_size / 2.0, icon_size), false, Color.WHITE)
	else:
		# A fist keeps the action honest when the weapon is unequipped.
		draw_style_box(_icon_style(Color("ddbb8a")), Rect2(center + Vector2(-13, -13), Vector2(30, 34)))
		for finger: int in range(4):
			draw_style_box(_icon_style(Color("efcea0")), Rect2(center + Vector2(-16 + finger * 8, -23), Vector2(9, 23)))
		draw_style_box(_icon_style(Color("e7c394")), Rect2(center + Vector2(-21, -3), Vector2(14, 22)))
	draw_set_transform(Vector2.ZERO)

func _icon_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("51391e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
