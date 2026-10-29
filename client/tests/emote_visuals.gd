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
 assert(visuals.frame_index(0)==0 and visuals.frame_index(239)==0 and visuals.frame_index(240)==1 and visuals.frame_index(479)==1 and visuals.frame_index(480)==2 and visuals.frame_index(719)==2 and visuals.frame_index(720)==3 and visuals.frame_index(959)==3)
 for ident: int in [1,3,4,5,7,14]:
  for frame: int in range(4):
   var tex: AtlasTexture=visuals.social_texture(ident,frame) as AtlasTexture
   assert(tex.region.position.y==visuals.social_set(ident)*200 and tex.region.position.x==frame*200)
 var rect: Rect2=visuals.social_rect(Vector2.ZERO,480)
 assert(rect.end.y<=-80 and rect.size==Vector2(50,50))
 for gender: int in [0,1]:
  for direction: int in range(4):
   var back: bool=direction==1 or direction==2
   var chair: float=11+gender if back else 9+gender
   assert(visuals.sitting_head_shift(1,gender,direction)==chair)
   assert(visuals.sitting_head_shift(2,gender,direction)==chair*2-(1 if back else 0))
   assert(visuals.sitting_head_shift(0,gender,direction)==0)
 game.drink_effects.event({"kind":"player_emote","player_id":100,"emote":1})
 game.emote_ui.begin(77);game.emote_ui.release(game.emote_ui.button.get_global_rect().get_center())
 for _frame: int in range(3):await process_frame
 await RenderingServer.frame_post_draw
 var path: String=OS.get_environment("EO_EMOTE_SCREENSHOT")
 if path!="":
  root.get_texture().get_image().save_png(path)
  for frame: int in range(4):
   game.drink_effects.social_emotes[100]={"id":1,"at":Time.get_ticks_msec()-frame*240-5}
   game.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(path.trim_suffix(".png")+"_%d.png"%frame)
 var original: CanvasTexture=CanvasTexture.new()
 original.diffuse_texture=load(visuals.ORIGINAL_PATH)
 visuals.animation_atlas=original;visuals.enhanced=false;visuals.frame_textures.clear()
 var fallback: AtlasTexture=visuals.social_texture(7,3) as AtlasTexture
 assert(fallback.region==Rect2((6*4+3)*50,0,50,50))
 print("EMOTE VISUAL PASS: original enhanced four-frame animations and face/nameplate clearance")
 game.online.active=false;game.online_mode=false;game.queue_free();await process_frame;quit()
