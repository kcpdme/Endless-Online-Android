extends SceneTree
## Pack an enhanced 8x8 contact sheet into the original 15 four-frame sequences.
## Original/derived art stays in ignored client/content; no source atlas is replaced.
func _initialize() -> void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=2:
  push_error("Usage: --script tools/pack_emote_enhancement.gd -- INPUT.png OUTPUT.png");quit(1);return
 var source: Image=Image.load_from_file(args[0])
 if source==null or source.get_width()!=source.get_height() or source.get_width()<1024:
  push_error("Expected square enhanced 8x8 sprite grid, at least 1024px");quit(1);return
 var packed: Image=Image.create(800,3000,false,Image.FORMAT_RGBA8)
 packed.fill(Color(0,0,0,0))
 for index: int in range(60):
  var col: int=index%8
  var row: int=index/8
  var left: int=roundi(col*source.get_width()/8.0)
  var top: int=roundi(row*source.get_height()/8.0)
  var right: int=roundi((col+1)*source.get_width()/8.0)
  var bottom: int=roundi((row+1)*source.get_height()/8.0)
  var frame: Image=source.get_region(Rect2i(left,top,right-left,bottom-top))
  # Ignore invisible RGB matte colours during interpolation to prevent fringes.
  frame.premultiply_alpha()
  frame.resize(200,200,Image.INTERPOLATE_LANCZOS)
  for y: int in range(200):
   for x: int in range(200):
    var pixel: Color=frame.get_pixel(x,y)
    if pixel.a>0.0001:frame.set_pixel(x,y,Color(pixel.r/pixel.a,pixel.g/pixel.a,pixel.b/pixel.a,pixel.a))
    else:frame.set_pixel(x,y,Color(0,0,0,0))
  packed.blit_rect(frame,Rect2i(0,0,200,200),Vector2i((index%4)*200,(index/4)*200))
 var error: Error=packed.save_png(args[1])
 if error!=OK:push_error("Could not save packed atlas");quit(1);return
 print("Packed 15 original emotes x 4 frames; 200px frames; 800x3000 transparent atlas")
 quit()
