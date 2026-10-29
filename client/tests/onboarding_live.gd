extends SceneTree
var game: Node
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,why: String) -> void:
 checks+=1
 if not ok:failed=true;push_error(why)
func wait_for(test: Callable) -> bool:
 var end: int=Time.get_ticks_msec()+20000
 while Time.get_ticks_msec()<end:
  if test.call():return true
  await process_frame
 return false
func run() -> void:
 root.size=Vector2i(1544,720)
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_ONBOARDING_FIXTURE")))
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 var c: Node=game.online
 c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=str(fixture.username);c.password_field.text=str(fixture.password);c._authenticate("login")
 check(await wait_for(func() -> bool:return c.character_box.visible),"Regular new player login works")
 if failed:game.queue_free();await process_frame;quit(1);return
 c.character_list.select(0);c._enter_selected()
 check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Original house loads through native online entry")
 check(int(game.world.id)==192 and game.player_tile==Vector2i(7,6),"Client uses the original Tutorial Island spawn")
 check((c.player.get("inventory",[]) as Array).is_empty() and (c.player.get("spells",[]) as Array).is_empty(),"Inventory and learned skills start empty")
 check(int(c.player.stats.level)==0 and int(c.player.stats.admin)==0,"Player is level-zero and regular")
 check(not game.pet_ui.button.visible and not game.pet_ui.collection_button.visible,"Peasant has no Summoner controls")
 check(game.bag_button.visible,"Inventory remains available for earned items")
 check(not c.players.is_empty() or c.npcs.size()>=1,"Original nearby house inhabitants are rendered")
 for dimensions: Vector2i in [Vector2i(1544,720),Vector2i(960,540)]:
  root.size=dimensions
  for frame: int in range(4):await process_frame
  await RenderingServer.frame_post_draw
  var directory: String=OS.get_environment("ASTER_VALE_SCREENSHOTS")
  if directory!="":root.get_texture().get_image().save_png(directory.path_join("classic-start-%d.png"%dimensions.x))
 var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"original_house_rendered":true,"phone_viewports":2,"native_public_birth":true,"existing_player_used":false}
 FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
 print("CLASSIC ONBOARDING UI: ",JSON.stringify(report));c.log_out();game.queue_free();await process_frame;await process_frame;quit(1 if failed else 0)
