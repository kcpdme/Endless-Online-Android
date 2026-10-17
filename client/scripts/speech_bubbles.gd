extends Control
## Screen-space speech above characters/HUD, below modal windows; never eats input.
var game: Node
var bubbles: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 9
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	visible = game != null and game.online_mode and game.online.active and game.started and not game._modal_open()
	if game == null: return
	var speech: Dictionary = game.online.chat_bubbles
	var now: int = Time.get_ticks_msec()
	for key: Variant in bubbles.keys():
		if not speech.has(key) or now >= int((speech[key] as Dictionary).until):
			(bubbles[key] as Control).queue_free()
			bubbles.erase(key)
	for key: Variant in speech.keys():
		var data: Dictionary = speech[key] as Dictionary
		if now >= int(data.until): continue
		var panel: PanelContainer = bubbles.get(key) as PanelContainer
		if panel == null:
			panel = PanelContainer.new()
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style: StyleBoxFlat = game._style(Color("fff2d5"), Color("735733"), 9)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.content_margin_left = 11
			style.content_margin_right = 11
			style.content_margin_top = 7
			style.content_margin_bottom = 7
			panel.add_theme_stylebox_override("panel", style)
			var label: Label = Label.new()
			label.name = "Message"
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 20)
			label.add_theme_color_override("font_color", Color("2c2218"))
			panel.add_child(label)
			add_child(panel)
			bubbles[key] = panel
		var label: Label = panel.get_node("Message") as Label
		label.text = str(data.text)
		var text_width: float = ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		label.custom_minimum_size.x = clampf(text_width + 2, 50, minf(310, maxf(50, size.x - 40)))
		panel.reset_size()
		var at: Vector2 = game.online.chat_bubble_position(int(key))
		panel.visible = at.is_finite()
		if not panel.visible: continue
		var screen: Vector2 = game.get_global_transform_with_canvas() * (at + Vector2(0, -72))
		var anchor: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen
		panel.position = anchor - Vector2(panel.size.x / 2, panel.size.y + 9)
		panel.position.x = clampf(panel.position.x, 8, maxf(8, size.x - panel.size.x - 8))
		panel.position.y = maxf(8, panel.position.y)
	queue_redraw()

func _draw() -> void:
	for panel: PanelContainer in bubbles.values():
		if not panel.visible: continue
		var bottom: Vector2 = panel.position + Vector2(panel.size.x / 2, panel.size.y - 1)
		draw_colored_polygon(PackedVector2Array([bottom + Vector2(-9, 0), bottom + Vector2(9, 0), bottom + Vector2(0, 10)]), Color("735733"))
		draw_colored_polygon(PackedVector2Array([bottom + Vector2(-6, -1), bottom + Vector2(6, -1), bottom + Vector2(0, 7)]), Color("fff2d5"))
