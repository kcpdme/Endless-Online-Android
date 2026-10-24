extends RefCounted
## Touch screens for native town, account and social services.
var game: Node
var panel: Control
var card: Control
var scroll: ScrollContainer
var heading: Label
var content: VBoxContainer
var status: Label
var confirmation: ConfirmationDialog
var fields: Dictionary = {}
var state: Dictionary = {}
var kind: String = ""
var busy: bool = false
var pending_confirmation: Callable
var reduced_motion: bool = false
var quake_until: int = 0
var quake_strength: float = 0

func build(owner: Node, parent: Control) -> void:
	game = owner
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load("user://accessibility.cfg") == OK: reduced_motion = bool(cfg.get_value("motion","reduced",false))
	panel = game._modal(parent,Vector2(940,650))
	card = panel.get_child(0); card.set_anchors_preset(Control.PRESET_TOP_LEFT,true); game._wood_card(card)
	heading = game._label(card,"Town services",Vector2(28,18),28,game.GOLD)
	game._button(card,"×",Vector2(858,12),Vector2(54,48),close)
	scroll = ScrollContainer.new(); scroll.position=Vector2(28,82); scroll.size=Vector2(884,470);scroll.follow_focus=true
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;card.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",12);scroll.add_child(content)
	status=game._label(card,"",Vector2(28,568),19);status.size=Vector2(884,64);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	confirmation=ConfirmationDialog.new();confirmation.dialog_autowrap=true;panel.add_child(confirmation)
	confirmation.confirmed.connect(func() -> void:
		if pending_confirmation.is_valid(): pending_confirmation.call()
		pending_confirmation=Callable()
	)
	panel.hide()

func close() -> void:
	blur();confirmation.hide();pending_confirmation=Callable();panel.hide()
	for key: String in ["old_password","new_password","repeat_password"]:
		if fields.has(key) and is_instance_valid(fields[key]): fields[key].text=""

func clear_content() -> void:
	fields.clear()
	for child: Node in content.get_children():content.remove_child(child);child.queue_free()

func label(value: String) -> Label:
	var node: Label=game._label(content,value,Vector2.ZERO,21)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return node

func field(key: String, hint: String, secret: bool=false, multiline: bool=false) -> Control:
	label(hint)
	var node: Control=TextEdit.new() if multiline else LineEdit.new()
	node.custom_minimum_size.y=100 if multiline else 54
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if node is LineEdit:node.secret=secret;node.max_length=64 if secret else 64
	node.add_theme_font_size_override("font_size",22);content.add_child(node);fields[key]=node;return node

func button(title: String, action: Callable) -> Button:
	var node: Button=game._button(content,title,Vector2.ZERO,Vector2.ONE,func() -> void:
		if not busy:action.call()
	)
	node.custom_minimum_size.y=54;node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return node

func ask(message: String, action: Callable) -> void:
	blur();pending_confirmation=action;confirmation.dialog_text=message;confirmation.popup_centered(Vector2i(640,260))

func blur() -> void:
	for control: Variant in fields.values():
		if is_instance_valid(control) and control is Control:control.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):DisplayServer.virtual_keyboard_hide()

func layout(keyboard_override: float=-1.0) -> void:
	var lift: float=keyboard_override
	if lift<0:
		lift=float(DisplayServer.virtual_keyboard_get_height())*game.get_viewport_rect().size.y/maxf(1.0,DisplayServer.window_get_size().y) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	var available: Vector2=panel.size-Vector2(0,lift)
	card.size=Vector2(minf(940,available.x-24),minf(650,available.y-24))
	card.position=(available-card.size)/2
	scroll.size=Vector2(card.size.x-56,maxf(40,card.size.y-180))
	status.position=Vector2(28,card.size.y-82);status.size.x=card.size.x-56

func open(mode: String, request: Dictionary={}) -> void:
	if busy:return
	kind=mode;state={"location":request.duplicate()} if mode=="board" else {};game.menu.hide();game._cancel_controls();game.skills_ui.armed=0;panel.get_parent().move_child(panel,-1);panel.show()
	if mode in ["password","delete"]:render();return
	clear_content();heading.text=mode.capitalize();status.text="Loading…"
	var payload: Dictionary=request.duplicate();payload.kind=mode
	send("feature_open",payload)

func send(operation: String, payload: Dictionary) -> void:
	if busy:return
	busy=true;status.text="Waiting for the server…"
	if game.online.session.request(operation,payload)<0:busy=false;status.text="Connection lost."

func action(operation: String, ident: int=0, text: String="", body: String="") -> void:
	send("feature_action",{"kind":kind,"action":operation,"ident":ident,"text":text,"body":body})

func selected() -> int:
	var list: ItemList=fields.get("list") as ItemList
	if list==null or list.get_selected_items().is_empty():return 0
	return int(list.get_item_metadata(list.get_selected_items()[0]))

func render() -> void:
	clear_content();heading.text={"law":"Law Bob","priest":"Wedding ceremony","board":"Town message board","jukebox":"Jukebox","reset":"Reset attributes and skills","password":"Change account password","delete":"Delete selected character","book":"Character book","social":"Social and accessibility"}.get(kind,kind.capitalize())
	status.text=str(state.get("notice",""))
	match kind:
		"social":
			button("Emotes",func() -> void:open("emotes"))
			button("Find a player",func() -> void:open("find"))
			button("My character book",func() -> void:open("book"))
			button("Contact admin / report player",func() -> void:open("report"))
			button("Disable whispers" if bool(state.get("whispers",true)) else "Enable whispers",func() -> void:action("whispers",0 if bool(state.get("whispers",true)) else 1))
			var toggle: CheckBox=CheckBox.new();toggle.text="Reduce camera motion";toggle.custom_minimum_size.y=54;toggle.add_theme_font_size_override("font_size",22);toggle.button_pressed=reduced_motion;content.add_child(toggle)
			toggle.toggled.connect(func(enabled: bool) -> void:
				reduced_motion=enabled;var cfg: ConfigFile=ConfigFile.new();cfg.set_value("motion","reduced",enabled);cfg.save("user://accessibility.cfg")
			)
		"emotes":
			var names: Array[String]=["Happy","Depressed","Sad","Angry","Confused","Surprised","Hearts","Moon","Dismay","Embarrassed"]
			for index: int in names.size():
				var ident: int=index+1;button(names[index],func() -> void:action("emote",ident))
			button("Playful",func() -> void:action("emote",14))
		"find":
			field("name","Character name");button("Find",func() -> void:action("find",0,str(fields.name.text)))
		"report":
			field("name","Player name (required only for a report)");field("body","Explain what happened — up to 256 characters",false,true)
			button("Ask an admin for help",func() -> void:action("help",0,"",str(fields.body.text)))
			button("Report this player",func() -> void:ask("Send this report to the admins?",func() -> void:action("report",0,str(fields.name.text),str(fields.body.text))))
		"book":
			label("%s · %s\n%s · %s\nPartner: %s"%[state.get("name",""),state.get("title",""),state.get("home",""),state.get("guild",""),state.get("partner","")])
			label("Completed quests")
			for quest: String in state.get("quests",[]):label(quest)
		"reset":
			label("All six attributes return to zero and learned skills are removed. Your level and items stay with you. Level-based points become available again.")
			button("Reset attributes and skills",func() -> void:ask("Reset all attributes and learned skills? Skill shortcuts will be cleared.",func() -> void:action("reset")))
		"law":
			var prices: Dictionary=state.get("prices",{}) as Dictionary
			field("name","Partner’s character name")
			button("Marriage approval · %s Gold"%prices.get("MarriagePrice","500"),func() -> void:ask("Buy marriage approval for this partner?",func() -> void:action("approve",0,str(fields.name.text))))
			button("Divorce · %s Gold"%prices.get("DivorcePrice","10000"),func() -> void:ask("End this marriage and pay the divorce fee?",func() -> void:action("divorce",0,str(fields.name.text))))
		"priest":
			label("Both partners need Law Bob approval and their wedding outfits. Wait for the priest’s vow prompt before saying I do.")
			field("name","Partner’s character name")
			button("Request wedding",func() -> void:action("request",0,str(fields.name.text)))
		"board":
			if state.has("body"):label(str(state.body));button("Back to posts",func() -> void:open("board",state.get("location",{}) as Dictionary));return
			var list: ItemList=ItemList.new();list.custom_minimum_size.y=154;list.add_theme_font_size_override("font_size",21);content.add_child(list);fields.list=list
			for post: Dictionary in state.get("posts",[]):
				var row: int=list.add_item(str(post.subject)+" · "+str(post.author));list.set_item_metadata(row,int(post.id))
			button("Read selected post",func() -> void:action("read",selected()))
			if int((game.online.player.get("stats",{}) as Dictionary).get("admin",0))>0:button("Remove selected post",func() -> void:ask("Remove this post?",func() -> void:action("remove",selected())))
			field("subject","Post subject (up to 64 characters)");field("body","Post message (up to 256 characters)",false,true)
			button("Publish post",func() -> void:ask("Publish this message on the town board?",func() -> void:action("post",0,str(fields.subject.text),str(fields.body.text))))
		"jukebox":
			label("Cost: %s Gold · Current DJ: %s"%[state.get("price",0),state.get("owner","")])
			for index: int in range(int(state.get("songs",0))+1):
				var song: int=index;button("Play track %d"%(song+1),func() -> void:ask("Pay %s Gold to play track %d?"%[state.get("price",0),song+1],func() -> void:action("play",song)))
		"password":
			label("Change this account’s password. Saved login will be cleared after success.")
			field("old_password","Current password",true);field("new_password","New password (6–64 characters)",true);field("repeat_password","Repeat new password",true)
			button("Change password",change_password)
		"delete":
			var selections: PackedInt32Array=game.online.character_list.get_selected_items()
			if selections.is_empty():label("Select a character first.");return
			state.character=(game.online.selected_characters[selections[0]] as Dictionary).duplicate()
			label("Permanently delete %s, including inventory and quest progress? Type the character’s name to confirm."%str(state.character.name))
			field("name","Character name")
			button("Delete permanently",func() -> void:
				if str(fields.name.text).strip_edges().to_lower()!=str(state.character.name).to_lower():status.text="Type the selected character’s exact name.";return
				ask("Permanently delete "+str(state.character.name)+"?",func() -> void:send("delete_character",{"character_id":int(state.character.id),"name":str(fields.name.text)}))
			)

func change_password() -> void:
	if str(fields.new_password.text)!=str(fields.repeat_password.text):status.text="New passwords do not match.";return
	send("change_password",{"old_password":str(fields.old_password.text),"new_password":str(fields.new_password.text)})

func response(message: Dictionary) -> void:
	var operation: String=str(message.get("op",""))
	if operation not in ["feature_open","feature_action","delete_character","change_password"]:return
	busy=false
	if not bool(message.get("ok",false)):status.text=str(message.get("error","Action failed."));return
	var data: Dictionary=message.get("data",{}) as Dictionary
	if operation=="delete_character":close();game.online._show_characters(data.get("characters",[]) as Array);return
	if operation=="change_password":
		close();game.online.login_store.forget();game.online.character_flow.save_automatic_choice(false);game.online.character_flow.remember.set_pressed_no_signal(false);game.online.character_flow.automatic.set_pressed_no_signal(false);game.online.resume_token="";game.online.reconnection.forget();game.online.character_flow.restored_login.clear();game.online._set_status("Password changed. Saved login cleared.");return
	if not data.has("feature"):return
	var reply: Dictionary=data.feature as Dictionary
	if bool(reply.get("reset",false)):
		var profile: String=game.online.profile_identity()
		var store = preload("res://scripts/shortcut_store.gd")
		store.clear_slots(game.online.shortcuts.pending_path,profile+"/skills")
		store.write_slots(game.skills_ui.settings_path,profile,[0,0])
		game.online.shortcuts.queued.erase("skills")
	if not panel.visible:return
	if str(reply.kind)!=kind:return
	if operation=="feature_open" or reply.has("posts") or reply.has("body"):
		var previous_location: Dictionary=state.get("location",{}) as Dictionary
		state=reply.duplicate(true)
		if kind=="board":state.location=previous_location
		render()
	else:
		state.merge(reply,true);status.text=str(reply.get("notice",""))
		if kind=="social":render()
		if bool(reply.get("reset",false)) or kind in ["law","emotes","priest"]:close()

func event(data: Dictionary) -> void:
	if data.get("kind")=="jukebox_music":game.music.selected_id=int(data.track);game.music.selected_control=1;game.music._apply(int(data.track),1)
	if data.get("kind")=="wedding_invite" or (data.get("kind")=="wedding_notice" and int(data.get("code",0))==6):
		kind="priest";state={};game.menu.hide();game._cancel_controls();render();panel.get_parent().move_child(panel,-1);panel.show()
		var reply: String="accept" if data.kind=="wedding_invite" else "vow"
		ask("Accept wedding invitation from %s?"%str(data.get("name","partner")) if reply=="accept" else "Do you take this partner?",func() -> void:action(reply))
	elif data.get("kind")=="wedding_notice":game._toast(str(data.message));status.text=str(data.message)

func tick() -> void:
	if panel.visible:layout()
	if reduced_motion or Time.get_ticks_msec()>=quake_until:game.camera.offset=Vector2.ZERO
	else:
		var t: float=float(Time.get_ticks_msec())/55.0;game.camera.offset=Vector2(sin(t*1.9),cos(t*2.3))*quake_strength

func disconnected() -> void:
	close();clear_content();state.clear();busy=false;quake_until=0;game.camera.offset=Vector2.ZERO
