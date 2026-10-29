extends RefCounted
## Small vector skill glyphs and bounded animated impacts; no raster art pack.
const COLORS:Array[String]=["e5bb72","f5da85","8abfff","d6a2ee","9bdea4","e9ac71","ae9bea"]
const CONVERTED:Array[int]=[3,16,18,27,37,39,46]

static func style(ident:int,spell:Dictionary)->String:
	if ident==17:return "music"
	if spell.get("effect_kind","")=="companion":return "pet"
	if int(spell.get("hp",0))>0:return "heal"
	var classes:Array=spell.get("allowed_classes",[])
	var clas:int=int(classes[0]) if not classes.is_empty() else 3
	if clas==4:return "dagger"
	if clas==5:return "arrow"
	if clas==6:return "hammer" if ident in [38,40,45,46] else "sword"
	if clas==2:return "holy"
	if clas==7:return "spirit"
	if ident in [4,10,25,31]:return "fire"
	if ident in [14,21]:return "ice"
	if ident==5:return "thunder"
	if ident==19:return "stone"
	return "arcane"

static func color(spell:Dictionary)->Color:
	var classes:Array=spell.get("allowed_classes",[])
	var clas:int=int(classes[0]) if not classes.is_empty() else 3
	if clas==7:return Color(str((spell.get("companion",{}) as Dictionary).get("tier_color","ae9bea")))
	return Color(COLORS[clampi(clas-1,0,6)])

static func icon(ident:int,spell:Dictionary,highlight:bool=false)->Texture2D:
	if ident<=0 or spell.is_empty():return null
	var shapes:Dictionary={
		"heal":"<path d='M19 10h10v9h9v10h-9v9H19v-9h-9V19h9z'/>",
		"holy":"<path d='M23 7v32M12 18h24M11 32l-4 5M37 32l4 5' fill='none' stroke-width='5'/>",
		"fire":"<path d='M25 6C32 18 43 22 36 34C30 44 12 39 12 29C12 21 18 18 19 13L23 24C28 18 26 12 25 6z'/>",
		"thunder":"<path d='M28 5L11 27h11l-3 16 18-25H26z'/>",
		"ice":"<path d='M24 6v36M8 15l32 18M8 33l32-18M19 9l5 5 5-5M19 39l5-5 5 5' fill='none' stroke-width='3'/>",
		"dagger":"<path d='M37 7L17 23l7 7zM10 23l15 15M17 32l-9 9' stroke-width='3'/>",
		"sword":"<path d='M32 6l7 2-2 7-16 18-6-6zM10 26l15 13M16 34l-7 8' stroke-width='3'/>",
		"hammer":"<path d='M24 16L10 39l6 4 15-23zM19 7l19 10-6 11-19-10z' stroke-width='2'/>",
		"arrow":"<path d='M8 39L38 9M27 9h11v11M9 28l11 11M14 23l11 11' fill='none' stroke-width='4'/>",
		"spirit":"<path d='M13 36V20C13 5 35 5 35 20v16l-6-4-5 6-5-6z'/><path d='M18 20h3M27 20h3' stroke='#14202b' stroke-width='4'/>",
		"pet":"<path d='M24 7C16 7 11 24 11 31c0 13 26 13 26 0C37 24 32 7 24 7z'/><path d='M13 28l7-4 5 6 8-5' fill='none' stroke='#273248' stroke-width='3'/>",
		"music":"<path d='M20 34V11l17-4v23M20 16l17-4' fill='none' stroke-width='4'/><ellipse cx='14' cy='35' rx='7' ry='5'/><ellipse cx='31' cy='31' rx='7' ry='5'/>",
		"stone":"<path d='M8 28l6-15 15-7 12 16-7 17-18 2z'/><path d='M14 13l11 13 16-4M25 26l-9 15' fill='none' stroke='#4b4c67' stroke-width='2'/>",
		"arcane":"<circle cx='24' cy='24' r='13'/><path d='M5 24h8M35 24h8M24 5v8M24 35v8' fill='none' stroke-width='2'/>",
	}
	var tint:String=color(spell).to_html(false)
	var glyph:String=str(shapes.get(style(ident,spell),shapes.arcane))
	# Different tiny rune marks distinguish abilities sharing the same family.
	var marks:String=""
	for n:int in range(1+ident%5):marks+="<circle cx='%d' cy='43' r='1.2' fill='#fff1ce'/>"%(18+n*3)
	for bit:int in range(6):
		if ident & (1<<bit):marks+="<rect x='43' y='%d' width='2' height='2' rx='.5' fill='#fff1ce'/>"%(8+bit*5)
	var detail:String="<path d='M%d 5h5M5 %dv5' stroke='#fff1ce' stroke-width='1.5'/>"%[8+ident%20,8+(ident*7)%20]
	var svg:String="<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><rect x='1' y='1' width='46' height='46' rx='9' fill='#14222d' stroke='#%s' stroke-width='%d'/><g fill='#%s' stroke='#%s' stroke-linecap='round' stroke-linejoin='round'>%s</g>%s%s</svg>"%["ffefb5" if highlight else tint,3 if highlight else 1,tint,tint,glyph,marks,detail]
	var pixels:Image=Image.new()
	if pixels.load_svg_from_string(svg)!=OK:return null
	return ImageTexture.create_from_image(pixels)

static func effect(ident:int,spell:Dictionary)->Dictionary:
	var native:Dictionary=(spell.get("effect",{}) as Dictionary).duplicate(true)
	if native.is_empty() or (native.get("paths",{}) as Dictionary).is_empty() or ident>=32 or ident in CONVERTED or spell.get("effect_kind","")=="companion":
		return {"procedural":true,"style":style(ident,spell),"color":color(spell),"frames":6,"loops":1,"spell_id":ident}
	return native

static func draw(game:Node,fx:Dictionary,front:bool)->void:
	if not front:return
	var progress:float=clampf((Time.get_ticks_msec()-int(fx.start))/720.0,0,1)
	var tint:Color=fx.color;tint.a=sin(progress*PI)
	var at:Vector2=(fx.at as Vector2)+Vector2(0,-28)
	var kind:String=str(fx.style)
	if kind in ["sword","dagger","hammer","arrow"]:
		var extent:float=12+sin(progress*PI)*14
		game.draw_line(at+Vector2(-extent,-extent),at+Vector2(extent,extent),tint,3.5,true)
		if kind!="arrow":game.draw_line(at+Vector2(-extent,extent*.6),at+Vector2(extent,-extent*.6),Color(tint,.7*tint.a),2,true)
		game.draw_arc(at,9+progress*14,-PI*.5+progress*PI,progress*PI,24,tint,2,true)
	else:
		var radius:float=8+sin(progress*PI)*11
		game.draw_arc(at,radius,0,TAU,40,tint,2,true)
		for i:int in range(6):
			var direction:Vector2=Vector2.RIGHT.rotated(i*TAU/6+progress)
			var centre:Vector2=at+direction*(radius+5)
			game.draw_line(centre-direction*3,centre+direction*3,tint,2,true)
		if kind in ["heal","holy"]:
			game.draw_line(at+Vector2(-8,-progress*10),at+Vector2(8,-progress*10),tint,3,true)
			game.draw_line(at+Vector2(0,-8-progress*10),at+Vector2(0,8-progress*10),tint,3,true)
		else:game.draw_circle(at,4+sin(progress*PI)*3,tint)
