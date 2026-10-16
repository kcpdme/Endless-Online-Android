extends RefCounted
## Classic EO attributes and server-calculated totals, alongside the original paperdoll.
const ATTRIBUTES: Array[String] = ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]
var game: Node
var panel: Control
var item_panel: Control
var item_body: Label
var item_heading: Label
var item_kind: String = ""
var summary: Label
var details: Label
var points: Label
var values: Array[Label] = []
var add_buttons: Array[Button] = []
var vitals: Control
var hp_bar: ProgressBar
var tp_bar: ProgressBar
var hp_text: Label
var tp_text: Label
var level_text: Label

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	vitals = game._panel(parent, Vector2(389, 96), Vector2(300, 92))
	hp_bar = _bar(Vector2(14, 12), Color("b0473e"))
	tp_bar = _bar(Vector2(14, 39), Color("447bba"))
	hp_text = game._label(vitals, "", Vector2(22, 11), 16)
	tp_text = game._label(vitals, "", Vector2(22, 38), 16)
	level_text = game._label(vitals, "", Vector2(14, 67), 14, game.GOLD)
	vitals.hide()
	panel = game._modal(parent, Vector2(840, 650))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "CHARACTER STATS", Vector2(36, 22), 28, game.GOLD)
	game._button(card, "×", Vector2(750, 18), Vector2(54, 48), func() -> void: panel.hide())
	summary = game._label(card, "", Vector2(36, 76), 20)
	points = game._label(card, "", Vector2(36, 126), 17, game.GOLD)
	for index: int in range(ATTRIBUTES.size()):
		var key: String = ATTRIBUTES[index]
		game._label(card, key.capitalize(), Vector2(36, 179 + index * 54), 20)
		values.append(game._label(card, "", Vector2(255, 179 + index * 54), 22))
		var stat_id: int = index + 1
		add_buttons.append(game._button(card, "+", Vector2(326, 171 + index * 54), Vector2(52, 46), func() -> void: game.online.spend_stat(stat_id)))
	details = game._label(card, "", Vector2(438, 175), 18)
	details.size = Vector2(370, 360)
	game._label(card, "Equipment bonuses are included in these totals.\nSpend earned points using + beside an attribute.", Vector2(36, 559), 17, game.MUTED)
	panel.hide()
	item_panel = game._modal(parent, Vector2(840, 650))
	var item_card: Control = item_panel.get_child(0) as Control
	game._wood_card(item_card)
	item_heading = game._label(item_card, "", Vector2(36, 24), 28, game.GOLD)
	game._button(item_card, "×", Vector2(750, 18), Vector2(54, 48), func() -> void: item_panel.hide())
	item_body = game._label(item_card, "", Vector2(36, 92), 20)
	item_body.size = Vector2(760, 470)
	item_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(item_card, "Item bonuses come from the original game data.
Your combined totals are shown in Character Stats.", Vector2(36, 570), 17, game.MUTED)
	item_panel.hide()

func show_item(kind: String) -> void:
	if not game.online_mode or game.online.item_info(kind).is_empty(): return
	item_kind = kind
	game.inventory.hide()
	game.character_panel.hide()
	game._cancel_controls()
	item_panel.show()
	refresh()

func is_open() -> bool:
	return (panel != null and panel.visible) or (item_panel != null and item_panel.visible)

func hide() -> void:
	panel.hide()
	item_panel.hide()

func _bar(at: Vector2, color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.position = at
	bar.size = Vector2(272, 24)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	vitals.add_child(bar)
	return bar

func show_stats() -> void:
	if not game.online_mode:
		game._toast("Character stats belong to your online character.")
		return
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
		item_heading.text = str(item.get("name", "Item"))
		var bonuses: Array[String] = []
		var requirements: Array[String] = []
		for key: String in ATTRIBUTES:
			bonuses.append("%s +%d" % [key.substr(0, 3).to_upper(), int(item.get(key, 0))])
			if int(item.get(key + "_requirement", 0)) > 0: requirements.append("%s %d" % [key.capitalize(), int(item[key + "_requirement"])])
		if int(item.get("level_requirement", 0)) > 0: requirements.append("Level %d" % int(item.level_requirement))
		if int(item.get("class_requirement", 0)) > 0:
			var item_class: Dictionary = (game.online.catalog.get("classes", {}) as Dictionary).get(str(int(item.class_requirement)), {}) as Dictionary
			requirements.append(str(item_class.get("name", "Class %d" % int(item.class_requirement))))
		item_body.text = "Damage  %d–%d                 Armor  +%d\n\nAccuracy  +%d                   Evade  +%d\n\nHP  +%d                              TP  +%d\n\n%s\n\nWeight  %d\n\nRequirements\n%s" % [int(item.get("min_damage", 0)), int(item.get("max_damage", 0)), int(item.get("armor", 0)), int(item.get("accuracy", 0)), int(item.get("evade", 0)), int(item.get("hp", 0)), int(item.get("tp", 0)), "   ·   ".join(bonuses), int(item.get("weight", 0)), "   ·   ".join(requirements) if not requirements.is_empty() else "None"]
	var p: Dictionary = game.online.player
	var stats: Dictionary = p.get("stats", {}) as Dictionary
	var hp: int = int(p.get("hp", 0))
	var max_hp: int = maxi(1, int(p.get("max_hp", 1)))
	var tp: int = int(p.get("tp", 0))
	var max_tp: int = maxi(1, int(p.get("max_tp", 1)))
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	tp_bar.max_value = max_tp
	tp_bar.value = tp
	hp_text.text = "HP  %d / %d" % [hp, max_hp]
	tp_text.text = "TP  %d / %d" % [tp, max_tp]
	level_text.text = "Level %d  ·  EXP %d" % [int(p.get("level", 0)), int(stats.get("experience", 0))]
	var classes: Dictionary = game.online.catalog.get("classes", {}) as Dictionary
	var profession: Dictionary = classes.get(str(int(stats.get("class_id", 0))), {}) as Dictionary
	summary.text = "%s  ·  Level %d  ·  %s\nHP %d / %d      TP %d / %d      EXP %d" % [str(p.get("name", "Player")), int(p.get("level", 0)), str(profession.get("name", "–")), hp, max_hp, tp, max_tp, int(stats.get("experience", 0))]
	points.text = "Stat points: %d     Skill points: %d" % [int(stats.get("stat_points", 0)), int(stats.get("skill_points", 0))]
	for index: int in range(ATTRIBUTES.size()):
		values[index].text = str(int(stats.get(ATTRIBUTES[index], 0)))
		add_buttons[index].disabled = int(stats.get("stat_points", 0)) <= 0 or not game.online._action_ready()
	details.text = "Damage      %d–%d\n\nAccuracy     %d\n\nEvade          %d\n\nArmor          %d\n\nMax SP        %d\n\nWeight        %d / %d\n\nKarma          %d" % [int(stats.get("min_damage", 0)), int(stats.get("max_damage", 0)), int(stats.get("accuracy", 0)), int(stats.get("evade", 0)), int(stats.get("armor", 0)), int(stats.get("max_sp", 0)), int(stats.get("weight", 0)), int(stats.get("max_weight", 0)), int(stats.get("karma", 0))]
