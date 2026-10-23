extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op":op,"fields":fields.duplicate()}); return calls.size()
var checks: int = 0
var failed: bool = false
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func _initialize() -> void: call_deferred("run")
func tap(control: Control) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = 77; event.position = control.get_global_rect().get_center(); event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame
func run() -> void:
	root.size = Vector2i(1544,720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game); await process_frame
	game.set_process(false); game.music.stop(); game.started = true; game.welcome.hide(); game.online_mode = true
	var c: Node = game.online; c.set_process(false); c.session.queue_free()
	var wire: Capture = Capture.new(); c.add_child(wire); wire.set_process(false); c.session = wire
	c.active = true; c.streaming = true
	c.player = {"name":"devfixture","player_id":100,"character_id":1,"map_id":5,"x":40,"y":40,"hp":100,"max_hp":100,"tp":100,"max_tp":100,"level":120,"gender":1,"inventory":[{"id":210,"amount":2}],"equipment":{},"spells":[{"id":14,"level":7},{"id":21,"level":7}],"stats":{}}
	game.skills_ui.slots.assign([14,21]); game.skills_ui.shortcut_identity = c.profile_identity(); game.skills_ui.refresh()
	for slot: int in range(2):
		game.skills_ui.ready_at = 0; game.skills_ui.casting.clear(); wire.calls.clear()
		await tap(game.skills_ui.buttons[slot])
		check(wire.calls.size() == 1 and wire.calls[0].op == "spell_cast", "One skill touch sends one request")
		if not wire.calls.is_empty(): check(str(wire.calls[0].fields.target_kind) == "area" and int(wire.calls[0].fields.target_id) == 0, "Ice Blast cannot require a selected opponent")
		check(game.skills_ui.armed == 0, "Ice Blast must not arm target selection")
		check(int(c.player.tp) == 100, "No optimistic TP spending")
		game.skills_ui.event({"kind":"spell_area","spell_id":14 if slot==0 else 21,"player_id":100,"x":40,"y":40,"targets":0})
		check(game.skills_ui.casting.is_empty() and not game.skills_ui.area_bursts.is_empty(), "Native empty-area completion clears cast and draws frost")
	game.skills_ui.ready_at = 0; game.skills_ui.casting.clear(); wire.calls.clear()
	game.inventory.show(); game._select_item("item:210"); game._refresh_ui(); await process_frame
	check(game.equip_button.text == "Use" and not game.equip_button.disabled, "Fairy Soda Use works at full HP and TP")
	await tap(game.equip_button)
	check(wire.calls.size() == 1 and wire.calls[0].op == "item_use" and int(wire.calls[0].fields.item_id) == 210, "Actual bag Use sends native drink request")
	check(not game.drink_effects.drunk() and c.bag_amount(210) == 2, "Never consume or make drunk before native ACK")
	c.player.inventory = [{"id":210,"amount":1}]
	c._process_events([{"kind":"player_emote","player_id":100,"emote":11},{"kind":"item_used","item_id":210,"item_type":22,"consumed":1,"remaining":1,"drunk_seconds":25}])
	check(game.drink_effects.drunk() and game.drink_effects.emotes.has(100), "Native drink ACK starts original emote and timed effect")
	check(not c.pending_item_use, "Drink ACK unlocks the Use button")
	game.inventory.hide(); game.toast_time = 0; game.toast_label.hide()
	c.show_speech({"channel":"local","outgoing":true,"message":"h*llo *hic* everyowne","drunk":true})
	game.speech_layer.sync(); await process_frame
	var bubble: Panel = game.speech_layer.bubbles[100]
	check((bubble.get_node("Haze") as Label).visible and (bubble.get_node("Message") as Label).text.contains("*"), "Stars and subtle ghosted hazy speech are visible")
	var speech_before: Dictionary = c.chat_bubbles[100].duplicate(true)
	game.skills_ui.event({"kind":"bard_note","player_id":100,"note":12,"instrument":49})
	check(c.chat_bubbles[100] == speech_before, "Bard must preserve chat text, drunk styling and speech lifetime")
	check(game.drink_effects.music_emotes.has(100) and game.drink_effects.emotes.has(100), "Music and soda emotes can coexist with speech")
	if OS.get_environment("EO_V42_SCREENSHOT") != "":
		await process_frame; await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(OS.get_environment("EO_V42_SCREENSHOT"))
	game.drink_effects.event({"kind":"drunk_ended"}); game.speech_layer.sync()
	check(not game.drink_effects.drunk() and not (bubble.get_node("Haze") as Label).visible, "Expiry restores normal text rendering")
	c._on_closed("Fixture disconnected")
	check(game.drink_effects.until == 0 and game.drink_effects.emotes.is_empty() and game.drink_effects.music_emotes.is_empty(), "Disconnect clears cosmetic state")
	game.started = false; game.queue_free(); await process_frame
	if not failed: print("DRINKS AREA V42 PASS: ",checks," actual GUI checks")
	quit(1 if failed else 0)
