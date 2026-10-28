extends RefCounted
const PET_DETAILS = preload("res://scripts/pet_details.gd")
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
var area_bursts: Array[Dictionary] = []
const ICE_BLAST_IDS: Array[int] = [14, 21]
var ready_at: int = 0
var cast_hint: Label
var character_id: int = -1
var shortcut_identity: String = ""
var settings_path: String = "user://quick_skills.json"
const Store = preload("res://scripts/shortcut_store.gd")
var last_rows: String = ""
var target_panel: Control
var target_list: ItemList
var bard_panel: Control

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	for index: int in range(3):
		var slot: int = index
		var button: Button = preload("res://scripts/hud_icon_button.gd").new() if index == 2 else Button.new()
		if index == 2: button.set("kind", "skills")
		button.position = [Vector2(-258, -318), Vector2(-166, -346), Vector2(-446, 24)][index]
		if index < 2: button.position += game.COMBAT_HUD_SHIFT
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
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.position = Vector2(414, 90)
	detail_scroll.size = Vector2(404, 235)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(detail_scroll)
	detail = game._label(detail_scroll, "", Vector2.ZERO, 18)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			game.online.shortcuts.save_slots("skills", settings_path, shortcut_identity, slots)
			panel.hide()
			refresh()
		)
	game._button(card,"Reset all…",Vector2(414,340),Vector2(394,38),func() -> void:
		if master.is_empty():game._toast("Visit a skill master first.");return
		panel.hide();game.feature_ui.open("reset",{"npc_index":int(master.npc_index)})
	)
	panel.hide()
	_build_targeting(parent)

func info(ident: int) -> Dictionary:
	return (game.online.catalog.get("spells", {}) as Dictionary).get(str(ident), {}) as Dictionary

func area_skill(ident: int) -> bool:
	return int(info(ident).get("area_radius", 0)) > 0 if int(game.online.catalog.get("balance_version", 0)) > 0 else ident in ICE_BLAST_IDS

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
	if not usable(slots[index]):
		game._toast("This skill is locked for your current class or level.")
		return
	var spell: Dictionary = info(slots[index])
	if int(game.online.player.get("tp", 0)) < int(spell.get("tp", 0)):
		game._toast("Not enough TP.")
		return
	if int(spell.get("type", 2)) == 2:
		open_bard()
		return
	if int(spell.get("target", -1)) == 3:
		if game.party_ui.party.is_empty(): game._toast("Join a party before casting this group heal."); return
		cast(slots[index], "group", 0)
		return
	game._release_attack()
	if game.sfx != null: game.sfx.play_named("SpellActivate", "skill_select")
	if area_skill(slots[index]):
		cast(slots[index], "area", 0)
		return
	if int(spell.get("target", 0)) == 1:
		cast(slots[index], "self", 0)
		return
	armed = 0 if armed == slots[index] else slots[index]
	if armed > 0 and int(spell.get("restrict",0)) == 1:
		game._toast("Tap yourself or another player to heal. Tap the skill again to cancel.")
		refresh()
		return
	if armed > 0: game._toast("%s: tap %s to cast. Tap the skill again to cancel." % [str(spell.get("name", "Skill")), "a player (or yourself)" if int(spell.get("restrict", 0)) == 1 else "a monster or player in this PK area" if int(spell.get("restrict",0))==2 and bool(game.online.world_rules.get("pk",false)) else "a monster"])
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
		if int(spell.get("restrict",0)) == 2 and bool(game.online.world_rules.get("pk",false)):
			for peer: Dictionary in game.online.players:
				if int(peer.player_id) != int(game.online.player.player_id) and Vector2i(int(peer.x),int(peer.y)) == tile:
					cast(armed,"player",int(peer.player_id)); return true
		for npc: Dictionary in game.online.npcs:
			if Vector2i(int(npc.x), int(npc.y)) == tile:
				if not game.online.is_combat_npc(npc):
					game._toast("Only monsters can be targeted by this skill.")
					return true
				cast(armed, "npc", int(npc.index))
				return true
	game._toast("Select a valid target for %s." % str(spell.get("name", "this skill")))
	return true

func class_usable(ident: int) -> bool:
	var stats: Dictionary = game.online.player.get("stats", {}) as Dictionary
	if int(stats.get("admin", 0)) > 0: return true
	var allowed: Array = info(ident).get("allowed_classes", []) as Array
	if allowed.is_empty(): return true
	var profession: int = int(stats.get("class_id", 0))
	var base: int = int((game.online.catalog.classes as Dictionary).get(str(profession), {}).get("base", 0))
	# JSON arrays contain floats; Array.has uses strict Variant types.
	for required: Variant in allowed:
		if int(required) == profession or (int(required) > 0 and int(required) == base): return true
	return false

func usable(ident: int) -> bool:
	if int(game.online.catalog.get("balance_version", 0)) < 2: return true
	var stats: Dictionary = game.online.player.get("stats", {}) as Dictionary
	if int(stats.get("admin", 0)) > 0: return true
	return int(stats.get("level", 0)) >= int(info(ident).get("level_requirement", 1)) and class_usable(ident)

func cast(ident: int, kind: String, target_id: int) -> void:
	if not casting.is_empty() or Time.get_ticks_msec() < ready_at: return
	if not usable(ident):
		game._toast("This skill is locked for your current class or level.")
		return
	if not game.online.mobile_action_ready(): return
	var spell: Dictionary = info(ident)
	if kind == "npc":
		var target_npc: Dictionary = {}
		for npc: Dictionary in game.online.npcs:
			if int(npc.get("index", -1)) == target_id: target_npc = npc; break
		if not game.online.is_combat_npc(target_npc):
			game._toast("Only monsters can be targeted by this skill.")
			return
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
		target_panel.hide(); bard_panel.hide()
		armed = 0
		cancel_cast()
		chants.clear()
		effects.clear()
	var identity: String = game.online.profile_identity()
	var learned: Array = game.online.player.get("spells", []) as Array
	if not identity.is_empty() and identity != shortcut_identity:
		shortcut_identity = identity
		character_id = int(game.online.player.get("character_id", -1))
		ready_at = 0
		last_rows = ""
		var defaults: Array[int] = [0, 0]
		for spell: Dictionary in learned:
			var index: int = defaults.find(0)
			if index < 0: break
			if not defaults.has(int(spell.id)): defaults[index] = int(spell.id)
		slots.assign(game.online.shortcuts.load_slots("skills", settings_path, identity, defaults))
	# Only an authoritative learned list can invalidate an unlearned skill.
	if active and game.online.player.has("spells"):
		for index: int in range(slots.size()):
			if slots[index] != 0 and not known(slots[index]):
				slots[index] = 0
				game.online.shortcuts.save_slots("skills", settings_path, shortcut_identity, slots)
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
	for offer: Dictionary in master.get("offers", []):
		if int(game.online.catalog.get("balance_version", 0)) > 0 and not class_usable(int(offer.id)): continue
		rows[int(offer.id)] = offer
	var stamp: String = JSON.stringify([rows, learned])
	if stamp != last_rows:
		last_rows = stamp
		list.clear()
		for ident: int in rows:
			var spell: Dictionary = info(ident)
			var row: int = list.add_item(str(spell.get("name", "Skill %d" % ident)) + ("  🔒" if not usable(ident) else "  ✓" if known(ident) else ""), icon(ident))
			list.set_item_metadata(row, ident)
			if ident == selected: list.select(row)
		if selected == 0 and list.item_count > 0:
			list.select(0)
			selected = int(list.get_item_metadata(0))
	refresh_detail()

func refresh_detail() -> void:
	var spell: Dictionary = info(selected)
	var balanced: bool = int(game.online.catalog.get("balance_version", 0)) > 0
	var cap: int = int(spell.get("max_level", 100)) if balanced else 100
	var stats: Dictionary = game.online.player.get("stats", {}) as Dictionary
	var profession: Dictionary = (game.online.catalog.get("classes", {}) as Dictionary).get(str(int(stats.get("class_id", 0))), {}) as Dictionary
	var lines: Array[String] = [str(spell.get("name", "No learned skills yet"))]
	if not spell.is_empty():
		lines.append("TP %d   ·   Chant %.2fs" % [int(spell.get("tp", 0)), float(spell.get("cast_time", 1)) * 0.48])
		var area_text: String = "Up to %d monsters within %d tiles" % [int(spell.get("area_targets", 5)), int(spell.get("area_radius", 2))]
		lines.append("Target: " + (area_text if area_skill(selected) else "Yourself" if int(spell.get("target", 0)) == 1 else "Nearby party" if int(spell.get("target", 0)) == 3 else "Friendly player" if int(spell.get("restrict", 0)) == 1 else "Monster"))
		if balanced and not usable(selected): lines.append("Locked for your current class or level. Learned ownership is kept.")
		if balanced:
			lines.append("Requires level %d" % int(spell.get("level_requirement", 1)))
			if spell.has("learn_source"): lines.append(str(spell.learn_source))
			if spell.get("requires_bow", false): lines.append("Requires a bow and arrows.")
			if spell.get("weapon_range", false): lines.append("Range: %d tiles with your current bow and arrows." % int((game.online.player.get("combat", {}) as Dictionary).get("range_tiles", 1)))
			elif int(spell.get("range", 0)) > 0: lines.append("Range: %d tiles." % int(spell.range))
		if spell.get("effect_kind", "") == "companion":
			var pet: Dictionary = spell.get("companion", {}) as Dictionary
			if pet.has("tier"): lines.append(PET_DETAILS.combat_text(pet))
			lines.append("Dismiss your companion; the living bond is kept." if int(pet.get("npc_id", 0)) < 0 else "One strong spirit while upkeep TP lasts. Your death breaks its bond: hatch another egg afterward. Travel and logout keep the bond. Assists active fights; no idle hunting." if bool(spell.get("bond_lost_on_death", false)) else "One spirit companion while upkeep TP lasts. Assists your active fights; no idle hunting.")
			if int(pet.get("npc_id", 0)) > 0: lines.append("Upkeep: %d TP every 2 seconds. CHA and INT increase its damage." % int(pet.get("upkeep", 0)))
		for learned: Dictionary in game.online.player.get("spells", []):
			if int(learned.id) == selected:
				var level: int = int(learned.level)
				lines.append("Skill level %d / %d" % [level, cap])
				if balanced and level > cap: lines.append("Power is capped at %d. A free rebuild refunds your old training." % cap)
				if int(spell.get("type", -1)) == 0:
					var heal: int = int(spell.get("hp", 0)) + level
					if balanced:
						heal = int(spell.get("hp", 0)) + mini(level, cap) * 2 + int(float(stats.get("wisdom", 0)) * float(profession.get("heal_wis", 0)) + float(stats.get("intelligence", 0)) * float(profession.get("heal_int", 0)) + float(stats.get("charisma", 0)) * float(profession.get("heal_cha", 0)))
					lines.append("Heals %d HP" % heal)
					if level < cap: lines.append("Next level: %d HP (+%d)" % [heal + (2 if balanced else 1), 2 if balanced else 1])
				elif int(spell.get("type", -1)) == 1 and spell.get("effect_kind", "") != "companion":
					var low: int = int(spell.get("min_damage", 0)) + level
					var high: int = int(spell.get("max_damage", 0)) + level
					if balanced:
						var scale: float = maxf(1.0, float(profession.get("pk_spell_scale", profession.get("spell_scale", 1.0)) if bool(game.online.world_rules.get("pk", false)) else profession.get("spell_scale", 1.0)))
						var area_scale: float = float(spell.get("area_scale", 1.0))
						low = int((int(float(stats.get("min_damage", 0)) * scale) + int(spell.get("min_damage", 0)) + mini(level, cap) * 2) * area_scale)
						high = int((int(float(stats.get("max_damage", 0)) * scale) + int(spell.get("max_damage", 0)) + mini(level, cap) * 2) * area_scale)
						lines.append("Attack power %d–%d before defence and hit chance." % [low, high])
						if level < cap: lines.append("Training adds up to 2 power before area scaling.")
					else:
						lines.append("Spell damage bonus %d–%d" % [low, high])
						if level < cap: lines.append("Next level: %d–%d (+1)" % [low + 1, high + 1])
						lines.append("Adds to attack damage; defence and hit chance apply.")
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
	var at_cap: bool = false
	for learned: Dictionary in game.online.player.get("spells", []):
		if int(learned.id) == selected and int(learned.level) >= cap: at_cap = true
	level_button.disabled = at_cap or not known(selected) or int((game.online.player.get("stats", {}) as Dictionary).get("skill_points", 0)) <= 0
	learn_button.disabled = master.is_empty() or selected == 0 or known(selected)
	forget_button.disabled = master.is_empty() or not known(selected)

func change(action: String) -> void:
	if selected == 0: return
	game.online.session.request("skill_" + action, {"spell_id": selected})

func flash_spell(ident: int, suffix: String = "") -> void:
	var text: String = str(info(ident).get("shout", info(ident).get("name", "Skill")))
	if not suffix.is_empty(): text += " · " + suffix
	game.online.spell_labels[int(game.online.player.get("player_id", 0))] = {"text": text, "spell": true, "start": Time.get_ticks_msec(), "until": Time.get_ticks_msec() + 900}

func event(event_data: Dictionary) -> void:
	var kind: String = str(event_data.get("kind", ""))
	var pid: int = int(event_data.get("player_id", 0))
	if kind == "skill_changed" and str(event_data.get("action", "")) == "trained":
		var trained: Dictionary = info(int(event_data.spell_id))
		game._toast("%s · Level %d · +1 %s" % [str(trained.get("name", "Skill")), int(event_data.level), "HP healing" if int(trained.get("type", -1)) == 0 else "spell damage"])
		refresh_detail()
	if kind == "spell_chant":
		chants[pid] = Time.get_ticks_msec() + int(float(event_data.get("seconds", 0.48)) * 1000) + 200
		var shout: String = str(info(int(event_data.get("spell_id", 0))).get("shout", ""))
		if not shout.is_empty(): game.online.spell_labels[pid] = {"text": shout, "spell": true, "start": Time.get_ticks_msec(), "until": int(chants[pid])}
		return
	if kind in ["spell_failed", "spell_cancelled"]:
		cancel_cast()
		chants.erase(pid)
		if kind == "spell_failed": game._toast(str(event_data.get("message", "Cast cancelled")))
		return
	if kind == "bard_note":
		if game.sfx != null: game.sfx.bard(int(event_data.instrument), int(event_data.note))
		game.online.peer_attacks[pid] = {"until": Time.get_ticks_msec()/1000.0 + 0.48, "direction": int(event_data.get("direction",0))}
		if pid == int(game.online.player.get("player_id",-1)): game.swing_clock = 0.48
		game.drink_effects.event({"kind":"player_emote","player_id":pid,"emote":15})
		return
	if kind == "spell_group":
		for member: Dictionary in event_data.get("targets",[]):
			event({"kind":"spell_heal", "player_id":pid,"target_id":int(member.player_id),"spell_id":int(event_data.spell_id),"hp_gain":int(event_data.get("hp_gain",0))})
		return
	if kind == "spell_area":
		if pid == int(game.online.player.get("player_id", -1)): casting.clear()
		chants.erase(pid)
		area_bursts.append({"tile": Vector2i(int(event_data.x), int(event_data.y)), "start": Time.get_ticks_msec()})
		if game.sfx != null: game.sfx.effect(int(info(int(event_data.spell_id)).get("graphic", 0)))
		if int(event_data.get("targets", 0)) == 0:
			var empty_fx: Dictionary = (info(int(event_data.spell_id)).get("effect", {}) as Dictionary).duplicate(true)
			if not empty_fx.is_empty():
				empty_fx.merge({"kind": "player", "id": pid, "at": player_position(pid), "start": Time.get_ticks_msec()})
				effects.append(empty_fx)
		return
	if not event_data.has("spell_id") or kind not in ["npc_damage", "npc_killed", "spell_heal"]: return
	if int(event_data.get("player_id", -1)) == int(game.online.player.get("player_id", -2)) or bool(event_data.get("own_cast", false)):
		if int(casting.get("spell_id", -1)) == int(event_data.spell_id): casting.clear()
	var target_kind: String = "npc" if kind in ["npc_damage", "npc_killed"] else "player"
	var ident: int = int(event_data.get("npc_index", 0)) if target_kind == "npc" else int(event_data.get("target_id", pid))
	var at: Vector2 = game.tile_position(Vector2i(int(event_data.get("x", 0)), int(event_data.get("y", 0)))) if target_kind == "npc" else player_position(ident)
	if game.sfx != null and not area_skill(int(event_data.spell_id)): game.sfx.effect(int(info(int(event_data.spell_id)).get("graphic", 0)))
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

func draw_area() -> void:
	var now: int = Time.get_ticks_msec()
	for burst: Dictionary in area_bursts:
		var elapsed: float = float(now - int(burst.start)) / 840.0
		if elapsed < 0.0 or elapsed >= 1.0: continue
		var alpha: float = (1.0 - elapsed) * 0.34
		for x: int in range(-2, 3):
			for y: int in range(-2, 3):
				var center: Vector2 = game.tile_position((burst.tile as Vector2i) + Vector2i(x, y))
				var radius: float = 0.7 + sin(elapsed * PI) * 0.25
				var points: PackedVector2Array = PackedVector2Array([center + Vector2(0, -15) * radius, center + Vector2(30, 0) * radius, center + Vector2(0, 15) * radius, center + Vector2(-30, 0) * radius])
				game.draw_colored_polygon(points, Color(0.62, 0.89, 1.0, alpha))
				game.draw_line(center + Vector2(-4, -4), center + Vector2(4, 4), Color(0.84, 0.97, 1.0, alpha * 2), 1.0)
				game.draw_line(center + Vector2(4, -4), center + Vector2(-4, 4), Color(0.84, 0.97, 1.0, alpha * 2), 1.0)

func tick() -> void:
	for index: int in range(area_bursts.size() - 1, -1, -1):
		if Time.get_ticks_msec() - int(area_bursts[index].start) >= 840: area_bursts.remove_at(index)
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

func _build_targeting(parent: Control) -> void:
	target_panel = game._modal(parent,Vector2(620,460))
	var card: Control = target_panel.get_child(0)
	game._wood_card(card)
	game._label(card,"CHOOSE A HEAL TARGET",Vector2(28,22),25,game.GOLD)
	game._button(card,"×",Vector2(540,14),Vector2(54,48),func() -> void: target_panel.hide(); armed = 0)
	target_list = ItemList.new(); target_list.position = Vector2(28,82); target_list.size = Vector2(564,242); target_list.add_theme_font_size_override("font_size",22); card.add_child(target_list)
	game._button(card,"Heal selected player",Vector2(28,340),Vector2(564,48),func() -> void:
		var selected_rows: PackedInt32Array = target_list.get_selected_items()
		if selected_rows.is_empty(): return
		var pid: int = int(target_list.get_item_metadata(selected_rows[0])); var ident: int = armed
		target_panel.hide(); cast(ident,"player",pid)
	,true)
	game._button(card,"Choose in the world",Vector2(28,398),Vector2(564,40),func() -> void: target_panel.hide(); game._toast("Tap a player, including your own character, to heal."))
	target_panel.hide()
	bard_panel = game._modal(parent,Vector2(800,410))
	card = bard_panel.get_child(0); game._wood_card(card)
	game._label(card,"BARD · THREE OCTAVES",Vector2(28,20),25,game.GOLD)
	game._button(card,"×",Vector2(720,14),Vector2(54,48),func() -> void: bard_panel.hide())
	game._label(card,"Equip a Harp or Guitar, then tap a note.",Vector2(28,66),18,game.MUTED)
	var notes: Array[String] = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
	for octave: int in range(3):
		for pitch: int in range(12):
			var note: int = octave*12+pitch
			game._button(card,notes[pitch]+str(octave+1),Vector2(28+pitch*62,116+octave*84),Vector2(56,72),func() -> void: game.online.session.request("bard_note",{"note":note}))
	bard_panel.hide()

func open_targets() -> void:
	game._cancel_controls()
	target_list.clear()
	var seen: Array[int] = []
	for peer: Dictionary in [game.online.player] + game.online.players:
		var pid: int = int(peer.get("player_id",0))
		if pid in seen: continue
		seen.append(pid)
		var own: bool = pid == int(game.online.player.get("player_id",-1))
		var row: int = target_list.add_item(str(peer.get("name","Player")) + (" · Yourself" if own else ""))
		target_list.set_item_metadata(row,pid)
		if own: target_list.select(row)
	target_panel.show()

func open_bard() -> void:
	game._cancel_controls()
	panel.hide(); bard_panel.show()
