extends SceneTree
var game: Node
var messages: Array[Dictionary] = []
var checks: int=0
func _initialize() -> void:call_deferred("run")
func letters() -> String:
	var result: String="dev"
	for i: int in range(8):result+=String.chr(97+randi_range(0,25))
	return result
func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:push_error(why);quit(1)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+25000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func tap(control: Control) -> void:
	await process_frame;await process_frame
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=61;e.position=root.get_final_transform()*control.get_global_rect().get_center();e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func run() -> void:
	root.size=Vector2i(1600,720)
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c: Node=game.online;var account: String=letters();var password: String="Dev"+letters()+"42"
	c.session.message_received.connect(func(m: Dictionary) -> void:messages.append(m))
	c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=account;c.password_field.text=password;c._authenticate("register")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Registration/login failed: "+c.last_error):return
	var expected: Array[Dictionary]=[]
	for index: int in range(3):
		await tap(c.character_cards.get_child(index));if not check(c.creation_panel.visible,"Empty slot did not open creation"):return
		var appearance: Dictionary={"gender":index%2,"hairstyle":[20,1,7][index],"haircolor":[9,0,4][index],"race":[3,0,1][index]}
		var name: String=letters();expected.append({"name":name,"appearance":appearance})
		await tap(c.character_flow.gender_buttons[int(appearance.gender)])
		if not check(c.creation_appearance().gender==appearance.gender,"Body button did not select requested gender"):return
		c.hair_choice.select(int(appearance.hairstyle)-1);c.color_choice.select(int(appearance.haircolor));c.skin_choice.select(int(appearance.race));c.character_name_field.text=name;c._update_creation_preview()
		await tap(c.character_flow.creation_submit)
		if not check(await wait_for(func() -> bool:return c.selected_characters.size()==index+1 and not c.creation_panel.visible),"Native creation failed: "+c.last_error):return
		var selection: int=c.character_list.get_selected_items()[0]
		var record: Dictionary=c.selected_characters[selection]
		if not check(record.name==name,"New character must be selected after creation"):return
		for key: String in appearance:
			if not check(int(record[key])==int(appearance[key]),"Native chosen "+key+" mismatch"):return
	if not check(not c.character_flow.create_button.visible and c.character_cards.get_child_count()==3,"Maximum account must show exactly three occupied cards"):return
	var requests: int=c.session.serial;c.character_flow.open_creation();c._create_character()
	if not check(not c.creation_panel.visible and c.session.serial==requests,"Client must not request a fourth character"):return
	# The native limit is also verified independently of the client guard.
	messages.clear();c.session.request("create_character",{"name":letters(),"gender":1,"hairstyle":1,"haircolor":0,"race":0})
	if not check(await wait_for(func() -> bool:return messages.any(func(m: Dictionary) -> bool:return m.get("op")=="create_character" and not bool(m.get("ok",true)))),"Native max-three limit missing"):return
	for index: int in range(3):
		if index>0:
			c.log_out();await create_timer(.8).timeout;c.show_login();c.password_field.text=password;c._authenticate("login")
			if not check(await wait_for(func() -> bool:return c.character_box.visible and c.selected_characters.size()==3),"Native relogin failed"):return
		var selected: int=-1
		for slot: int in range(c.selected_characters.size()):
			if str(c.selected_characters[slot].name)==str(expected[index].name):selected=slot
		await tap(c.character_cards.get_child(selected));await tap(c.character_flow.enter_button)
		if not check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Selected character entry failed"):return
		if not check(c.player.name==expected[index].name,"Wrong character entered"):return
		for key: String in expected[index].appearance:
			if not check(int(c.player[key])==int(expected[index].appearance[key]),"Entered native appearance mismatch"):return
	var report: Dictionary={"result":"passed","checks":checks,"three_actual_native_characters_created":true,"chosen_body_skin_hair_color_native":true,"new_character_selected":true,"native_fourth_creation_rejected":true,"all_three_cards_enter_correct_characters":true,"dev_account_only":true}
	var out: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);out.store_string(JSON.stringify(report,"  ")+"\n")
	print("CHARACTER FLOW LIVE: ",JSON.stringify(report));c.log_out();game.queue_free();await create_timer(.2).timeout;quit(0)
