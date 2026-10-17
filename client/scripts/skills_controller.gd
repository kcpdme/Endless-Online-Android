extends RefCounted
## Native known-spell list, touch shortcuts and original GFX024 effect layers.
const CAST_POSE_MSEC: int = 480 # Original four120ms frames, after the local chant.
var game: Node
var panel: Control
var list: ItemList
var heading: Label
var detail: Label
var learn_button: Button
var forget_button: Button
var level_button: Button
var icons: Dictionary = {}
var buttons: Array[Button] = []
var slots: Array[int] = []
var selected: int = 0
var armed: int = 0
var casting: Dictionary = {}
var master: Dictionary = {}
var chants: Dictionary = {}
var effects: Array[Dictionary] = []
var ready_at: int = 0
var cast_hint: Label
var character_id: int = -1
var last_rows: String = ""

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	for index: int in range(3):
		var slot: int = index
		var button: Button = preload("res://scripts/hud_icon_button.gd").new() if index == 2 else Button.new()
		if index == 2: button.set("kind", "skills")
		button.position = [Vector2(-258, -318), Vector2(-166, -346), Vector2(-356, 24)][index]
		button.size = Vector2(68, 68)
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 38)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBoxFlat = game._style(Color(0.04, 0.10, 0.13, 0.48), Color(0.8, 0.86, 0.9, 0.65), 34)
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 10
			style.content_margin_bottom = 10
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(func() -> void: press(slot))
		parent.add_child(button)
		button.set_anchors_preset(Control.PRESET_TOP_RIGHT if index == 2 else Control.PRESET_BOTTOM_RIGHT, true)
		buttons.append(button)
		if index < 2:
			var cost: Label = game._label(button, "", Vector2(0, 50), 11, game.TEXT)
			cost.name = "TPCost"
			cost.size = Vector2(68, 16)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_hint = game._label(parent, "", Vector2(-250, -272), 18, game.GOLD)
	cast_hint.size = Vector2(500, 30)
	cast_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cast_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	cast_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = game._modal(parent, Vector2(850, 600))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	heading = game._label(card, "SKILLS", Vector2(30, 24), 28, game.GOLD)
	game._button(card, "×", Vector2(764, 18), Vector2(54, 48), func() -> void: panel.hide())
	list = ItemList.new()
	list.position = Vector2(30, 84)
	list.size = Vector2(360, 400)
	list.fixed_icon_size = Vector2i(32, 32)
	list.add_theme_font_size_override("font_size", 19)
	list.item_selected.connect(func(index: int) -> void:
		selected = int(list.get_item_metadata(index))
		refresh_detail()
	)
	card.add_child(list)
	detail = game._label(card, "", Vector2(414, 90), 18)
	detail.size = Vector2(404, 275)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_button = game._button(card, "Train +1", Vector2(414, 386), Vector2(190, 48), func() -> void: change("level"))
	learn_button = game._button(card, "Learn", Vector2(618, 386), Vector2(190, 48), func() -> void: change("learn"))
	forget_button = game._button(card, "Forget skill", Vector2(414, 446), Vector2(394, 46), func() -> void: change("forget"))
	for index: int in range(2):
		var slot: int = index
		game._button(card, "Set slot %d" % (index + 1), Vector2(30 + index * 398, 516), Vector2(380, 50), func() -> void:
			if not known(selected):
				game._toast("Learn this skill first.")
				return
			while slots.size() < 2: slots.append(0)
			var old: int = slots.find(selected)
			if old >= 0: slots[old] = slots[slot]
			slots[slot] = selected
			panel.hide()
			refresh()
		)
	panel.hide()

func info(ident: int) -> Dictionary:
	return (game.online.catalog.get("spells", {}) as Dictionary).get(str(ident), {}) as Dictionary

func icon(ident: int, highlight: bool = false) -> Texture2D:
	var key: String = "%d:%s" % [ident, str(highlight)]
	if icons.has(key): return icons[key] as Texture2D
	var texture: Texture2D = game._texture(str(info(ident).get("icon", "")))
	if texture == null: return null
	# Original GFX025 contains normal and hover halves, not one wide icon.
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float(texture.get_width()) / 2.0 if highlight else 0.0, 0, float(texture.get_width()) / 2.0, texture.get_height())
	icons[key] = atlas
	return atlas

func known(ident: int) -> bool:
	for spell: Dictionary in game.online.player.get("spells", []):
		if int(spell.id) == ident: return true
	return false

func press(index: int) -> void:
	if index == 2:
		game._cancel_controls()
		master.clear()
		last_rows = ""
		panel.show()
		refresh()
		return
	if index >= slots.size() or slots[index] == 0:
		press(2)
		return
	if not game.online.mobile_action_ready() or not casting.is_empty():
		game._toast("Wait until this skill is ready.")
		return
	if Time.get_ticks_msec() < ready_at:
		game._toast("Your skill is recovering.")
		return
	var spell: Dictionary = info(slots[index])
	if int(game.online.player.get("tp", 0)) < int(spell.get("tp", 0)):
		game._toast("Not enough TP.")
		return
	if int(spell.get("type", 2)) == 2 or int(spell.get("target", -1)) == 3:
		game._toast("This skill needs bard or party support, which is not available yet.")
		return
	game._release_attack()
	if int(spell.get("target", 0)) == 1:
		cast(slots[index], "self", 0)
		return
	armed = 0 if armed == slots[index] else slots[index]
	if armed > 0: game._toast("%s: tap %s to cast. Tap the skill again to cancel." % [str(spell.get("name", "Skill")), "a player (or yourself)" if int(spell.get("restrict", 0)) == 1 else "a monster"])
	refresh()

func contains(point: Vector2) -> int:
	for index: int in range(buttons.size()):
		if buttons[index].visible and buttons[index].get_global_rect().has_point(point): return index
	return -1

func target(tile: Vector2i) -> bool:
	if armed == 0: return false
	var spell: Dictionary = info(armed)
	if int(spell.get("restrict", 0)) == 1:
		for peer: Dictionary in [game.online.player] + game.online.players:
			if Vector2i(int(peer.x), int(peer.y)) == tile:
				cast(armed, "player", int(peer.player_id))
				return true
	else:
		for npc: Dictionary in game.online.npcs:
			if Vector2i(int(npc.x), int(npc.y)) == tile:
				cast(armed, "npc", int(npc.index))
				return true
	game._toast("Select a valid target for %s." % str(spell.get("name", "this skill")))
	return true

func cast(ident: int, kind: String, target_id: int) -> void:
	if not casting.is_empty() or Time.get_ticks_msec() < ready_at: return
	if not game.online.mobile_action_ready(): return
	var spell: Dictionary = info(ident)
	armed = 0
	if kind == "self" and int(spell.get("type", -1)) == 0 and int(game.online.player.get("hp", 0)) >= int(game.online.player.get("max_hp", 1)):
		flash_spell(ident, "HP full")
		refresh()
		return
	game._release_attack()
	armed = 0
	flash_spell(ident)
	var seconds: float = float(info(ident).get("cast_time", 1)) * 0.48
	casting = {"spell_id": ident, "until": Time.get_ticks_msec() + int(seconds * 1000), "seconds": seconds}
	ready_at = int(casting.until) + CAST_POSE_MSEC
	if game.online.session.request("spell_cast", {"spell_id": ident, "target_kind": kind, "target_id": target_id}) < 0: cancel_cast()
	refresh()

func cancel_cast() -> void:
	casting.clear()
	ready_at = 0
	chants.erase(int(game.online.player.get("player_id", -1)))

func receive(data: Dictionary) -> void:
	if data.has("casting"):
		if data.casting == null:
			casting.clear()
		elif casting.is_empty():
			casting = (data.casting as Dictionary).duplicate()
			casting["until"] = Time.get_ticks_msec() + int(float(casting.get("seconds", 0.48)) * 1000)
			ready_at = int(casting.until) + CAST_POSE_MSEC
	if data.has("skillmaster"): master = data.skillmaster as Dictionary if data.skillmaster is Dictionary else {}
	refresh()

func refresh() -> void:
	var active: bool = game.online_mode and game.online.active
	if not active:
		armed = 0
		cancel_cast()
		chants.clear()
		effects.clear()
	var identity: int = int(game.online.player.get("character_id", -1))
	if identity != character_id:
		character_id = identity
		ready_at = 0
		slots.clear()
		last_rows = ""
	var learned: Array = game.online.player.get("spells", []) as Array
	for index: int in range(slots.size()):
		if slots[index] != 0 and not known(slots[index]): slots[index] = 0
	for spell: Dictionary in learned:
		if slots.size() >= 2: break
		if not slots.has(int(spell.id)): slots.append(int(spell.id))
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		button.visible = active and game.started and not game._modal_open()
		var ident: int = slots[index] if index < slots.size() and index < 2 else 0
		var spell: Dictionary = info(ident)
		button.icon = icon(ident, armed == ident) if ident > 0 else null
		if index < 2: (button.get_node("TPCost") as Label).text = "TP %d" % int(spell.get("tp", 0)) if ident > 0 else ""
		button.text = "" if index == 2 else ("+" if ident == 0 else "")
		button.tooltip_text = "Skills" if index == 2 else str(spell.get("name", "Assign a skill"))
		button.modulate = Color("ffe39c") if armed == ident and ident > 0 else Color.WHITE
		button.disabled = index < 2 and (game.online.defeated or not casting.is_empty() or Time.get_ticks_msec() < ready_at)
	cast_hint.visible = active and game.started and not game._modal_open() and armed > 0
	if armed > 0: cast_hint.text = str(info(armed).get("name", "Skill")) + " · Choose a target"
	if not panel.visible: return
	heading.text = str(master.get("name", "SKILLS"))
	var rows: Dictionary = {}
	for spell: Dictionary in learned: rows[int(spell.id)] = spell
	for offer: Dictionary in master.get("offers", []): rows[int(offer.id)] = offer
	var stamp: String = JSON.stringify([rows, learned])
	if stamp != last_rows:
		last_rows = stamp
		list.clear()
		for ident: int in rows:
			var spell: Dictionary = info(ident)
			var row: int = list.add_item(str(spell.get("name", "Skill %d" % ident)) + ("  ✓" if known(ident) else ""), icon(ident))
			list.set_item_metadata(row, ident)
			if ident == selected: list.select(row)
		if selected == 0 and list.item_count > 0:
			list.select(0)
			selected = int(list.get_item_metadata(0))
	refresh_detail()

func refresh_detail() -> void:
	var spell: Dictionary = info(selected)
	var lines: Array[String] = [str(spell.get("name", "No learned skills yet"))]
	if not spell.is_empty():
		lines.append("TP %d   ·   Chant %.2fs" % [int(spell.get("tp", 0)), float(spell.get("cast_time", 1)) * 0.48])
		lines.append("Target: " + ("Yourself" if int(spell.get("target", 0)) == 1 else "Party" if int(spell.get("target", 0)) == 3 else "Friendly player" if int(spell.get("restrict", 0)) == 1 else "Monster"))
		for learned: Dictionary in game.online.player.get("spells", []):
			if int(learned.id) == selected: lines.append("Skill level %d" % int(learned.level))
		for offer: Dictionary in master.get("offers", []):
			if int(offer.id) != selected: continue
			lines.append("Learn: %d Gold · Level %d · Class %d (0 = any)" % [int(offer.cost), int(offer.level), int(offer.class_id)])
			for key: String in ["strength", "intelligence", "wisdom", "agility", "constitution", "charisma"]:
				if int(offer.get(key, 0)) > 0: lines.append("%s %d" % [key.capitalize(), int(offer[key])])
			for ident: Variant in offer.get("prerequisites", []):
				if int(ident) > 0: lines.append("Requires " + str(info(int(ident)).get("name", ident)))
	lines.append("Skill points: %d" % int((game.online.player.get("stats", {}) as Dictionary).get("skill_points", 0)))
	if master.is_empty(): lines.append("Visit a skill master to learn or forget skills.")
	detail.text = "\n".join(lines)
	level_button.disabled = not known(selected) or int((game.online.player.get("stats", {}) as Dictionary).get("skill_points", 0)) <= 0
	learn_button.disabled = master.is_empty() or selected == 0 or known(selected)
	forget_button.disabled = master.is_empty() or not known(selected)

func change(action: String) -> void:
	if selected == 0: return
	game.online.session.request("skill_" + action, {"spell_id": selected})

func flash_spell(ident: int, suffix: String = "") -> void:
	var text: String = str(info(ident).get("shout", info(ident).get("name", "Skill")))
	if not suffix.is_empty(): text += " · " + suffix
	game.online.chat_bubbles[int(game.online.player.get("player_id", 0))] = {"text": text, "until": Time.get_ticks_msec() + 900}

func event(event_data: Dictionary) -> void:
	var kind: String = str(event_data.get("kind", ""))
	var pid: int = int(event_data.get("player_id", 0))
	if kind == "spell_chant":
		chants[pid] = Time.get_ticks_msec() + int(float(event_data.get("seconds", 0.48)) * 1000) + 200
		var shout: String = str(info(int(event_data.get("spell_id", 0))).get("shout", ""))
		if not shout.is_empty(): game.online.chat_bubbles[pid] = {"text": shout, "until": int(chants[pid])}
		return
	if kind in ["spell_failed", "spell_cancelled"]:
		cancel_cast()
		chants.erase(pid)
		if kind == "spell_failed": game._toast(str(event_data.get("message", "Cast cancelled")))
		return
	if not event_data.has("spell_id") or kind not in ["npc_damage", "npc_killed", "spell_heal"]: return
	if int(event_data.get("player_id", -1)) == int(game.online.player.get("player_id", -2)) or bool(event_data.get("own_cast", false)):
		if int(casting.get("spell_id", -1)) == int(event_data.spell_id): casting.clear()
	var target_kind: String = "npc" if kind in ["npc_damage", "npc_killed"] else "player"
	var ident: int = int(event_data.get("npc_index", 0)) if target_kind == "npc" else int(event_data.get("target_id", pid))
	var at: Vector2 = game.tile_position(Vector2i(int(event_data.get("x", 0)), int(event_data.get("y", 0)))) if target_kind == "npc" else player_position(ident)
	var fx: Dictionary = (info(int(event_data.spell_id)).get("effect", {}) as Dictionary).duplicate(true)
	if not fx.is_empty():
		fx.merge({"kind": target_kind, "id": ident, "at": at, "start": Time.get_ticks_msec()})
		effects.append(fx)
	chants.erase(pid)
	if kind == "spell_heal" and int(event_data.get("hp_gain", 0)) > 0: game.damage_numbers.append({"position": at + Vector2(0, -62), "value": "+%d" % int(event_data.get("hp_gain", 0)), "time": 0.85})

func player_position(pid: int) -> Vector2:
	if pid == int(game.online.player.get("player_id", 0)): return game.player_world
	for peer: Dictionary in game.online.players:
		if int(peer.player_id) == pid: return game.tile_position(Vector2i(int(peer.x), int(peer.y)))
	return game.player_world

func is_chanting(pid: int) -> bool:
	if pid == int(game.online.player.get("player_id", -1)): return not casting.is_empty()
	return Time.get_ticks_msec() < int(chants.get(pid, 0))

func tick() -> void:
	for index: int in range(effects.size() - 1, -1, -1):
		var fx: Dictionary = effects[index]
		if Time.get_ticks_msec() - int(fx.start) >= int(fx.frames) * int(fx.loops) * 120: effects.remove_at(index)
	refresh()

func draw_effect(kind: String, ident: int, at: Vector2, front: bool) -> void:
	for fx: Dictionary in effects:
		if str(fx.kind) != kind or int(fx.id) != ident: continue
		fx.at = at
		draw_sheet(fx, front)

func draw_orphans() -> void:
	for fx: Dictionary in effects:
		if str(fx.kind) != "npc": continue
		var alive: bool = false
		for npc: Dictionary in game.online.npcs:
			if int(npc.index) == int(fx.id): alive = true
		if not alive:
			draw_sheet(fx, false)
			draw_sheet(fx, true)

func draw_sheet(fx: Dictionary, front: bool) -> void:
	var elapsed: int = maxi(0, Time.get_ticks_msec() - int(fx.start)) / 120
	var frame: int = elapsed % int(fx.frames)
	if int(fx.get("mode", 0)) == 3 and elapsed >= int(fx.frames): frame = 3 + ((elapsed - int(fx.frames)) % 2)
	frame = mini(frame, int(fx.frames) - 1)
	var shift: Vector2 = Vector2(float(fx.get("x", 0)), float(fx.get("y", 0)))
	if int(fx.get("mode", 0)) == 1: shift.y += elapsed * int(fx.get("adjust", 0))
	if int(fx.get("mode", 0)) == 2:
		shift += Vector2([-20, 0, 20, 0][frame % 4], [0, 14, 0, -14][frame % 4])
	for layer: int in ([1, 2] if front else [0]):
		var path: String = str((fx.get("paths", {}) as Dictionary).get(str(layer), ""))
		if path.is_empty(): continue
		var texture: Texture2D = game._texture(path)
		if texture == null: continue
		var width: float = float(texture.get_width()) / int(fx.frames)
		var height: float = texture.get_height()
		var at: Vector2 = (fx.at as Vector2) + Vector2(-width / 2.0, 20 - height + floorf((height - 100) / 2.0)) + shift
		game.draw_texture_rect_region(texture, Rect2(at, Vector2(width, height)), Rect2(Vector2(frame * width, 0), Vector2(width, height)), Color(1, 1, 1, 0.5 if layer == 1 else 1.0))
