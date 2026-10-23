extends SceneTree
class Capture extends "res://scripts/online_session.gd":
	var calls: Array[Dictionary] = []
	func request(op: String, fields: Dictionary = {}) -> int:
		serial += 1; calls.append({"op":op,"fields":fields.duplicate()}); return serial
var checks: int = 0
var failed: bool = false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(why)
func tap(control: Control) -> void:
	await process_frame;await process_frame
	var event: InputEventScreenTouch = InputEventScreenTouch.new(); event.index=71;event.pressed=true;event.position=root.get_final_transform()*control.get_global_rect().get_center();Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func shot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	var game: Node=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.music.stop();game.welcome.hide();game.online.panel.hide()
	var c: Node=game.online;c.show_login();c.session.queue_free();var wire: Capture=Capture.new();c.add_child(wire);wire.set_process(false);c.session=wire
	var fixtures: Array=[{"id":11,"name":"emberknight","gender":1,"race":0,"hairstyle":1,"haircolor":0,"level":120,"equipment_graphics":[1,1,44,1,33]},{"id":22,"name":"moonweaver","gender":0,"race":3,"hairstyle":20,"haircolor":9,"level":50,"equipment_graphics":[1,40,0,0,49]},{"id":33,"name":"stonewarden","gender":1,"race":2,"hairstyle":7,"haircolor":4,"level":25,"equipment_graphics":[1,1,0,0,21]}]
	for dimensions: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720),Vector2i(1920,1080)]:
		root.size=dimensions;await process_frame;await process_frame
		for count: int in range(4):
			c._show_characters(fixtures.slice(0,count));await process_frame;await process_frame
			var viewport: Rect2=root.get_visible_rect()
			check(viewport.encloses(c.panel.get_child(0).get_global_rect()),"Full-screen card fits viewport")
			check(c.character_cards.get_child_count()==3 and c.selection_previews.size()==count,"Always three native slots")
			check(c.character_flow.create_button.visible==(count<3),"Creation unavailable exactly at three")
			check(c.character_flow.enter_button.disabled==(count==0),"Enter requires a character")
			for slot: Control in c.character_cards.get_children():check(viewport.encloses(slot.get_global_rect()) and slot.size.y>=250,"Each slot stays large and inside viewport")
			check(viewport.encloses(c.character_flow.enter_button.get_global_rect()),"Enter remains visible")
			if count==3:
				await tap(c.character_cards.get_child(2));check(c.character_list.get_selected_items()[0]==2,"Third card selects by native index")
				var before: int=wire.calls.size();c.character_flow.open_creation();c._create_character();check(not c.creation_panel.visible and wire.calls.size()==before,"Fourth creation blocked before request")
	root.size=Vector2i(1600,720);await process_frame;await process_frame
	c._show_characters(fixtures);await process_frame;await process_frame;await shot("characters-three")
	c._show_characters(fixtures.slice(0,2));await process_frame;await process_frame;await shot("characters-empty-slot")
	await tap(c.character_cards.get_child(2));check(c.creation_panel.visible,"Empty slot opens full-screen creation")
	c.character_name_field.text="newtraveler"
	for gender: int in range(2):
		await tap(c.character_flow.gender_buttons[gender]);check(c.creation_appearance().gender==gender and c.character_preview.appearance.gender==gender,"Body choice updates native preview immediately")
	c.hair_choice.select(19);c.color_choice.select(9);c.skin_choice.select(3);c._update_creation_preview()
	c.character_flow.cycle(c.hair_choice,1);c.character_flow.cycle(c.color_choice,1);c.character_flow.cycle(c.skin_choice,1)
	check(c.creation_appearance()=={"gender":1,"hairstyle":1,"haircolor":0,"race":0},"Native appearance arrows wrap correctly")
	c.body_choice.select(0);c.hair_choice.select(19);c.color_choice.select(9);c.skin_choice.select(3);c._update_creation_preview();await process_frame;await process_frame
	check(not c.character_flow.creation_submit.disabled,"Valid name enables creation")
	check(root.get_visible_rect().encloses(c.character_flow.creation_submit.get_global_rect()),"Create stays visible")
	for control: Control in [c.character_name_field,c.hair_choice,c.color_choice,c.skin_choice,c.character_preview]:check(root.get_visible_rect().encloses(control.get_global_rect()),"Appearance controls inside viewport")
	await shot("character-create-female")
	var before: int=wire.calls.size();await tap(c.character_flow.creation_submit);c._create_character();check(wire.calls.size()==before+1,"Repeated submit queues only one native creation")
	check(wire.calls.back().fields=={"name":"newtraveler","gender":0,"hairstyle":20,"haircolor":9,"race":3},"Chosen native appearance sent exactly")
	c._on_message({"op":"create_character","ok":false,"error":"Name is already in use."})
	check(not c.creating_character and c.character_name_field.text=="newtraveler" and c.character_preview.appearance.gender==0,"Server rejection preserves name and appearance")
	c.body_choice.select(1);c.hair_choice.select(5);c.color_choice.select(4);c.skin_choice.select(0);c._update_creation_preview();await process_frame;await shot("character-create-male")
	var before_turn: String=c.character_preview.direction;c.character_preview.turn(1);check(before_turn!=c.character_preview.direction,"Preview turns without changing creation properties")
	c.creation_panel.hide();c._show_characters(fixtures);await process_frame;await tap(c.character_cards.get_child(2));await tap(c.character_flow.enter_button)
	check(wire.calls.back().op=="enter" and int(wire.calls.back().fields.character_id)==33,"Third character enters with correct native ID")
	var requests: int=wire.calls.size();c.character_flow.open_creation();c._create_character();c._enter_selected()
	check(not c.creation_panel.visible and wire.calls.size()==requests and c.character_cards.get_child(0).disabled,"Entering prevents competing creation or duplicate entry")
	var report: Dictionary={"result":"passed" if not failed else "failed","checks":checks,"four_landscape_sizes":true,"zero_through_three_characters":true,"fourth_creation_and_double_submit_prevented":true,"native_body_skin_hair_and_color":true,"third_native_character_selection":true}
	var out: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
	if not out.is_empty():var f: FileAccess=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n")
	print("CHARACTER FLOW: ",JSON.stringify(report));game.queue_free();await process_frame;await process_frame;quit(1 if failed else 0)
