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
	tooltip_text = {"bag": "Inventory bag", "person": "Character equipment", "stats":"Character stats and attributes", "auto_attack":"Enable / disable hold-to-auto attack", "chat": "Chat", "quests": "Ongoing quests", "party": "Party", "admin": "Admin functions", "skills": "Skills", "sit": "Sit / Stand", "zoom":"Normal / 125% view", "collapse":"Hide messages"}.get(kind, "")

func _has_point(point: Vector2) -> bool:
	if kind=="collapse":return Rect2(Vector2.ZERO,size).has_point(point)
	var radius: float = minf(size.x, size.y) * 0.5
	return point.distance_squared_to(size * 0.5) <= radius * radius

func contains_point(global_point: Vector2) -> bool:
	return _has_point(get_global_transform_with_canvas().affine_inverse() * global_point)

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.5
	var down: bool = button_pressed
	var hovered: bool = is_hovered()
	if kind!="collapse":
		draw_circle(center, radius, Color(0.055, 0.12, 0.13, 0.61 if down else 0.42))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.98, 0.88, 0.64, 0.90) if down or hovered else Color(0.82, 0.88, 0.79, 0.64), 1.5, true)
	# Base alpha never multiplies the icon. Every icon fill and stroke below is opaque.
	var scale_factor: float = minf(size.x, size.y) / 76.0
	draw_set_transform(center + Vector2(0, 1 if down else 0), 0.0, Vector2.ONE * scale_factor)
	var ink: Color = Color("20312e")
	var light: Color = Color("f2e8c7")
	var gold: Color = Color("e7bd70")
	if kind=="stats":
		for index:int in range(3):
			var height:float=16+index*12
			draw_rect(Rect2(-20+index*15,22-height,10,height),gold if index==2 else light)
		draw_line(Vector2(-24,24),Vector2(24,24),light,2,true)
	elif kind=="auto_attack":
		var color:Color=gold if down else light
		draw_arc(Vector2.ZERO,23,-PI*.85,-PI*.1,26,color,3.5,true)
		draw_arc(Vector2.ZERO,23,PI*.15,PI*.9,26,color,3.5,true)
		draw_colored_polygon(PackedVector2Array([Vector2(25,-12),Vector2(22,0),Vector2(13,-9)]),color)
		draw_colored_polygon(PackedVector2Array([Vector2(-25,12),Vector2(-22,0),Vector2(-13,9)]),color)
		draw_line(Vector2(-6,14),Vector2(8,-13),color,4,true)
		draw_line(Vector2(-12,4),Vector2(4,12),color,3,true)
		if not down:draw_line(Vector2(-23,24),Vector2(23,-24),Color("eaa69c"),3.5,true)
	elif kind=="zoom":
		draw_arc(Vector2(-4,-5),14,0,TAU,48,light,3.0,true)
		draw_line(Vector2(7,7),Vector2(21,21),gold,5.0,true)
		draw_line(Vector2(-11,-5),Vector2(3,-5),gold,2.5,true)
		if not button_pressed:draw_line(Vector2(-4,-12),Vector2(-4,2),gold,2.5,true)
	elif kind=="collapse":
		var chevron:PackedVector2Array=PackedVector2Array([Vector2(-18,-8),Vector2(0,11),Vector2(18,-8)])
		draw_polyline(chevron,ink,8,true);draw_polyline(chevron,light,4.5,true)
	elif kind == "hand":
		# Open palm: compact pickup action, without a changing item-name ribbon.
		var hand: PackedVector2Array = PackedVector2Array([Vector2(-13, 5), Vector2(-21, -3), Vector2(-20, -7), Vector2(-16, -8), Vector2(-9, -2), Vector2(-9, -19), Vector2(-6, -22), Vector2(-3, -20), Vector2(-3, -7), Vector2(-2, -25), Vector2(1, -27), Vector2(4, -24), Vector2(4, -7), Vector2(5, -22), Vector2(8, -23), Vector2(11, -20), Vector2(11, -5), Vector2(12, -16), Vector2(15, -17), Vector2(18, -14), Vector2(18, 4), Vector2(13, 16), Vector2(12, 23), Vector2(-5, 23), Vector2(-6, 16)])
		draw_colored_polygon(hand, light)
		draw_line(Vector2(-2, 5), Vector2(8, 2), gold, 2.0, true)
		draw_line(Vector2(-1, 10), Vector2(9, 8), gold, 2.0, true)
	elif kind == "emote":
		draw_circle(Vector2.ZERO, 21, gold)
		draw_circle(Vector2(-7, -6), 3, ink)
		draw_circle(Vector2(7, -6), 3, ink)
		draw_arc(Vector2(0, 2), 11, 0.15, PI - 0.15, 20, ink, 3, true)
	elif kind == "pet":
		for at: Vector2 in [Vector2(-15, -12), Vector2(-5, -21), Vector2(7, -21), Vector2(17, -11)]: draw_circle(at, 5.5, light)
		draw_colored_polygon(PackedVector2Array([Vector2(-16, 10), Vector2(-9, -2), Vector2(0, -7), Vector2(10, -1), Vector2(18, 11), Vector2(12, 20), Vector2(0, 15), Vector2(-11, 20)]), gold)
	elif kind == "sit":
		# Seated person: opaque silhouette inside the same translucent HUD ring.
		draw_circle(Vector2(-5, -19), 6.0, light)
		draw_polyline(PackedVector2Array([Vector2(-7, -9), Vector2(-7, 6), Vector2(9, 6), Vector2(13, 22), Vector2(21, 22)]), light, 7.0, true)
		draw_polyline(PackedVector2Array([Vector2(-20, -6), Vector2(-20, 13), Vector2(3, 13)]), gold, 3.0, true)
		draw_line(Vector2(-17, 13), Vector2(-17, 24), gold, 3.0, true)
	elif kind == "skills":
		draw_colored_polygon(PackedVector2Array([Vector2(-19, -15), Vector2(-3, -12), Vector2(0, -9), Vector2(3, -12), Vector2(19, -15), Vector2(19, 15), Vector2(3, 17), Vector2(0, 20), Vector2(-3, 17), Vector2(-19, 15)]), light)
		draw_line(Vector2(0, -9), Vector2(0, 17), ink, 2.0, true)
		for y: int in [-5, 1, 7]:
			draw_line(Vector2(-14, y), Vector2(-5, y + 2), gold, 1.8, true)
			draw_line(Vector2(5, y + 2), Vector2(14, y), gold, 1.8, true)
	elif kind == "admin":
		draw_colored_polygon(PackedVector2Array([Vector2(-20,-14),Vector2(-10,-7),Vector2(0,-23),Vector2(10,-7),Vector2(20,-14),Vector2(15,16),Vector2(-15,16)]),gold)
		draw_rect(Rect2(-15,16,30,5),light)
		draw_circle(Vector2(0,3),4.0,ink)
	elif kind == "party":
		# Three people remain distinct from the single-character equipment icon.
		for side: int in [-1, 1]:
			draw_circle(Vector2(side * 15, -9), 5.5, gold)
			draw_style_box(_shoulders(gold), Rect2(side * 15 - 9, -1, 18, 20))
		draw_circle(Vector2(0, -15), 7.0, light)
		draw_style_box(_shoulders(light), Rect2(-11, -4, 22, 28))
	elif kind == "quests":
		# Rolled parchment and a check mark distinguish quests from the skill book.
		draw_rect(Rect2(-14,-20,28,38),light)
		draw_line(Vector2(-18,-20),Vector2(16,-20),gold,5.0,true)
		draw_line(Vector2(-14,18),Vector2(18,18),gold,5.0,true)
		for y: int in [-11,-4]: draw_line(Vector2(-7,y),Vector2(8,y),ink,2.0,true)
		draw_polyline(PackedVector2Array([Vector2(-7,6),Vector2(-2,11),Vector2(9,1)]),ink,3.0,true)
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

func _shoulders(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
