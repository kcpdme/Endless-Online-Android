extends RefCounted
## One authoritative summon/dismiss action; eggs and bonds stay in native handlers.
var game: Node
var button: Button
var caption: Label

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new()
	button.set("kind", "pet")
	button.position = Vector2(-262, -100) + game.COMBAT_HUD_SHIFT
	button.size = Vector2(76, 76)
	parent.add_child(button)
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	button.pressed.connect(press)
	caption = game._label(button, "Summon", Vector2(-4, 62), 13, game.GOLD)
	caption.size = Vector2(84, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 4)
	button.hide()

func bond() -> int:
	for row: Dictionary in game.online.player.get("spells", []):
		var spell: Dictionary = game.skills_ui.info(int(row.id))
		if spell.get("effect_kind", "") == "companion" and int((spell.get("companion", {}) as Dictionary).get("npc_id", 0)) > 0: return int(row.id)
	return 0

func tick() -> void:
	button.visible = game.online_mode and game.online.active and game.started and not game._modal_open() and not game.welcome.visible and int((game.online.player.get("stats", {}) as Dictionary).get("class_id", 0)) == 7
	var called: bool = not game.online.companion.is_empty()
	caption.text = "Dismiss" if called else "Summon"
	button.tooltip_text = "Dismiss pet (keep its bond)" if called else "Call your bonded pet" if bond() > 0 else "Hatch an egg from Inventory first"
	button.modulate = Color("b4efff") if called else Color.WHITE
	button.disabled = game.online.defeated or not game.skills_ui.casting.is_empty() or Time.get_ticks_msec() < game.skills_ui.ready_at

func contains(point: Vector2) -> bool:
	return button.visible and button.contains_point(point)

func press() -> void:
	if not button.visible or button.disabled: return
	var ident: int = 35 if not game.online.companion.is_empty() else bond()
	if ident == 0:
		game._toggle_inventory()
		game._toast("Use a pet egg to hatch a bond, then tap Summon.")
		return
	game.skills_ui.cast(ident, "self", 0)
