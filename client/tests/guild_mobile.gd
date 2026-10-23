extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		calls.append({"op": op, "fields": fields.duplicate()})
		return calls.size()
var failed: bool = false
var checks: int = 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(reason)
func _initialize() -> void: call_deferred("run")
func touch(point: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point; event.pressed = pressed; event.index = 87
	Input.parse_input_event(event)
	await process_frame
func run() -> void:
	root.size = Vector2i(1544, 720)
	var game: Node = load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame
	game.set_process(false); game.online.set_process(false); game.music.stop()
	game.welcome.hide();game.online.panel.hide(); game.started = true; game.online_mode = true
	var online: Node = game.online
	online.session.queue_free()
	var wire: Capture = Capture.new(); online.add_child(wire); wire.set_process(false); online.session = wire
	online.panel.hide(); online.active = true; online.streaming = true
	online.player = {"player_id":100,"stats":{}}
	game.player_tile = Vector2i(40, 40); game.player_world = game.tile_position(game.player_tile)
	game.camera.position = game.player_world
	online.npcs.assign([{"id":46,"index":7,"x":40,"y":39,"direction":0}])
	await process_frame
	# Tap the rendered Guild Bob sprite, outside the reserved stick area.
	var at: Vector2 = game.get_global_transform_with_canvas() * (game.tile_position(Vector2i(40, 39)) - Vector2(0, 15))
	await touch(at, true); await touch(at, false)
	check(online.interaction.get("kind", "") == "guild", "Guild Bob sprite tap must select the guild service")
	online._process_interaction()
	check(wire.calls.size() == 1 and wire.calls[0].op == "guild_open", "Guild Bob must send one guild_open request")
	check(game.route.is_empty(), "Counter service must not path onto Guild Bob")
	var data: Dictionary = {"guild":{"npc_id":46,"npc_index":7,"map_id":5,"token":0}}
	online._on_message({"op":"guild_open","ok":true,"data":data})
	check(game.guild_ui.panel.visible and game._modal_open(), "Native acknowledgement must open a movement-blocking guild modal")
	check(game.guild_ui.title.text == "Guild Bob", "Modal must display the native NPC name")
	await process_frame
	game.guild_ui.query.text = "TST"
	var card: Control = game.guild_ui.panel.get_child(0)
	for label: String in ["Guild information", "Member list"]:
		for child: Node in game.guild_ui.body.get_children():
			if child is Button and child.text == label:
				await touch(child.get_global_rect().get_center(), true)
				await touch(child.get_global_rect().get_center(), false)
				game.guild_ui.response({"op":"guild_info","ok":true})
				await process_frame
				break
	check(wire.calls.size() == 3 and wire.calls[1].op == "guild_info" and wire.calls[2].op == "guild_members", "Actual touch buttons must send native lookups")
	data.guild.result = {"query":"TST","members":[{"name":"devleader","title":"Founder","rank":0}]}
	online._on_message({"op":"guild_members","ok":true,"data":data})
	check("devleader" in game.guild_ui.detail.text, "Native member list must render")
	online._on_message({"op":"guild_info","ok":false,"error":"Guild not found"})
	check(game.guild_ui.panel.visible and game.toast_label.text == "Guild not found" and game.guild_ui.status.text == "Guild not found", "Lookup errors must keep the window usable and show feedback")
	for width: int in [960,1280,1544,1920]:
		root.size = Vector2i(width,720); await process_frame
		game.guild_ui.tick(); await process_frame
		check(root.get_visible_rect().encloses(card.get_global_rect()), "Guild window must fit phone landscape viewport")
	if OS.get_environment("EO_GUILD_SCREENSHOT") != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("EO_GUILD_SCREENSHOT"))
	# Creation is unavailable until native founding-member confirmation.
	game.guild_ui._remember(); game.guild_ui.page = 1; game.guild_ui.refresh()
	game.guild_ui.inputs["create_tag"].text = "TST"
	game.guild_ui.inputs["create_name"].text = "Test Guild"
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text == "Invite founding members": child.pressed.emit()
	check(wire.calls.back().op == "guild_begin" and wire.calls.back().fields.tag == "TST", "Founding form must send the chosen tag and name")
	game.guild_ui.response({"op":"guild_begin","ok":true})
	data.guild_creation = {"tag":"TST","name":"test guild","members":["devfounder"],"ready":false}
	game.guild_ui.receive(data)
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text.begins_with("Found guild"): check(child.disabled, "Found button must wait for native readiness")
	data.guild_creation.ready = true; game.guild_ui.receive(data)
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text.begins_with("Found guild"):
			check(not child.disabled, "Native member confirmation must enable founding")
			child.pressed.emit()
	check(game.guild_ui.confirmation.visible and wire.calls.back().op == "guild_begin", "Founding must ask before spending Gold")
	game.guild_ui.confirmation.hide(); game.guild_ui.confirmation.confirmed.emit()
	check(wire.calls.back().op == "guild_found", "Confirmed founding must send guild_found")
	game.guild_ui.response({"op":"guild_found","ok":true})
	game.guild_ui._remember(); game.guild_ui.page = 2; game.guild_ui.refresh()
	game.guild_ui.inputs["join_tag"].text = "TST"; game.guild_ui.inputs["recruiter"].text = "devleader"
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text == "Request membership": child.pressed.emit()
	check(wire.calls.back().op == "guild_join" and wire.calls.back().fields.recruiter == "devleader", "Join form must send tag and recruiter")
	game.guild_ui.response({"op":"guild_join","ok":true})
	game.guild_ui.receive({"guild_invitation":{"player_id":200,"display":"Test Guild (TST)","map_id":5}})
	check(game.guild_ui.page == 4 and game.guild_ui.panel.visible, "Incoming native founding invitation must open Requests")
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text == "Support founding": child.pressed.emit()
	check(wire.calls.back().op == "guild_support" and wire.calls.back().fields.accept, "Support button must send the user's acceptance")
	game.guild_ui.response({"op":"guild_support","ok":true})
	data.guild.membership = {"tag":"TST","guild_name":"test guild","rank":0,"title":"Founder","bank":5000,"description":"Welcome","ranks":["Leader","Recruiter","","","","","","","Member"]}
	data.guild_requests = [{"player_id":201,"name":"devjoiner","map_id":5}]
	data.guild_invitation = null; data.guild_creation = null
	game.guild_ui.receive(data)
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text == "Accept devjoiner": child.pressed.emit()
	check(game.guild_ui.pending_op == "guild_recruit", "Recruiter acceptance must offer a confirmation")
	game.guild_ui.confirmation.hide(); game.guild_ui.confirmation.confirmed.emit()
	check(wire.calls.back().op == "guild_recruit" and wire.calls.back().fields.player_id == 201, "Recruiter must accept the native applicant ID")
	game.guild_ui.response({"op":"guild_recruit","ok":true})
	game.guild_ui._remember(); game.guild_ui.page = 3; game.guild_ui.refresh()
	game.guild_ui.layout(360)
	check(card.get_global_rect().position.x >= 0 and card.get_global_rect().position.y >= 0 and card.get_global_rect().end.y <= 360, "Guild forms must remain above the software keyboard")
	game.guild_ui.layout(0)
	check(root.get_visible_rect().encloses(card.get_global_rect()), "Guild panel remains fully on-screen after keyboard closes")
	check(game.guild_ui.inputs.has("rank_9") and game.guild_ui.inputs.has("description"), "Founder must have all rank-name and description fields")
	game.guild_ui.inputs["member_rank"].text = ""
	game.guild_ui._confirm("guild_rank", {"name":"devmember","rank":0}, "Change rank?")
	check(not game.guild_ui.confirmation.visible and game.guild_ui.status.text.begins_with("Enter the intended rank"), "Blank rank must never be interpreted as founder appointment")
	for child: Node in game.guild_ui.body.get_children():
		if child is Button and child.text == "Disband guild": child.pressed.emit()
	check(game.guild_ui.pending_op == "guild_disband" and game.guild_ui.confirmation.visible, "Disband must require explicit confirmation")
	game.guild_ui.confirmation.hide()
	game._handle_back()
	check(not game.guild_ui.panel.visible and wire.calls.back().op == "guild_close", "Android Back must close guild context")
	game.guild_ui.receive(data); online._on_closed("Test disconnect")
	check(not game.guild_ui.panel.visible, "Disconnect must hide stale guild UI")
	game.started = false; game.queue_free(); await process_frame
	if not failed: print("GUILD MOBILE PASS: ", checks, " checks")
	quit(1 if failed else 0)
