extends Control
## Subtle code-drawn wood grain, so the inventory has no stretched bitmap labels.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	for row: int in range(12, int(size.y) - 8, 11):
		var line: PackedVector2Array = PackedVector2Array()
		for x: int in range(8, int(size.x) - 7, 12):
			var bend: float = sin(float(x) * 0.018 + float(row) * 0.31) * 1.8 + sin(float(x) * 0.041 + float(row)) * 0.6
			line.append(Vector2(x, float(row) + bend))
		if line.size() > 1:
			draw_polyline(line, Color(0.17, 0.075, 0.02, 0.14), 1.0, true)
	# Beveled timber frame and brass corner pins.
	draw_line(Vector2(7, size.y - 7), Vector2(7, 7), Color(0.96, 0.75, 0.39, 0.32), 2.0)
	draw_line(Vector2(7, 7), Vector2(size.x - 7, 7), Color(0.96, 0.75, 0.39, 0.32), 2.0)
	draw_line(Vector2(8, size.y - 7), size - Vector2(7, 7), Color(0.16, 0.08, 0.025, 0.55), 2.0)
	for point: Vector2 in [Vector2(13, 13), Vector2(size.x - 13, 13), Vector2(13, size.y - 13), size - Vector2(13, 13)]:
		draw_circle(point + Vector2(0, 1), 3.0, Color("38230f"))
		draw_circle(point, 2.0, Color("d8ac60"))
