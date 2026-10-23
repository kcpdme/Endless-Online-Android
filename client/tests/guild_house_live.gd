extends SceneTree
var game: Node
var checks: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> bool:
	checks+=1
	if not ok:push_error(why);quit(1)
	return ok
func wait_for(test: Callable) -> bool:
	var end: int=Time.get_ticks_msec()+18000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func tap(control: Control) -> void:
	await process_frame;await process_frame
	await world_tap(root.get_final_transform()*control.get_global_rect().get_center())
func world_tap(point: Vector2) -> void:
	var e: InputEventScreenTouch=InputEventScreenTouch.new();e.index=82;e.position=point;e.pressed=true;Input.parse_input_event(e);await process_frame
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e);await process_frame
func text_button(parent: Node, value: String) -> Button:
	for control: Node in parent.find_children("*","Button",true,false):
		if control.text==value:return control
	check(false,"Missing guild button: "+value);return null
func shot(name: String) -> void:
	var folder: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1600,720)
	var fs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_GUILD_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c: Node=game.online;c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fs.username;c.password_field.text=fs.password;c._authenticate("login")
	if not check(await wait_for(func() -> bool:return c.character_box.visible),"Guild fixture login failed"):return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Guild fixture entry failed"):return
	if not check(int(c.player.map_id)==108,"Must be in actual guild house"):return
	var bob: Dictionary={}
	for npc: Dictionary in c.npcs:
		if int(npc.id)==46:bob=npc
	if not check(not bob.is_empty(),"Guild Bob missing from native guild house"):return
	await world_tap(root.get_final_transform()*game.get_global_transform_with_canvas()*(game.tile_position(Vector2i(int(bob.x),int(bob.y)))+Vector2(0,-25)))
	var ui: RefCounted=game.guild_ui
	if not check(await wait_for(func() -> bool:return ui.panel.visible and c.session.is_idle()),"Touching real Guild Bob did not open guild service: "+c.last_error):return
	ui.tick();await process_frame
	if not check(root.get_visible_rect().encloses(ui.panel.get_child(0).get_global_rect()),"Guild Bob window is clipped with its layout handler running"):return
	if not check(ui.title.text=="Guild Bob" and not ui.state.is_empty(),"Native guild context or name missing"):return
	await shot("guild-bob-fixed")
	await tap(text_button(ui.panel,"Look up"));ui.inputs.query.text="ZZQ"
	await tap(text_button(ui.body,"Guild information"))
	if not check(await wait_for(func() -> bool:return not ui.busy and ui.status.text.contains("not found")),"Guild lookup error did not arrive"):return
	if not check(ui.panel.visible,"Lookup failure closed guild house"):return
	await tap(text_button(ui.panel,"Create"))
	ui.inputs.create_tag.text="ABC";ui.inputs.create_name.text="Dev Guild"
	await shot("guild-bob-create")
	var tag_control: LineEdit=ui.inputs.create_tag
	# Unrelated snapshots must not rebuild focused forms or reopen a dismissed service.
	c.session.request("refresh")
	if not check(await wait_for(func() -> bool:return c.session.is_idle()),"Refresh did not settle"):return
	if not check(ui.inputs.create_tag==tag_control and ui.inputs.create_tag.text=="ABC","Unrelated world refresh destroyed the guild form"):return
	game._handle_back()
	if not check(await wait_for(func() -> bool:return c.session.is_idle() and not ui.panel.visible),"Back did not close native guild context"):return
	c.session.request("refresh");await wait_for(func() -> bool:return c.session.is_idle())
	if not check(not ui.panel.visible,"Closed Guild Bob reopened on world refresh"):return
	c.log_out();game.queue_free();await create_timer(.2).timeout
	var report: Dictionary={"result":"passed","checks":checks,"actual_guild_house_bob_touch":true,"native_lookup_error_keeps_window":true,"refresh_preserves_form_and_close":true,"dev_account_only":true}
	var f: FileAccess=FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  ")+"\n")
	print("GUILD HOUSE LIVE: ",JSON.stringify(report));quit(0)
