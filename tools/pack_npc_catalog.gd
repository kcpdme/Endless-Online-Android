extends SceneTree
## Pack prepared canonical poses, preserving all native pose metadata.
## Args: SOURCES.json PREPARED_POSE_DIRECTORY OUTPUT_DIRECTORY REPORT.json
const SCALE:int=2
const GUTTER:int=2
var report:Array=[]
var failed:bool=false

func fit(source:Image,size:Vector2i)->Image:
	if source.get_size()==size:return source
	var result:Image=source.duplicate();result.convert(Image.FORMAT_RGBA8);result.premultiply_alpha()
	result.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	for y:int in range(size.y):
		for x:int in range(size.x):
			var c:Color=result.get_pixel(x,y)
			result.set_pixel(x,y,Color(c.r/c.a,c.g/c.a,c.b/c.a,c.a) if c.a>.0001 else Color(0,0,0,0))
	return result

func descriptors(value:Variant)->Array:
	return value if value is Array else [value]

func pack(gid:String,entry:Dictionary,path:String,directory:String)->Dictionary:
	var original:Dictionary=entry.original
	var reference:Dictionary=entry.frames[0].frame
	var width:int=int(reference.region[2])*SCALE;var height:int=int(reference.region[3])*SCALE
	for item:Dictionary in entry.frames:
		width=maxi(width,int(item.frame.region[2])*SCALE);height=maxi(height,int(item.frame.region[3])*SCALE)
	var stride:Vector2i=Vector2i(width+GUTTER*2,height+GUTTER*2)
	var columns:int=mini(4,2048/stride.x)
	var rows:int=ceili(float(entry.frames.size())/columns)
	if columns<=0 or rows*stride.y>2048:
		failed=true;push_error("Atlas exceeds limit: "+gid);return {}
	var atlas:Image=Image.create(columns*stride.x,rows*stride.y,false,Image.FORMAT_RGBA8);atlas.fill(Color(0,0,0,0))
	var slots:Dictionary={}
	for i:int in range(entry.frames.size()):
		var item:Dictionary=entry.frames[i];var bounds:Array=item.frame.visible_bounds
		var size:Vector2i=Vector2i(int(item.frame.region[2])*SCALE,int(item.frame.region[3])*SCALE)
		var at:Vector2i=Vector2i((i%columns)*stride.x+GUTTER,(i/columns)*stride.y+GUTTER)
		var source:Image=Image.load_from_file(path.path_join(str(item.frame.path).get_file()))
		if source==null or source.get_width()%(size.x/SCALE)!=0 or source.get_height()%(size.y/SCALE)!=0 or source.get_width()/size.x!=source.get_height()/size.y:
			failed=true;push_error("Missing or invalid prepared pose: "+gid+" "+str(i));return {}
		var refined:Image=fit(source,size)
		if int(bounds[2])==0 or int(bounds[3])==0:refined.fill(Color(0,0,0,0))
		atlas.blit_rect(refined,Rect2i(Vector2i.ZERO,refined.get_size()),at)
		# Empty native poses (Ancient Wraith) deliberately stay transparent.
		slots[str(item.direction)+"/"+str(item.state)+"/"+str(int(item.index))]=[at.x,at.y,size.x,size.y]
	var resource:String="res://content/characters/npc_enhanced/npc"+gid+"_2x.png"
	var result:Dictionary=original.duplicate(true);var frame_count:int=0
	for direction:String in ["south","east","north","west"]:
		for state:String in ["idle","frames","attack"]:
			var raw:Variant=original[state][direction];var updated:Array=[]
			for index:int in range(descriptors(raw).size()):
				var f:Dictionary=descriptors(raw)[index].duplicate(true)
				var canonical:String="south" if direction in ["south","east"] else "north"
				f.path=resource;f.region=slots[canonical+"/"+state+"/"+str(index)];f.pixel_scale=SCALE
				f.flip_h=direction in ["east","west"]
				var b:Array=f.visible_bounds;f.visible_bounds=[int(b[0])*SCALE,int(b[1])*SCALE,int(b[2])*SCALE,int(b[3])*SCALE]
				updated.append(f);frame_count+=1
			result[state][direction]=updated if raw is Array else updated[0]
	var output:String=directory.path_join("npc"+gid+"_2x.png")
	if atlas.save_png(output)!=OK:failed=true;return {}
	report.append({"graphic":int(gid),"frames":frame_count,"stored_poses":entry.frames.size(),"dimensions":[atlas.get_width(),atlas.get_height()],"rgba_bytes":atlas.get_width()*atlas.get_height()*4,"png_bytes":FileAccess.get_file_as_bytes(output).size()})
	return result

func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=4:push_error("Expected sources, enhanced directory, output directory and report");quit(1);return
	var sources:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[0]));var graphics:Dictionary={}
	DirAccess.make_dir_recursive_absolute(args[2])
	for gid:String in sources:
		var result:Dictionary=pack(gid,sources[gid],args[1],args[2])
		if not result.is_empty():graphics[gid]=result
	if not failed:
		FileAccess.open(args[2].path_join("pack.json"),FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"graphics":graphics})+"\n")
	FileAccess.open(args[3],FileAccess.WRITE).store_string(JSON.stringify({"result":"failed" if failed else "passed","graphics":graphics.size(),"atlases":report},"  ")+"\n")
	print("NPC catalog: ",graphics.size()," / ",sources.size());quit(1 if failed else 0)
