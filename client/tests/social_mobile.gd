extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		serial += 1; calls.append({"op":op,"fields":fields.duplicate()}); return serial
var failed: bool = false
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(reason)
func press_text(parent: Node, text: String) -> void:
	for button: Node in parent.find_children("*","Button",true,false):
		if button.text == text: button.pressed.emit(); return
	check(false,"Missing button: "+text)
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	for button: Node in game.welcome.find_children("*","Button",true,false): check(not button.text.to_lower().contains("offline"),"Offline entry remains visible")
	game._begin_play(); check(game.online.panel.visible and not game.started,"Entry opens online login")
	var c: Node = game.online; c.session.queue_free(); var wire: Capture = Capture.new(); c.add_child(wire); wire.set_process(false); c.session = wire
	c._show_characters([{"id":10,"name":"one","gender":0,"race":3,"hairstyle":7,"haircolor":8,"level":50,"equipment_graphics":[1,40,44,1,33]},{"id":20,"name":"two","gender":1,"race":1,"hairstyle":2,"haircolor":1,"level":5,"equipment_graphics":[1,1,0,0,21]}])
	check(c.selection_previews.size() == 2,"Each native login character has a preview")
	var record: Dictionary = c.selection_previews[0].appearance_record()
	check(record.equipment_graphics == [1,0,0,0,40,0,44,1,33] and record.race == 3 and record.hairstyle == 7,"Preview preserves actual native appearance and BAHSW equipment")
	check(not c.character_graphic(record).is_empty(),"Actual equipment preview resolves imported layers")
	c.character_cards.get_child(1).pressed.emit(); c._enter_selected()
	check(wire.calls.back().op == "enter" and int(wire.calls.back().fields.character_id) == 20,"Card selects native ID and enters selected character")
	c.panel.hide(); game.welcome.hide(); c.active = true; game.online_mode = true; game.started = true
	c.player = {"name":"actor","player_id":100,"character_id":1,"x":40,"y":40,"map_id":5,"tp":100,"hp":1,"max_hp":100,"inventory":[],"spells":[{"id":6},{"id":8},{"id":3},{"id":17}],"equipment":{}}
	c.players.assign([{"name":"peer","player_id":200,"x":41,"y":40}]); c.host_field.text = "wss://test.invalid/ws"
	var skills: RefCounted = game.skills_ui; skills.settings_path = "user://social-test-skills.json"; skills.shortcut_identity = c.profile_identity()
	game.player_tile = Vector2i(40,40); game.player_world = game.tile_position(game.player_tile)
	for ident: int in [6,8]:
		skills.slots.assign([ident,0]); skills.ready_at = 0; skills.casting.clear(); skills.press(0)
		check(skills.target_panel.visible and skills.target_list.item_count == 2,"Target heal offers self and nearby player")
		for index: int in range(2):
			if index == 1: skills.casting.clear(); skills.ready_at = 0; skills.press(0)
			skills.target_list.select(index); press_text(skills.target_panel,"Heal selected player")
			check(wire.calls.back().op == "spell_cast" and wire.calls.back().fields.target_kind == "player" and int(wire.calls.back().fields.target_id) == (100 if index == 0 else 200),"Heal sends correct native player target")
		skills.casting.clear(); skills.ready_at = 0
	skills.armed = 6
	var hit: Dictionary = c.map_entity_target(game.player_world+Vector2(0,-45))
	check(hit.get("kind") == "player" and hit.tile == Vector2i(40,40),"Own visible sprite is a reliable healing target")
	skills.armed = 0; skills.slots.assign([3,0]); skills.press(0)
	check(skills.casting.is_empty(),"Group heal requires actual party membership")
	game.party_ui.receive({"party":[{"name":"actor","player_id":100,"leader":true,"level":5,"hp_percent":1},{"name":"peer","player_id":200,"leader":false,"level":5,"hp_percent":30}]})
	skills.press(0); check(wire.calls.back().fields.target_kind == "group","Party heal casts without selecting player")
	skills.casting.clear(); skills.ready_at = 0; skills.slots.assign([17,0]); skills.press(0)
	check(skills.bard_panel.visible,"Bard opens instrument keyboard")
	var notes: int = 0
	for button: Node in skills.bard_panel.find_children("*","Button",true,false):
		if button.text != "×": notes += 1
	check(notes == 36,"Bard exposes all 36 original notes")
	press_text(skills.bard_panel,"C1"); check(wire.calls.back().op == "bard_note" and int(wire.calls.back().fields.note) == 0,"Bard sends native note number")
	skills.bard_panel.hide(); skills.event({"kind":"spell_group","player_id":100,"spell_id":3,"hp_gain":20,"targets":[{"player_id":100},{"player_id":200}]})
	check(skills.effects.size() >= 2,"Group heal renders effects on each recipient")
	game.party_ui.receive({"party_invitation":{"type":1,"name":"peer","player_id":200,"expires":1234}})
	check(game.party_ui.panel.visible and game.party_ui.accept_button.visible,"Party invitation opens an accept/decline prompt")
	press_text(game.party_ui.panel,"Accept request"); check(wire.calls.back().op == "party_accept","Invitation approval sends native acceptance")
	game.party_ui.action("kick",200); check(wire.calls.back().op == "party_kick" and int(wire.calls.back().fields.player_id) == 200,"Leader remove UI addresses selected member")
	game.party_ui.chat.text = "hello"; game.party_ui.send_chat(); check(wire.calls.back().fields.channel == "party","Party chat uses party channel")
	c.log_out(); check(not c.active and not game.started and not game.party_ui.panel.visible,"Logout clears party and ends gameplay")
	var screenshot: String = OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if not screenshot.is_empty() and DisplayServer.get_name() != "headless":
		c.show_login(); c._show_characters([{"id":10,"name":"one","gender":0,"race":3,"hairstyle":7,"haircolor":8,"level":50,"equipment_graphics":[1,40,44,1,33]}]); await process_frame; await process_frame; root.get_texture().get_image().save_png(screenshot)
	var report: Dictionary = {"result":"passed" if not failed else "failed","checks":checks,"target_heals_choose_self_or_player":true,"party_and_group_heal_ui":true,"bard_36_note_keyboard":true,"login_real_appearance_and_equipment":true,"online_only_entry":true}
	var path: String = OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not path.is_empty(): var f: FileAccess = FileAccess.open(path,FileAccess.WRITE); f.store_string(JSON.stringify(report,"  ")+"\n")
	print("SOCIAL MOBILE: ",JSON.stringify(report)); game.queue_free(); await process_frame; await process_frame; quit(1 if failed else 0)
