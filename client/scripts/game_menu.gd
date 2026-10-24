extends RefCounted
## Opaque, full-screen game menu with touch-sized settings and navigation.

func build(game: Node, parent: Node) -> Control:
	# A CanvasLayer parent fills the physical viewport, including HUD safe-area gaps.
	var page: Control = game._modal(parent, Vector2.ONE)
	page.name = "GameMenu"
	page.color = Color("0c1c20")
	var card: Control = page.get_child(0)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", game._style(Color("10272a"), Color("10272a"), 0))
	var margin: MarginContainer = MarginContainer.new()
	card.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	var layout_safe_area: Callable = func() -> void:
		var safe: Rect2 = game._hud_bounds()
		var viewport: Rect2 = game.get_viewport_rect()
		margin.add_theme_constant_override("margin_left", 32 + int(safe.position.x))
		margin.add_theme_constant_override("margin_right", 32 + int(viewport.end.x - safe.end.x))
		margin.add_theme_constant_override("margin_top", 24 + int(safe.position.y))
		margin.add_theme_constant_override("margin_bottom", 24 + int(viewport.end.y - safe.end.y))
	page.visibility_changed.connect(func() -> void:
		if page.visible: layout_safe_area.call()
	)
	game.get_viewport().size_changed.connect(func() -> void: layout_safe_area.call_deferred())
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	margin.add_child(body)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	body.add_child(header)
	var title: Label = label(game, header, "Aster Vale", 34, game.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button: Button = button(game, header, "×", func() -> void: page.hide())
	close_button.custom_minimum_size.x = 60
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 36)
	scroll.add_child(columns)
	var adventure: VBoxContainer = column(columns)
	label(game, adventure, "Your adventure", 25, game.TEXT)
	var note: Label = label(game, adventure, "Your journey is saved automatically.", 18, game.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(game, adventure, "Return to the vale", func() -> void: page.hide(), true)
	button(game, adventure, "Movement controls", func() -> void: game.movement_ui.open())
	button(game, adventure, "Graphics", func() -> void: game.graphics_ui.open())
	button(game, adventure, "Social, emotes and accessibility", func() -> void: game.feature_ui.open("social"))
	button(game, adventure, "Redeem Code", func() -> void: game.redeem_ui.open())
	var audio: VBoxContainer = column(columns)
	label(game, audio, "Audio", 25, game.TEXT)
	audio_option(game, audio, "Music", game.music)
	audio_option(game, audio, "Sound effects", game.sfx)
	var footer: HBoxContainer = HBoxContainer.new()
	body.add_child(footer)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var logout: Button = button(game, footer, "Log out", func() -> void: page.hide(); game.online.log_out())
	logout.custom_minimum_size.x = 220
	logout.size_flags_horizontal = Control.SIZE_SHRINK_END
	page.hide()
	return page

func column(parent: Control) -> VBoxContainer:
	var result: VBoxContainer = VBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("separation", 18)
	parent.add_child(result)
	return result

func label(game: Node, parent: Node, value: String, font_size: int, color: Color) -> Label:
	return game._label(parent, value, Vector2.ZERO, font_size, color)

func button(game: Node, parent: Node, value: String, action: Callable, primary: bool = false) -> Button:
	var result: Button = game._button(parent, value, Vector2.ZERO, Vector2.ONE, action, primary)
	result.custom_minimum_size.y = 58
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func audio_option(game: Node, parent: Control, title: String, controller: Node) -> void:
	var toggle: CheckBox = CheckBox.new()
	toggle.text = title
	toggle.custom_minimum_size.y = 52
	toggle.button_pressed = controller.enabled
	toggle.add_theme_font_size_override("font_size", 22)
	toggle.toggled.connect(controller.set_enabled)
	parent.add_child(toggle)
	var volume: HSlider = HSlider.new()
	volume.custom_minimum_size.y = 52
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = controller.volume
	volume.value_changed.connect(controller.set_volume)
	parent.add_child(volume)
