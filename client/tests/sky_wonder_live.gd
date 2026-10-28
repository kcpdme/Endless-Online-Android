extends SceneTree
## Walk the actual new native portals through the shipped client and adapters.
var game: Node
var c: Node
var checks: int=0
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, why: String) -> void:
 checks+=1
 if not ok:failed=true;push_error(why)
func wait_for(test: Callable, seconds: float=12.0) -> bool:
 var end: int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if test.call():return true
  await process_frame
 return false
func step(direction: Vector2i, mid: int, tile: Vector2i) -> void:
 check(await wait_for(func() -> bool:return not game.moving and c.pending_inputs.is_empty() and c.session.is_idle()),"Previous native step finished")
 c.request_step(direction)
 check(await wait_for(func() -> bool:return int(c.player.get("map_id",0))==mid and game.player_tile==tile and not game.moving and c.pending_inputs.is_empty() and c.session.is_idle()),"Authoritative client arrival: %d %s"%[mid,str(tile)])
func run() -> void:
 root.size=Vector2i(1280,720)
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_SKY_FIXTURE")))
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;c=game.online
 c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=str(fixture.username);c.password_field.text=str(fixture.password);c._authenticate("login")
 check(await wait_for(func() -> bool:return c.character_box.visible),"Regular fixture logs in")
 if failed:game.queue_free();await process_frame;quit(1);return
 c.character_list.select(0);c._enter_selected()
 check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Regular fixture enters actual native world")
 check(int(c.player.stats.admin)==0,"No admin powers are used")
 var sign: Dictionary={}
 for entry: Dictionary in game.world.get("signs",[]):
  if int(entry.x)==12 and int(entry.y)==4:sign=entry
 check(not sign.is_empty(),"Sky Haven entrance has its matching sign and artwork")
 game.world_services.open_sign(sign)
 check(game.world_services.sign_title.text=="Sky Haven" and game.world_services.sign_text.text.contains("cloud bridge"),"Sign explains the walking entrance")
 game.world_services.sign_panel.hide()
 await step(Vector2i.UP,23,Vector2i(14,4));await step(Vector2i.UP,23,Vector2i(14,3));await step(Vector2i.UP,73,Vector2i(19,12))
 check(str(game.world.name)=="Sky Wonder Path","Cloud bridge has a useful map title")
 for x: int in range(18,10,-1):await step(Vector2i.LEFT,73,Vector2i(x,12))
 await step(Vector2i.LEFT,71,Vector2i(26,55))
 for y: int in range(56,62):await step(Vector2i.DOWN,71,Vector2i(26,y))
 await step(Vector2i.RIGHT,71,Vector2i(27,61))
 await step(Vector2i.DOWN,71,Vector2i(27,62));await step(Vector2i.DOWN,71,Vector2i(27,63));await step(Vector2i.DOWN,73,Vector2i(11,11))
 for x: int in range(12,20):await step(Vector2i.RIGHT,73,Vector2i(x,11))
 await step(Vector2i.RIGHT,23,Vector2i(14,5))
 check(c.pending_inputs.is_empty() and c.session.is_idle(),"Return landing does not loop or leave movement pending")
 var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"regular_player":true,"real_native_portals":true,"bridge_both_directions":true,"entrance_sign":true}
 var path: String=OS.get_environment("ASTER_VALE_TEST_REPORT")
 var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");print("SKY WONDER LIVE: ",JSON.stringify(report))
 c.log_out();game.queue_free();await process_frame;await process_frame;quit(1 if failed else 0)
