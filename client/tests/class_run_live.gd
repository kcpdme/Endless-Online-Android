extends SceneTree
var game:Node
var checks:int=0
var failed:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failed=true;push_error(why)
func wait_for(test:Callable,seconds:float=15)->bool:
	var end:int=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return false
func run()->void:
	root.size=Vector2i(1544,720)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_RUN_FIXTURE")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c:Node=game.online
	c.host_field.text="ws://127.0.0.1:18977/ws";c.username_field.text=str(fixture.username);c.password_field.text=str(fixture.password);c._authenticate("login")
	check(await wait_for(func()->bool:return c.character_box.visible),"Regular Summoner logs in through WebSocket")
	if failed:quit(1);return
	c.character_list.select(0);c._enter_selected()
	check(await wait_for(func()->bool:return c.active and c.streaming and c.session.is_idle()),"Regular Summoner enters current native profile")
	check(int(c.catalog.balance_version)==15,"Profile 15 reaches client")
	check(await wait_for(func()->bool:return game.run_ui.button.visible),"Native-supported Run icon appears")
	var tp:int=int(c.player.tp);game.run_ui.press()
	check(await wait_for(func()->bool:return bool((c.player.get("combat",{}) as Dictionary).get("running",false)) and c.session.is_idle()),"Native Run acknowledgement reaches client snapshot")
	check(game.run_ui.button.button_pressed and is_equal_approx(float(c.player.combat.move_seconds),.336),"Client uses server-acknowledged x1.25 cadence")
	check(await wait_for(func()->bool:return int(c.player.tp)<tp,3),"Standing idle still receives authoritative TP drain")
	game.run_ui.press()
	check(await wait_for(func()->bool:return not bool(c.player.combat.running) and c.session.is_idle()),"Run can be disabled through the same icon")
	check(is_equal_approx(float(c.player.combat.move_seconds),.42),"Native normal cadence restored")
	game.inventory.show();await process_frame;game._process(0)
	check(not game.run_ui.button.visible,"Modal dialog hides Run target")
	print("CLASS RUN LIVE: ",checks," checks, failed=",failed)
	game.queue_free();await create_timer(.2).timeout;quit(1 if failed else 0)
