extends SceneTree
## Compact 2x atlases for all player poses and item art; retain native placement.
const ROOT:String="res://content/visual_enhanced/"
const PAD:int=2
var jobs:Dictionary
var base:String
var output:String
var pixels:Dictionary={}
var atlas_sets:Dictionary={}
var atlases:Dictionary={}
var imports:Dictionary={}
var empty:Dictionary={}
var poses:Array=[]
var pose_ids:Dictionary={}

func intern(pose:Dictionary)->int:
	var key:String=JSON.stringify(pose)
	if not pose_ids.has(key):pose_ids[key]=poses.size();poses.append(pose)
	return int(pose_ids[key])

func refined(id:String)->Image:
	if pixels.has(id):return pixels[id]
	var spec:Dictionary=jobs.crops[id]
	var image:Image=Image.load_from_file(base.path_join("scaled/"+id+".png"))
	assert(image!=null)
	image.convert(Image.FORMAT_RGBA8);image.premultiply_alpha()
	image.resize(int(spec.size[0])*2,int(spec.size[1])*2,Image.INTERPOLATE_LANCZOS)
	for y:int in range(image.get_height()):
		for x:int in range(image.get_width()):
			var c:Color=image.get_pixel(x,y)
			image.set_pixel(x,y,Color(c.r/c.a,c.g/c.a,c.b/c.a,c.a) if c.a>.0001 else Color(0,0,0,0))
	if bool(spec.preserve_black):
		# Exact black is the original hat/hair clip mask, not a shading suggestion.
		var source:Image=Image.load_from_file(base.path_join("crops/"+id+".png"))
		for y:int in range(source.get_height()):
			for x:int in range(source.get_width()):
				var c:Color=source.get_pixel(x,y)
				if c.r==0 and c.g==0 and c.b==0 and c.a>0:
					for dy:int in range(2):
						for dx:int in range(2):image.set_pixel(x*2+dx,y*2+dy,c)
	pixels[id]=image;return image

func layout(ids:Array,width:int)->Dictionary:
	var positions:Dictionary={};var x:int=0;var y:int=0;var row:int=0;var used:int=0
	for id:String in ids:
		var size:Vector2i=Vector2i(jobs.crops[id].size[0]*2+PAD*2,jobs.crops[id].size[1]*2+PAD*2)
		if x+size.x>width:x=0;y+=row;row=0
		positions[id]=Vector2i(x+PAD,y+PAD);x+=size.x;row=maxi(row,size.y);used=maxi(used,x)
	return {"positions":positions,"size":Vector2i(used,y+row)}

func sheet(raw:Array)->Dictionary:
	var ids:Array=[];var placements:Dictionary={}
	for id:String in raw:
		if jobs.crops[id].empty and jobs.crops[id].size==[1.0,1.0]:placements[id]=empty
		elif not id in ids:ids.append(id)
	if ids.is_empty():return placements
	ids.sort();var signature:String=";".join(ids).sha256_text()
	if atlas_sets.has(signature):
		placements.merge(atlas_sets[signature]);return placements
	var area:int=0;var minimum:int=0;var lossless:bool=false
	for id:String in ids:
		var s:Array=jobs.crops[id].size
		area+=(int(s[0])*2+PAD*2)*(int(s[1])*2+PAD*2);minimum=maxi(minimum,int(s[0])*2+PAD*2)
		lossless=lossless or bool(jobs.crops[id].preserve_black)
	ids.sort_custom(func(a:String,b:String)->bool:
		var sa:Array=jobs.crops[a].size;var sb:Array=jobs.crops[b].size
		return sa[1]>sb[1] if sa[1]!=sb[1] else a<b
	)
	var width:int=mini(2048,maxi(minimum,ceili(sqrt(float(area))*1.15)))
	var packed:Dictionary=layout(ids,width)
	while packed.size.y>2048 and width<2048:
		width=mini(2048,width+128);packed=layout(ids,width)
	assert(packed.size.x<=2048 and packed.size.y<=2048,"Atlas exceeds mobile limit")
	var image:Image=Image.create(packed.size.x,packed.size.y,false,Image.FORMAT_RGBA8);image.fill(Color(0,0,0,0))
	var name:String="p_"+signature.substr(0,24)+".png";var path:String=ROOT+name;var entries:Dictionary={}
	for id:String in ids:
		var source:Image=refined(id);var at:Vector2i=packed.positions[id]
		image.blit_rect(source,Rect2i(Vector2i.ZERO,source.get_size()),at)
		var used:Rect2i=source.get_used_rect()
		entries[id]={"path":path,"region":[at.x,at.y,source.get_width(),source.get_height()],"visible_bounds":[used.position.x,used.position.y,used.size.x,used.size.y]}
	assert(image.save_png(output.path_join(name))==OK)
	atlases[path]=[image.get_width(),image.get_height()];imports[path]=lossless
	atlas_sets[signature]=entries;placements.merge(entries);return placements

func _initialize()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:push_error("Expected JOBS.json OUTPUT_DIRECTORY");quit(1);return
	base=args[0].get_base_dir();output=args[1];DirAccess.make_dir_recursive_absolute(output)
	jobs=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var blank:Image=Image.create(6,6,false,Image.FORMAT_RGBA8);blank.fill(Color(0,0,0,0));blank.save_png(output.path_join("p_empty.png"))
	empty={"path":ROOT+"p_empty.png","region":[2,2,2,2],"visible_bounds":[0,0,0,0]}
	atlases[empty.path]=[6,6];imports[empty.path]=true
	var by_source:Dictionary={};var frames:Dictionary={};var images:Dictionary={}
	for path:String in jobs.groups:
		by_source[path]=sheet(jobs.groups[path])
	for key:String in jobs.frames:
		var e:Dictionary=jobs.frames[key];var index:int=intern(by_source[e.source][e.id])
		frames[key]=[index,e.crop[0],e.crop[1],e.crop[2],e.crop[3],e.get("flip_h",false)]
	var item_paths:Array=jobs.images.keys()
	for start:int in range(0,item_paths.size(),32):
		var paths:Array=item_paths.slice(start,start+32);var ids:Array=[]
		for path:String in paths:ids.append(jobs.images[path].id)
		var entries:Dictionary=sheet(ids)
		for path:String in paths:
			var e:Dictionary=jobs.images[path]
			images[path]=[intern(entries[e.id]),e.size[0],e.size[1],e.get("flip_h",false)]
	FileAccess.open(output.path_join("pack.json"),FileAccess.WRITE).store_string(JSON.stringify({"schema":2,"frames":frames,"images":images,"poses":poses,"atlases":atlases})+"\n")
	FileAccess.open(base.path_join("import-modes.json"),FileAccess.WRITE).store_string(JSON.stringify(imports)+"\n")
	var bytes:int=0
	for size:Array in atlases.values():bytes+=int(size[0])*int(size[1])*4
	FileAccess.open(base.path_join("pack-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"result":"passed","frames":frames.size(),"item_images":images.size(),"atlases":atlases.size(),"unique_crops":jobs.crops.size(),"decoded_rgba_bytes":bytes,"lossless_mask_atlases":imports.values().count(true)},"  ")+"\n")
	print("Packed ",frames.size()," player poses and ",images.size()," item images into ",atlases.size()," compact atlases");quit()
