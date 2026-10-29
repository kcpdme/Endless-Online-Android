extends RefCounted
## Resizable original EO timber and bevels, with live mobile-sized controls.
const BASE:String="res://content/ui/dialog_"
static var cache:Dictionary={}

static func style(kind:String="shop", inset:bool=false, tint:Color=Color.WHITE)->StyleBoxTexture:
	var key:String=("inset" if inset else kind)+str(tint)
	if cache.has(key):return cache[key]
	var box:StyleBoxTexture=StyleBoxTexture.new()
	var path:String=BASE+("inset" if inset else kind)+".png"
	if not ResourceLoader.exists(path):path=BASE+"shop.png"
	if ResourceLoader.exists(path):box.texture=load(path) as Texture2D
	box.modulate_color=tint
	for edge:int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_texture_margin(edge,3 if inset else 8)
		box.set_content_margin(edge,8 if inset else 16)
	box.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	cache[key]=box
	return box

static func apply(card:Control, kind:String="shop")->void:
	card.set_meta("classic_dialog_kind",kind)
	card.add_theme_stylebox_override("panel",style(kind))
	# Inherited styles cover controls inserted later, e.g. town-board entries.
	var theme:Theme=Theme.new()
	for type:String in ["ItemList","LineEdit","TextEdit","RichTextLabel","PanelContainer"]:
		for state:String in ["panel","normal","read_only"]:theme.set_stylebox(state,type,style(kind,true))
	for state:String in ["normal","hover","pressed","disabled"]:
		theme.set_stylebox(state,"Button",style(kind,true,Color("ffe6b0") if state=="hover" else Color("bda478") if state=="disabled" else Color.WHITE))
	card.theme=theme

static func finish(node:Node)->void:
	# Replace generic teal overrides on live widgets, while retaining transparent
	# hit targets on the bitmap paperdoll and stat allocation controls.
	if node is Button and not node.has_meta("classic_button_done") and not node.has_meta("preserve_button_skin"):
		var normal:StyleBox=node.get_theme_stylebox("normal")
		if normal is StyleBoxFlat and normal.bg_color.a>0.0:
			var primary:bool=normal.bg_color.r>.65 and normal.bg_color.g>.40
			for state:String in ["normal","hover","pressed","disabled"]:
				var tint:Color=Color("ffe1a1") if primary else Color.WHITE
				if state=="hover":tint=tint.lightened(.15)
				elif state=="pressed":tint=tint.darkened(.2)
				elif state=="disabled":tint=Color("8d8168")
				node.add_theme_stylebox_override(state,style("shop",true,tint))
			for state:String in ["font_color","font_hover_color","font_pressed_color"]:node.add_theme_color_override(state,Color("fff0cf"))
			node.add_theme_color_override("font_disabled_color",Color("b7a78c"))
			node.set_meta("classic_button_done",true)
	elif (node is Panel or node is PanelContainer) and not node.has_meta("classic_dialog_kind"):
		if node.get_theme_stylebox("panel") is StyleBoxFlat:node.add_theme_stylebox_override("panel",style("shop",true))
	elif node is ItemList and not node.has_meta("preserve_panel_skin"):
		if node.get_theme_stylebox("panel")!=style("shop",true):node.add_theme_stylebox_override("panel",style("shop",true))
	elif node is LineEdit or node is TextEdit:
		if node.get_theme_stylebox("normal")!=style("shop",true):node.add_theme_stylebox_override("normal",style("shop",true))
	for child:Node in node.get_children():finish(child)
