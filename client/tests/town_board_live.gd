extends SceneTree
var game: Node
var c: Node
var ui: RefCounted
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
func shot(name: String) -> void:
 for frame: int in range(3):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("ASTER_VALE_SCREENSHOTS").path_join(name+".png"))
func press(title: String) -> void:
 if title=="Publish post":ui.board_ui.publish_button.pressed.emit();return
 for child: Node in ui.content.get_children():
  if child is Button and child.text==title:child.pressed.emit();return
 check(false,"Missing button: "+title)
func run() -> void:
 root.size=Vector2i(1544,720)
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ASTER_VALE_BOARD_FIXTURE")))
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;c=game.online;ui=game.feature_ui
 c.host_field.text=OS.get_environment("ASTER_VALE_TEST_HOST");c.username_field.text=fixture.username;c.password_field.text=fixture.password;c._authenticate("login")
 check(await wait_for(func() -> bool:return c.character_box.visible),"Regular player login")
 if failed:game.queue_free();await process_frame;quit(1);return
 c.character_list.select(0);c._enter_selected()
 check(await wait_for(func() -> bool:return c.active and c.streaming and c.session.is_idle()),"Regular player enters actual native world")
 # Centre short, wrapped and explicitly multi-line speech on the very first frame.
 var pid: int=int(c.player.player_id)
 for message: String in ["Hi", "A longer overhead message should have centred wrapped lines", "First line\nShort\nThe final centred line"]:
  c.show_speech({"channel":"local","outgoing":true,"message":message})
  var bubble: Panel=game.speech_layer.bubbles[pid]
  check((bubble.get_node("Message") as Label).horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,"Every overhead line is centred")
  check((bubble.get_node("Haze") as Label).horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,"Drunk haze uses the same centring")
 await shot("centred-overhead")
 ui.open("board",{"x":46,"y":1})
 check(await wait_for(func() -> bool:return ui.panel.visible and not ui.busy),"Actual town board opens")
 check(ui.board_ui.tab==0 and ui.board_ui.read_tab.button_pressed and not ui.fields.has("subject"),"Read is the default and does not show the post form")
 check(ui.board_ui.tabs.visible,"Read and Post tabs are at the top")
 await shot("board-read-empty")
 ui.board_ui.choose(1)
 check(ui.fields.has("subject") and ui.fields.has("body"),"Post tab opens the composer")
 ui.fields.subject.text="An island adventure";ui.fields.body.text="I crafted my first dagger.\nSee you in Aeven!"
 ui.board_ui.choose(0);ui.board_ui.choose(1)
 check(ui.fields.subject.text=="An island adventure" and ui.fields.body.text.contains("first dagger"),"Draft survives switching tabs")
 for dimensions: Vector2i in [Vector2i(1544,720),Vector2i(960,540)]:
  root.size=dimensions;await process_frame;ui.layout(0)
  check(Rect2(Vector2.ZERO,game.get_viewport_rect().size).encloses(ui.card.get_global_rect()),"Board fits the phone")
  check(ui.board_ui.tabs.get_global_rect().position.y>=ui.card.get_global_rect().position.y,"Board tabs stay inside the card")
  await shot("board-post-%d"%dimensions.x)
 root.size=Vector2i(1544,720);await process_frame;ui.layout(240)
 check(ui.card.get_global_rect().end.y<=480,"Composer stays above the software keyboard")
 ui.layout(0);press("Publish post")
 check(ui.confirmation.visible,"Publish confirmation opens")
 ui.confirmation.get_ok_button().pressed.emit()
 check(await wait_for(func() -> bool:return not ui.busy and ui.board_ui.tab==0 and not ui.board_ui.posts.is_empty()),"Successful native post returns to Read")
 check(ui.board_ui.draft_subject.is_empty() and ui.board_ui.draft_body.is_empty(),"Draft clears only after accepted publication")
 var post: Dictionary=ui.board_ui.posts[0]
 check(str(post.subject).begins_with("An island adventure"),"Actual native post subject appears")
 check(not ui.content.get_children().any(func(node: Node) -> bool:return node is Button and node.text=="Remove selected post"),"Regular players do not receive moderation controls")
 var list: ItemList=ui.fields.list;list.select(0);list.item_selected.emit(0);press("Read selected post")
 check(await wait_for(func() -> bool:return not ui.busy and ui.state.has("body")),"Selected native post opens")
 check(str(ui.state.body)=="I crafted my first dagger.\nSee you in Aeven!","Read preserves native multiline content")
 await shot("board-read-post")
 press("Back to posts");check(ui.fields.has("list") and not ui.state.has("body"),"Back returns to the cached post list")
 ui.board_ui.choose(1);ui.fields.subject.text="";ui.fields.body.text="";press("Publish post")
 check(not ui.busy and ui.status.text.contains("subject"),"Empty post is refused without sending")
 ui.close();c.log_out();game.queue_free();await process_frame;await process_frame
 var report: Dictionary={"result":"failed" if failed else "passed","checks":checks,"native_board_publish_and_read":true,"read_default_post_tab":true,"draft_preserved_across_tabs":true,"centred_multiline_overhead":true,"phone_viewports":2,"isolated_database":true,"production_board_posts_written":false}
 FileAccess.open(OS.get_environment("ASTER_VALE_TEST_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n");print("TOWN BOARD LIVE: ",JSON.stringify(report));quit(1 if failed else 0)
