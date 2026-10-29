extends SceneTree
## Align AI contact sheets to original poses and pack only compact 2x runtime art.
## Usage: SOURCES.json PIGLET.png BANSHI.png OUTPUT_DIRECTORY REPORT.json
const SCALE: int = 2
var details: Array = []

func resized(source: Image, size: Vector2i) -> Image:
	var image: Image = source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	image.premultiply_alpha()
	image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x,y)
			image.set_pixel(x,y,Color(color.r/color.a,color.g/color.a,color.b/color.a,color.a) if color.a>0.0001 else Color(0,0,0,0))
	return image

func pack(entry: Dictionary, input: String, output: String, gid: String) -> Dictionary:
	var sheet: Image = Image.load_from_file(input)
	assert(sheet != null and sheet.get_width()==sheet.get_height() and sheet.get_width()>=1024,"Expected a square 4x4 enhanced sheet")
	var original: Dictionary = entry.original
	var reference: Dictionary = entry.frames[0].frame
	var width: int = int(reference.region[2])*SCALE
	var height: int = int(reference.region[3])*SCALE
	var atlas: Image = Image.create(width*8,height*4,false,Image.FORMAT_RGBA8)
	atlas.fill(Color(0,0,0,0))
	var canonical: Dictionary = {}
	for i: int in range(entry.frames.size()):
		var item: Dictionary = entry.frames[i]
		var left: int = roundi((i%4)*sheet.get_width()/4.0)
		var top: int = roundi((i/4)*sheet.get_height()/4.0)
		var right: int = roundi(((i%4)+1)*sheet.get_width()/4.0)
		var bottom: int = roundi(((i/4)+1)*sheet.get_height()/4.0)
		var cell: Image = sheet.get_region(Rect2i(left,top,right-left,bottom-top))
		# Remove invisible matte RGB and faint isolated alpha noise before sampling.
		for y: int in range(cell.get_height()):
			for x: int in range(cell.get_width()):
				if cell.get_pixel(x,y).a<0.015: cell.set_pixel(x,y,Color(0,0,0,0))
		var used: Rect2i = cell.get_used_rect()
		assert(used.has_area() and used.position.x>0 and used.position.y>0 and used.end.x<cell.get_width() and used.end.y<cell.get_height(),"Generated frame touches another cell or is empty")
		var bounds: Array = item.frame.visible_bounds
		var fitted: Image = Image.create(width,height,false,Image.FORMAT_RGBA8); fitted.fill(Color(0,0,0,0))
		var art: Image = resized(cell.get_region(used),Vector2i(int(bounds[2])*SCALE,int(bounds[3])*SCALE))
		fitted.blit_rect(art,Rect2i(Vector2i.ZERO,art.get_size()),Vector2i(int(bounds[0])*SCALE,int(bounds[1])*SCALE))
		canonical[str(item.direction)+"/"+str(item.state)+"/"+str(int(item.index))] = fitted
	var result: Dictionary = original.duplicate(true)
	var counter: int = 0
	var resource: String = "res://content/characters/npc_enhanced/npc"+gid+"_2x.png"
	for direction: String in ["south","east","north","west"]:
		for state: String in ["idle","frames","attack"]:
			var raw: Variant = original[state][direction]
			var old: Array = raw if raw is Array else [raw]
			var updated: Array = []
			for index: int in range(old.size()):
				var source_direction: String = "south" if direction in ["south","east"] else "north"
				var frame: Image = (canonical[source_direction+"/"+state+"/"+str(index)] as Image).duplicate()
				if direction in ["east","west"]: frame.flip_x()
				var at: Vector2i = Vector2i((counter%8)*width,(counter/8)*height)
				atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,frame.get_size()),at)
				var descriptor: Dictionary = old[index].duplicate(true)
				descriptor.path = resource
				descriptor.region = [at.x,at.y,width,height]
				descriptor.pixel_scale = SCALE
				var visible: Array = descriptor.visible_bounds
				descriptor.visible_bounds = [int(visible[0])*SCALE,int(visible[1])*SCALE,int(visible[2])*SCALE,int(visible[3])*SCALE]
				updated.append(descriptor); counter+=1
			result[state][direction] = updated if raw is Array else updated[0]
	assert(atlas.save_png(output.path_join("npc"+gid+"_2x.png"))==OK)
	details.append({"graphic":int(gid),"frames":counter,"dimensions":[atlas.get_width(),atlas.get_height()],"rgba_bytes":atlas.get_width()*atlas.get_height()*4,"pixel_scale":SCALE})
	return result

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=5: push_error("Expected sources, Piglet image, Banshi image, output directory and report"); quit(1); return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	DirAccess.make_dir_recursive_absolute(args[3])
	var graphics: Dictionary = {"154":pack(data["154"],args[1],args[3],"154"),"134":pack(data["134"],args[2],args[3],"134")}
	FileAccess.open(args[3].path_join("pack.json"),FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"graphics":graphics},"  ")+"\n")
	FileAccess.open(args[4],FileAccess.WRITE).store_string(JSON.stringify({"result":"passed","atlases":details,"total_rgba_bytes":details[0].rgba_bytes+details[1].rgba_bytes},"  ")+"\n")
	print("Packed original idle/walk/attack poses for Piglet and Banshi at 2x; logical size/offsets unchanged")
	quit()
