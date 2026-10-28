extends Control
## Login-only composition of existing EO scenery and native character layers.
var game: Node
var artwork: Texture2D
var shade: GradientTexture2D
var brand: Label
var eyebrow: Label
var tagline: Label
var party: HBoxContainer
var previews: Array[Control] = []
var captions: Array[Label] = []
const TITLE_FONT: Font = preload("res://fonts/DejaVuSerif-Bold.ttf")

func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 clip_contents=true
 texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
 var path: String=str((game.manifest.get("login_art",{}) as Dictionary).get("path",""))
 if not path.is_empty():artwork=game._texture(path)
 var gradient: Gradient=Gradient.new()
 gradient.offsets=PackedFloat32Array([0,.42,1])
 gradient.colors=PackedColorArray([Color(.025,.06,.07,.6),Color(.025,.06,.07,.2),Color(.025,.06,.07,.94)])
 shade=GradientTexture2D.new();shade.gradient=gradient;shade.fill_from=Vector2(.5,0);shade.fill_to=Vector2(.5,1)
 eyebrow=label("A WORLD OF ADVENTURE",13,Color("d9c497"))
 brand=label("Aster Vale",60,Color("f6dda0"))
 brand.add_theme_font_override("font",TITLE_FONT)
 brand.add_theme_constant_override("outline_size",5)
 brand.add_theme_color_override("font_outline_color",Color("1c211d"))
 brand.add_theme_color_override("font_shadow_color",Color(0,0,0,.8))
 brand.add_theme_constant_override("shadow_offset_y",4)
 tagline=label("Six classes. One shared world.",16,Color("e5ddc5"))
 party=HBoxContainer.new();party.mouse_filter=Control.MOUSE_FILTER_IGNORE;party.add_theme_constant_override("separation",0);add_child(party)
 for spec: Dictionary in [
  {"role":"WARRIOR","gender":1,"hairstyle":7,"haircolor":4,"body":509,"boots":598,"head":0,"offhand":416,"weapon":498},
  {"role":"MAGICIAN","gender":1,"hairstyle":5,"haircolor":2,"body":501,"boots":574,"head":0,"offhand":0,"weapon":493},
  {"role":"ARCHER","gender":0,"hairstyle":11,"haircolor":4,"body":508,"boots":590,"head":0,"offhand":425,"weapon":496}
 ]:
  var slot: Control=Control.new();slot.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slot.mouse_filter=Control.MOUSE_FILTER_IGNORE;party.add_child(slot)
  var preview: Control=preload("res://scripts/character_preview.gd").new();preview.game=game
  preview.appearance={"gender":spec.gender,"race":0,"hairstyle":spec.hairstyle,"haircolor":spec.haircolor,"equipment_graphics":[graphic(spec.boots),0,0,0,graphic(spec.body),0,graphic(spec.head),graphic(spec.offhand),graphic(spec.weapon)]}
  preview.fit_to_rect=true;preview.zoom=2.5;preview.bottom_margin=6;preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  slot.add_child(preview);preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.offset_bottom=-25;previews.append(preview)
  var caption: Label=label(str(spec.role),12,Color("cdbb91"));remove_child(caption);slot.add_child(caption)
  caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);caption.offset_top=-23;caption.offset_bottom=-3;captions.append(caption)
 resized.connect(layout)
 layout()

func graphic(ident: int) -> int:
 if ident==0:return 0
 return int((game.online.catalog.get("items",{}) as Dictionary).get(str(ident),{}).get("doll_graphic",0))

func label(value: String, font_size: int, tint: Color) -> Label:
 var result: Label=Label.new();result.text=value;result.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;result.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
 result.add_theme_font_size_override("font_size",font_size);result.add_theme_color_override("font_color",tint);result.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(result);return result

func layout() -> void:
 if brand==null:return
 var title_y: float=size.y*.5
 brand.position=Vector2(12,title_y-42);brand.size=Vector2(size.x-24,84)
 brand.add_theme_font_size_override("font_size",clampi(int(size.x*.115),34,68))
 eyebrow.position=Vector2(12,maxf(12,title_y-83));eyebrow.size=Vector2(size.x-24,25)
 tagline.position=Vector2(12,title_y+49);tagline.size=Vector2(size.x-24,26)
 party.position=Vector2(14,size.y-160);party.size=Vector2(size.x-28,146)
 for preview: Control in previews:preview.queue_redraw()
 queue_redraw()

func _draw() -> void:
 var bounds: Rect2=Rect2(Vector2.ZERO,size)
 draw_style_box(game._style(Color("18282a"),Color("b49458"),14),bounds)
 var inside: Rect2=Rect2(Vector2(5,5),size-Vector2(10,10))
 if artwork!=null:draw_texture_rect_region(artwork,inside,Rect2(12,145,616,320),Color(.82,.85,.8))
 if shade!=null:draw_texture_rect(shade,inside,false)
 var y: float=size.y*.5+42
 draw_line(Vector2(size.x*.19,y),Vector2(size.x*.43,y),Color("ad8d50"),1,true)
 draw_line(Vector2(size.x*.57,y),Vector2(size.x*.81,y),Color("ad8d50"),1,true)
 draw_colored_polygon(PackedVector2Array([Vector2(size.x*.5,y-4),Vector2(size.x*.5+4,y),Vector2(size.x*.5,y+4),Vector2(size.x*.5-4,y)]),Color("e0bb70"))
 for corner: Vector2 in [Vector2(14,14),Vector2(size.x-14,14),Vector2(14,size.y-14),Vector2(size.x-14,size.y-14)]:
  var dx: float=1 if corner.x<size.x*.5 else -1
  var dy: float=1 if corner.y<size.y*.5 else -1
  draw_line(corner,corner+Vector2(24*dx,0),Color("e0bb70"),2,true)
  draw_line(corner,corner+Vector2(0,24*dy),Color("e0bb70"),2,true)
