extends "res://tests/mobile_network_live.gd"
## Mirrors Saniya's spent level-one points; validates a real GiveEXP level-up.
func _run()->void:
	var fixtures:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_PEER_FIXTURES")))
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var c:Node=game.online
	c.show_login();c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fixtures.observer.username;c.password_field.text=fixtures.observer.password;c._authenticate("login")
	if not check(await wait_for(func()->bool:return c.character_box.visible),"Quest fixture login failed"):return
	c.character_list.select(0);c._enter_selected()
	if not check(await wait_for(func()->bool:return c.active and c.streaming and c.session.is_idle()),"Quest fixture entry failed"):return
	if not check(int(c.player.level)==1 and int(c.player.stats.experience)==705 and int(c.player.stats.stat_points)==0 and int(c.player.stats.intelligence)==3,"Spent level-one fixture differs"):return
	c.map_click(Vector2i(7,43),"npc")
	if not check(await wait_for(func()->bool:return game.quest_ui.panel.visible and not game.quest_ui.state.is_empty()),"Native reward dialogue did not open"):return
	game.quest_ui.reply(1)
	if not check(await wait_for(func()->bool:return int(c.player.level)==2 and int(c.player.stats.stat_points)==3 and int(c.player.stats.skill_points)==6 and c.session.is_idle()),"Quest level-up failed to synchronize actual native point totals"):return
	game.stats_ui.refresh();await process_frame
	if not check(game.stats_ui.classic_fields.stat_points.text=="3" and game.stats_ui.classic_fields.skill_points.text=="6","Character Stats did not display the awarded points"):return
	game.chat_ui.open();game.chat_ui.select_tab(4)
	if not check(game.chat_ui.history.get_parsed_text().contains("Gained 500 EXP (quest)") and game.chat_ui.history.get_parsed_text().contains("Level 2 reached"),"System history omitted quest EXP or level-up"):return
	if not check(int(c.player.stats.experience)==1205 and int(c.player.stats.intelligence)==3,"Existing EXP or spent attributes changed unexpectedly"):return
	var report:Dictionary={"result":"passed","mirrors_spent_level_one_fixture":true,"quest_exp_gain":500,"new_level":2,"native_stat_points":3,"native_skill_points":6,"actual_character_stats_display":true,"system_history":true,"no_manual_points_added":true,"isolated_database":true}
	FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("QUEST LEVELUP UI PASS: ",JSON.stringify(report));c.session.close();game.queue_free();await process_frame;quit(0)
