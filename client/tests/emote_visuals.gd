extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size=Vector2i(1544,720)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.started=true;game.welcome.hide();game.online.panel.hide();game.online_mode=true
 game.online.set_process(false);game.online.session.set_process(false);game.online.active=true
 game.online.player={"player_id":100,"name":"Emote preview","x":35,"y":45,"class_id":7,"gender":1,"hairstyle":2,"haircolor":2,"race":0,"equipment_graphics":[0,0,0,0,0,0,0,0,0],"equipment":{},"stats":{}}
 game.player_world=game.tile_position(game.player_tile)
 var visuals=preload("res://scripts/drink_effects.gd")
 for ident: int in [1,2,3,4,5,6,7,8,9,10,14]:
  var tex: Texture2D=visuals.social_texture(ident)
  assert(tex != null and tex.get_width()>=192)
 var rect: Rect2=visuals.social_rect(Vector2.ZERO,480)
 assert(rect.end.y<=-96 and rect.size==Vector2(40,40))
 game.drink_effects.event({"kind":"player_emote","player_id":100,"emote":1})
 game.emote_ui.popup.show()
 for _frame: int in range(3):await process_frame
 await RenderingServer.frame_post_draw
 var path: String=OS.get_environment("EO_EMOTE_SCREENSHOT")
 if path!="":root.get_texture().get_image().save_png(path)
 print("EMOTE VISUAL PASS: 11 high resolution icons and face/nameplate clearance")
 game.online.active=false;game.online_mode=false;game.queue_free();await process_frame;quit()
