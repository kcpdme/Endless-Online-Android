extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()})
		return calls.size()
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	if not ok: failed = true; push_error(reason)
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.music.stop()
	game.welcome.hide()
	game.online_mode = true
	game.started = true
	game.load_map(70)
	var c: Node = game.online
	c.session.queue_free()
	var wire: Capture = Capture.new()
	c.add_child(wire)
	wire.set_process(false)
	c.session = wire
	c.active = true
	c.streaming = true
	c.host_field.text = "wss://test.invalid/ws"
	c.player = {"name":"testhero","character_id":1,"player_id":100,"map_id":70,"x":6,"y":3,"hp":20,"max_hp":100,"tp":5,"max_tp":100,"gender":1,"level":120,"inventory":[{"id":1,"amount":10000},{"id":41,"amount":2},{"id":39,"amount":2},{"id":54,"amount":2},{"id":49,"amount":2},{"id":375,"amount":100},{"id":331,"amount":20}],"equipment":{},"spells":[{"id":1,"level":7},{"id":5,"level":3}],"stats":{"skill_points":5,"class_id":6,"strength":3000,"intelligence":3000,"wisdom":3000,"agility":3000,"constitution":3000,"charisma":3000}}
	game.player_tile = Vector2i(6,3)
	game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	game.quick_items.settings_path = "res://../work/v36-test-items.json"
	game.skills_ui.settings_path = "res://../work/v36-test-skills.json"
	for path: String in [game.quick_items.settings_path,game.skills_ui.settings_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	c.refresh_game_ui()
	game.skills_ui.refresh()
	await process_frame
	# Each paired category accepts a second identical copy, without removing the first.
	for row: Array in [[41,"ring1","ring2"],[39,"armlet1","armlet2"],[54,"bracer1","bracer2"]]:
		c.player.equipment = {row[1]:row[0]}
		game._select_item("item:%d" % int(row[0]))
		check(not game.equip_button.disabled,"A worn copy cannot disable Equip for an owned bag copy")
		c.equipment_request("item:%d" % int(row[0]))
		check(wire.calls.back().op == "equip" and int(wire.calls.back().fields.subloc) == 1,"Second identical copy must use native alternate slot")
		c.player.equipment = {row[1]:row[0],row[2]:row[0]}
		c.equipment_request(row[2])
		check(wire.calls.back().op == "unequip" and int(wire.calls.back().fields.subloc) == 1,"Paperdoll secondary slot must remove that slot only")
	# Gloves remain one native slot; replacing a pair must first remove the old pair.
	c.player.equipment = {"gloves":49}
	c.equipment_request("item:49")
	check(wire.calls.back().op == "unequip" and int(wire.calls.back().fields.subloc) == 0,"Gloves have exactly one original native equipment slot")
	c.pending_equip.clear()
	game.inventory.hide()
	game.character_panel.hide()
	# A native touch uses the sit HUD icon once and cannot start a world interaction.
	await process_frame
	var before: int = wire.calls.size()
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 12; touch.pressed = true; touch.position = game.sit_button.get_global_rect().get_center()
	game._input(touch)
	check(wire.calls.size() == before + 1 and wire.calls.back().op == "sit","Sit icon must send exactly one native request")
	touch.pressed = false; game._input(touch)
	check(c.interaction.is_empty(),"Sit icon cannot leak through to an NPC")
	# Settings survive disconnection, a new numeric ID, and app reconstruction.
	game.quick_items.selected_slot = 0; game.quick_items.assign(331)
	game.quick_items.selected_slot = 1; game.quick_items.assign(375)
	game.skills_ui.slots.assign([5,1])
	game.skills_ui.Store.write_slots(game.skills_ui.settings_path,c.profile_identity(),game.skills_ui.slots)
	var identity: String = c.profile_identity()
	c.active = false; game.quick_items.refresh(); game.skills_ui.refresh()
	check(game.quick_items.slots == [331,375],"Disconnect cannot erase configured item bindings")
	c.active = true; c.player.character_id = 999
	game.quick_items.identity = ""; game.skills_ui.shortcut_identity = ""
	game.quick_items.refresh(); game.skills_ui.refresh()
	check(c.profile_identity() == identity and game.quick_items.slots == [331,375] and game.skills_ui.slots == [5,1],"A new login ID must restore both item and skill bindings")
	c.player.name = "otherhero"; game.quick_items.refresh(); game.skills_ui.refresh()
	game.quick_items.selected_slot = 0;game.quick_items.assign(375)
	c.player.name = "testhero";game.quick_items.refresh();game.skills_ui.refresh()
	check(game.quick_items.slots == [331,375],"Different characters cannot overwrite one another’s slots")
	# Detail changes only after the native training acknowledgement.
	var skills: RefCounted = game.skills_ui
	skills.panel.show()
	skills.selected = 1; skills.refresh_detail()
	check(skills.detail.text.contains("Heals 11 HP") and skills.detail.text.contains("12 HP (+1)"),"Self Heal details must include the trained bonus and next level")
	c.player.spells[0].level = 8; skills.receive({})
	check(skills.detail.text.contains("Heals 12 HP") and skills.detail.text.contains("13 HP (+1)"),"Native Train +1 must refresh actual healing")
	skills.selected = 5; skills.refresh_detail()
	check(skills.detail.text.contains("Spell damage bonus") and skills.detail.text.contains("(+1)"),"Damage spells must show current and next native bonuses")
	skills.panel.hide()
	# Original inn service uses NPC dialogue, a price quote, then payment.
	c.npcs.assign([{"id":150,"index":7,"x":6,"y":1,"direction":0}])
	c.map_click(Vector2i(6,1),"npc"); c._process_interaction()
	check(wire.calls.back().op == "inn_open","Innkeeper tap must open the original Citizen service")
	game.inn_ui.receive({"inn":{"npc_id":150,"npc_index":7,"vendor_id":2,"session_id":0}})
	check(game.inn_ui.panel.visible,"Innkeeper must show sleep dialogue")
	game.inn_ui.sleep_button.pressed.emit()
	check(wire.calls.back().op == "inn_quote","Sleep must quote before charging Gold")
	game.inn_ui.receive({"inn":{"npc_id":150,"npc_index":7,"vendor_id":2,"session_id":0,"cost":90}})
	check(game.inn_ui.detail.text.contains("90 Gold"),"Native sleep cost must be visible")
	game.inn_ui.sleep_button.pressed.emit()
	check(wire.calls.back().op == "inn_sleep","Confirmed quote must send original sleep purchase")
	game._handle_back()
	check(not game.inn_ui.panel.visible and wire.calls.back().op == "inn_close","Android Back cancels inn without payment")
	if DisplayServer.get_name() != "headless":
		game.skills_ui.panel.show();game.skills_ui.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../work/v36-skills-details.png")
	print("V36 FEATURES ","FAIL" if failed else "PASS",": native sit touch, paired slots, single gloves, item/skill reconnect persistence, trained effect details, native inn quote and sleep")
	for path: String in [game.quick_items.settings_path,game.skills_ui.settings_path]: DirAccess.remove_absolute(path)
	game.started = false;game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)
