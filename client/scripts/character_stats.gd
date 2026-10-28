extends RefCounted
## Classic EO attributes and server-calculated totals, alongside the original paperdoll.
const ATTRIBUTES: Array[String] = ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]
var game: Node
var panel: Control
var item_panel: Control
var item_body: Label
var item_heading: Label
var item_art: TextureRect
var item_kind: String = ""
var item_is_equipped: bool = false
var item_return_to: Control
var stats_return_to: Control
var summary: Label
var details: Label
var points: Label
var classic_fields: Dictionary = {}
var values: Array[Label] = []
var add_buttons: Array[Button] = []
var held_stat: int = 0
var repeat_wait: float = 0.0
var vitals: Control

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	vitals = preload("res://scripts/vitals_hud.gd").new()
	vitals.position = Vector2(28, 20)
	parent.add_child(vitals)
	vitals.hide()
	panel = game._modal(parent, Vector2(1050, 570))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "CHARACTER STATS", Vector2(40, 22), 28, game.GOLD)
	game._button(card, "×", Vector2(954, 18), Vector2(54, 48), func() -> void: close_stats())
	summary = game._label(card, "", Vector2(40, 72), 19)
	var art: TextureRect = TextureRect.new()
	if ResourceLoader.exists("res://content/ui/classic_34.png"): art.texture = load("res://content/ui/classic_34.png") as Texture2D
	art.position = Vector2(40, 118)
	art.size = Vector2(970, 238)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	for index: int in range(ATTRIBUTES.size()):
		var value: Label = game._label(card, "", Vector2(140, 130 + index * 36), 20)
		value.size = Vector2(104, 28)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		values.append(value)
		var stat_id: int = index + 1
		var increase: Button = game._button(card, "+", Vector2(256, 133 + index * 36), Vector2(30, 24), func() -> void: pass)
		increase.button_down.connect(func() -> void: begin_repeat(stat_id))
		increase.button_up.connect(stop_repeat)
		increase.mouse_exited.connect(stop_repeat)
		increase.add_theme_font_size_override("font_size", 14)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBoxFlat = game._wood_style(Color("51381f") if state == "disabled" else Color("286541") if state == "normal" else Color("368451"), Color("87633c") if state == "disabled" else Color("8ad89c"))
			style.content_margin_left = 2.0
			style.content_margin_right = 2.0
			style.content_margin_top = 2.0
			style.content_margin_bottom = 2.0
			increase.add_theme_stylebox_override(state, style)
		increase.add_theme_color_override("font_color", Color("dcffe4"))
		increase.add_theme_color_override("font_disabled_color", Color("a58f70"))
		add_buttons.append(increase)
	var field_rows: Dictionary = {"hp": [356, 130, 144], "tp": [356, 166, 144], "damage": [356, 202, 144], "accuracy": [356, 238, 144], "armor": [356, 274, 144], "evade": [356, 310, 144], "name": [600, 130, 290], "guild": [600, 166, 386], "level": [946, 130, 40], "weight": [600, 202, 122], "stat_points": [600, 238, 122], "skill_points": [600, 274, 122], "element": [600, 310, 122], "gold": [798, 202, 188], "experience": [798, 238, 188], "tnl": [798, 274, 188], "karma": [798, 310, 188]}
	for key: String in field_rows:
		var rect: Array = field_rows[key]
		var label: Label = game._label(card, "", Vector2(float(rect[0]), float(rect[1])), 20)
		label.size = Vector2(float(rect[2]), 28)
		label.clip_text = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		classic_fields[key] = label
	points = game._label(card, "", Vector2(40, 380), 18, game.GOLD)
	var guidance_scroll: ScrollContainer = ScrollContainer.new()
	guidance_scroll.position = Vector2(40, 420)
	guidance_scroll.size = Vector2(970, 120)
	guidance_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(guidance_scroll)
	details = game._label(guidance_scroll, "Equipment bonuses are included. Use + to spend earned stat points.", Vector2.ZERO, 17, game.MUTED)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.visibility_changed.connect(func() -> void:
		if not panel.visible: stop_repeat()
	)
	panel.hide()
	item_panel = game._modal(parent, Vector2(840, 650))
	var item_card: Control = item_panel.get_child(0) as Control
	game._wood_card(item_card)
	item_heading = game._label(item_card, "", Vector2(36, 24), 28, game.GOLD)
	item_heading.size = Vector2(672, 68)
	item_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(item_card, "×", Vector2(750, 18), Vector2(54, 48), close_item)
	item_panel.z_index = 20
	item_art = TextureRect.new()
	item_art.position = Vector2(36, 126)
	item_art.size = Vector2(240, 330)
	item_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_card.add_child(item_art)
	var item_scroll: ScrollContainer = ScrollContainer.new()
	item_scroll.position = Vector2(306, 100)
	item_scroll.size = Vector2(494, 450)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_card.add_child(item_scroll)
	item_body = game._label(item_scroll, "", Vector2.ZERO, 20)
	item_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(item_card, "Item bonuses come from the original game data.
Your combined totals are shown in Character Stats.", Vector2(36, 570), 17, game.MUTED)
	item_panel.hide()

func begin_repeat(stat_id: int) -> void:
	held_stat = stat_id
	repeat_wait = 0.35
	game.online.spend_stat(stat_id)

func stop_repeat() -> void:
	held_stat = 0
	repeat_wait = 0.0

func process_repeat(delta: float) -> void:
	if held_stat == 0: return
	if not panel.visible or not game.online.active or int((game.online.player.get("stats", {}) as Dictionary).get("stat_points", 0)) <= 0:
		stop_repeat()
		return
	repeat_wait = maxf(0.0, repeat_wait - delta)
	if repeat_wait <= 0.0 and game.online._action_ready():
		game.online.spend_stat(held_stat)
		repeat_wait = 0.16

func show_item(kind: String, return_to: Control = null, equipped: bool = false) -> void:
	if not game.online_mode or game.online.item_info(kind).is_empty(): return
	item_kind = kind
	item_is_equipped = equipped or not kind.begins_with("item:")
	item_return_to = return_to
	if return_to != null: return_to.hide()
	game.inventory.hide()
	game.character_panel.hide()
	game._cancel_controls()
	item_panel.show()
	refresh()

func is_open() -> bool:
	return (panel != null and panel.visible) or (item_panel != null and item_panel.visible)

func close_item() -> void:
	item_panel.hide()
	if is_instance_valid(item_return_to) and game.started: item_return_to.show()
	item_return_to = null

func close_stats() -> void:
	panel.hide()
	if is_instance_valid(stats_return_to) and game.started: stats_return_to.show()
	stats_return_to = null

func hide() -> void:
	if item_panel.visible: close_item()
	elif panel.visible: close_stats()

func dismiss() -> void:
	item_return_to = null
	stats_return_to = null
	panel.hide()
	item_panel.hide()

func show_stats() -> void:
	if not game.online_mode:
		game._toast("Character stats belong to your online character.")
		return
	stats_return_to = game.character_panel if game.character_panel.visible else null
	game.character_panel.hide()
	game.inventory.hide()
	game.menu.hide()
	game._cancel_controls()
	panel.show()
	refresh()

func refresh() -> void:
	if game == null or game.online == null: return
	if not item_kind.is_empty():
		var item: Dictionary = game.online.item_info(item_kind)
		item_art.texture = game.online._catalog_texture(str(item.get("icon", "")))
		item_heading.text = str(item.get("name", "Item"))
		var bonuses: Array[String] = []
		var requirements: Array[String] = []
		for key: String in ATTRIBUTES:
			bonuses.append("%s +%d" % [key.substr(0, 3).to_upper(), int(item.get(key, 0))])
			if int(item.get(key + "_requirement", 0)) > 0: requirements.append("%s %d" % [key.capitalize(), int(item[key + "_requirement"])])
		if int(item.get("level_requirement", 0)) > 0: requirements.append("Level %d" % int(item.level_requirement))
		var professions: String = game.online.equipment_classes(item)
		if not professions.is_empty(): requirements.append(professions)
		var quantity: int = 0
		for entry: Dictionary in game.online.inventory_items():
			if int(entry.id) == game.online.item_id(item_kind): quantity = int(entry.amount)
		item_heading.text += "  ·  Equipped" if item_is_equipped else "  ×%d" % quantity
		if int(item.get("type", -1)) == 12: requirements.append("Female" if int(item.get("gender", 0)) == 0 else "Male")
		item_body.text = "Damage  %d–%d\nArmor  +%d\n\nAccuracy  +%d\nEvade  +%d\n\nHP  +%d\nTP  +%d\n\n%s\n\nWeight  %d\n\nRequirements\n%s" % [int(item.get("min_damage", 0)), int(item.get("max_damage", 0)), int(item.get("armor", 0)), int(item.get("accuracy", 0)), int(item.get("evade", 0)), int(item.get("hp", 0)), int(item.get("tp", 0)), "\n".join(bonuses), int(item.get("weight", 0)), "\n".join(requirements) if not requirements.is_empty() else "None"]
		if item.get("backstab", false): item_body.text += "\n\nRogue rear strikes: 1.5x or 2x damage, without critical stacking."
		if int(item.get("hatch_spell", 0)) > 0:
			var summon: Dictionary = (game.online.catalog.get("spells", {}) as Dictionary).get(str(int(item.hatch_spell)), {}) as Dictionary
			if bool(item.get("bond_lost_on_death", false)):
				item_body.text = "Hatch this egg to bond %s.\n\nSummoner level %d required. One living pet bond at a time. Your death kills the pet and breaks its bond; hatch another egg afterward.\n\nBound to you: cannot trade, drop or store in a shared chest. Travel, logout and TP exhaustion keep the bond. Calling and upkeep still cost TP." % [str(summon.get("name", "a spirit")), int(item.get("level_requirement", 1))]
			else:
				item_body.text = "Hatch this egg to learn %s. Summoner level %d required. Calling and upkeep cost TP." % [str(summon.get("name", "a spirit summon")), int(item.get("level_requirement", 1))]
		if item.get("crafted", false): item_body.text += "\n\nCrafted definition · improved combat budget"
		if str(item.get("archetype", "balanced")) != "balanced": item_body.text += "\nStyle: %s" % str(item.archetype).capitalize()
	var p: Dictionary = game.online.player
	var stats: Dictionary = p.get("stats", {}) as Dictionary
	var hp: int = int(p.get("hp", 0))
	var max_hp: int = maxi(1, int(p.get("max_hp", 1)))
	var tp: int = int(p.get("tp", 0))
	var max_tp: int = maxi(1, int(p.get("max_tp", 1)))
	vitals.update_vitals(hp, max_hp, tp, max_tp)
	vitals.update_experience(int(p.get("level", 0)), int(stats.get("experience", 0)))
	var classes: Dictionary = game.online.catalog.get("classes", {}) as Dictionary
	var profession: Dictionary = classes.get(str(int(stats.get("class_id", 0))), {}) as Dictionary
	details.text = str(profession.get("build_hint", "Equipment bonuses are included. Use + to spend earned stat points."))
	var signature: Dictionary = profession.get("signature", {}) as Dictionary
	if not signature.is_empty(): details.text += "\n" + str(signature.get("description", ""))
	summary.text = "%s  ·  Level %d  ·  %s" % [str(p.get("name", "Player")), int(p.get("level", 0)), str(profession.get("name", "–"))]
	points.text = "Stat points: %d     Skill points: %d     Max SP: %d" % [int(stats.get("stat_points", 0)), int(stats.get("skill_points", 0)), int(stats.get("max_sp", 0))]
	for index: int in range(ATTRIBUTES.size()):
		values[index].text = str(int(stats.get(ATTRIBUTES[index], 0)))
		add_buttons[index].disabled = int(stats.get("stat_points", 0)) <= 0 or not game.online.active or game.online.defeated
	var fields: Dictionary = {"hp": "%d / %d" % [hp, max_hp], "tp": "%d / %d" % [tp, max_tp], "damage": "%d–%d" % [int(stats.get("min_damage", 0)), int(stats.get("max_damage", 0))], "name": str(p.get("name", "")), "guild": str(stats.get("guild", "")), "level": str(int(p.get("level", 0))), "weight": "%d / %d" % [int(stats.get("weight", 0)), int(stats.get("max_weight", 0))], "gold": str(game.coins), "element": "—", "tnl": "—"}
	for key: String in ["accuracy", "armor", "evade", "stat_points", "skill_points", "experience", "karma"]: fields[key] = str(int(stats.get(key, 0)))
	# Original level table: next level cubed * 133.1; display remaining EXP.
	var next_level: int = int(p.get("level", 0)) + 1
	fields["tnl"] = str(maxi(0, int(round(pow(next_level, 3) * 133.1)) - int(stats.get("experience", 0))))
	for key: String in classic_fields: (classic_fields[key] as Label).text = str(fields.get(key, ""))
