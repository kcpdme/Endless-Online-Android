extends Control
## Compact vitals and original next-level experience progress. Each heart/orb represents one fifth of the total.
var level: int = 0
var experience: int = 0
var experience_fraction: float = 0.0
var level_label: String = "Lv. 0"
var exp_label: String = "EXP 0%"
var hp: float = 1.0
var max_hp: float = 1.0
var tp: float = 1.0
var max_tp: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(280, 146)

func update_vitals(health: float, health_max: float, mana: float, mana_max: float) -> void:
	hp = health
	max_hp = maxf(1.0, health_max)
	tp = mana
	max_tp = maxf(1.0, mana_max)
	queue_redraw()

func update_experience(current_level: int, total: int) -> void:
	level = maxi(0, current_level)
	experience = maxi(0, total)
	var floor_exp: int = int(round(pow(level, 3) * 133.1))
	var next_exp: int = int(round(pow(level + 1, 3) * 133.1))
	experience_fraction = clampf(float(experience - floor_exp) / maxi(1, next_exp - floor_exp), 0.0, 1.0)
	level_label = "Lv. %d" % level
	exp_label = "EXP %d%%" % int(experience_fraction * 100.0)
	if level >= 250:
		experience_fraction = 1.0
		exp_label = "MAX"
	queue_redraw()

func _shape(center: Vector2, heart: bool, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(65):
		var t: float = TAU * float(i) / 64.0
		if heart:
			points.append(center + Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * radius / 17.0)
		else: points.append(center + Vector2(cos(t), sin(t)) * radius)
	return points

func _draw() -> void:
	for row: int in range(2):
		for i: int in range(5):
			var center: Vector2 = Vector2(28 + i * 48, 32 + row * 47)
			var heart: bool = row == 0
			var shape: PackedVector2Array = _shape(center, heart, 20.0 if heart else 15.0)
			draw_colored_polygon(_shape(center + Vector2(0, 3), heart, 22.0 if heart else 17.0), Color(0.02, 0.035, 0.065, 0.65))
			draw_colored_polygon(shape, Color("342734") if heart else Color("182f4b"))
			var fraction: float = clampf((hp / max_hp if heart else tp / max_tp) * 5.0 - i, 0.0, 1.0)
			if fraction > 0.0:
				var top: float = shape[0].y
				var bottom: float = top
				for point: Vector2 in shape:
					top = minf(top, point.y)
					bottom = maxf(bottom, point.y)
				var y: float = bottom - (bottom - top) * fraction
				var clip: PackedVector2Array = PackedVector2Array([Vector2(center.x - 25, y), Vector2(center.x + 25, y), center + Vector2(25, 25), center + Vector2(-25, 25)])
				for fill: PackedVector2Array in Geometry2D.intersect_polygons(shape, clip):
					draw_colored_polygon(fill, Color("ee5366") if heart else Color("389fee"))
				# Small bright glint follows a full or partially full vessel.
				if fraction > 0.72:
					draw_circle(center + Vector2(-6, -7), 4.0, Color(1.0, 0.82, 0.85, 0.55) if heart else Color(0.75, 0.95, 1.0, 0.8))
				if not heart: draw_arc(center + Vector2(0, 1), 11.5, 0.15, 1.4, 16, Color(0.15, 0.55, 1.0, 0.7), 2.0, true)
				else: draw_line(center + Vector2(8, 9), center + Vector2(1, 16), Color(0.55, 0.08, 0.22, 0.45), 2.0, true)
			draw_polyline(shape, Color("ffc2c3") if heart else Color("a4dcff"), 1.25, true)

	var progress: Rect2 = Rect2(8, 105, 232, 5)
	draw_rect(progress.grow(1), Color(0.02, 0.04, 0.06, 0.8))
	draw_rect(progress, Color("283d46"))
	draw_rect(Rect2(progress.position, Vector2(progress.size.x * experience_fraction, progress.size.y)), Color("e8c475"))
	var font: Font = ThemeDB.fallback_font
	draw_string_outline(font, Vector2(8, 131), level_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color(0.02, 0.03, 0.04, 0.8))
	draw_string(font, Vector2(8, 131), level_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0cf"))
	var exp_x: float = 240.0 - font.get_string_size(exp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string_outline(font, Vector2(exp_x, 131), exp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0.02, 0.03, 0.04, 0.8))
	draw_string(font, Vector2(exp_x, 131), exp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e8c475"))
