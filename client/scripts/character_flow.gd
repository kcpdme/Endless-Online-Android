extends RefCounted
## Full-screen, safe-area-aware login, three native character slots and creation.
const MAX_CHARACTERS: int = 3
var c: Node
var game: Node
var heading: Label
var subtitle: Label
var server_options: Control
var server_toggle: Button
var selection_actions: HBoxContainer
var enter_button: Button
var create_button: Button
var capacity: Label
var creation_submit: Button
var gender_buttons: Array[Button] = []
var restored_login: Dictionary={}
var restoring_login: bool=false
var remember: CheckBox
var automatic: CheckBox
var options_path: String = "user://login_options.cfg"
var startup_login_checked: bool = false
var forget_button: Button
var login_hero: Control
var creation_hint: Label

func page(parent: Control) -> Array:
	var curtain: Control = game._modal(parent,Vector2.ONE)
	curtain.color = Color("091719")
	var card: Control = curtain.get_child(0)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 16; card.offset_top = 16; card.offset_right = -16; card.offset_bottom = -16
	card.add_theme_stylebox_override("panel",game._style(Color("10272a"),Color("697d70"),18))
	var margin: MarginContainer = MarginContainer.new()
	card.add_child(margin); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	var content: VBoxContainer = VBoxContainer.new(); content.add_theme_constant_override("separation",14); margin.add_child(content)
	return [curtain,content]

func text(parent: Node, value: String, font: int = 20, color: Color = Color("e8ecda")) -> Label:
	var label: Label = Label.new(); label.text = value; label.add_theme_font_size_override("font_size",font); label.add_theme_color_override("font_color",color); parent.add_child(label)
	return label

func button(parent: Node, value: String, action: Callable, primary: bool = false) -> Button:
	var result: Button = game._button(parent,value,Vector2.ZERO,Vector2(1,56),action,primary)
	result.custom_minimum_size = Vector2(0,56); result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func header(parent: Control, title: String, back: Callable) -> Label:
	var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation",20); parent.add_child(row)
	var label: Label = text(row,title,34,game.GOLD); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var control: Button = button(row,"Back",back); control.size_flags_horizontal = Control.SIZE_SHRINK_END; control.custom_minimum_size.x = 120
	return label

func field(parent: Node, placeholder: String) -> LineEdit:
	var result: LineEdit = LineEdit.new(); result.placeholder_text = placeholder; result.custom_minimum_size.y = 54; result.size_flags_horizontal = Control.SIZE_EXPAND_FILL; result.add_theme_font_size_override("font_size",22); parent.add_child(result)
	return result

func build(owner: Node, parent: Control) -> void:
	c = owner; game = c.game
	var parts: Array = page(parent); c.panel = parts[0]; var body: VBoxContainer = parts[1]
	heading = header(body,"Enter Aster Vale",c._close_panel)
	subtitle = text(body,"Log in or create an account to begin your adventure.",19,game.MUTED)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	c.auth_box = VBoxContainer.new(); c.auth_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.auth_box.add_theme_constant_override("separation",14); scroll.add_child(c.auth_box)
	var auth: HBoxContainer = HBoxContainer.new(); auth.add_theme_constant_override("separation",28); c.auth_box.add_child(auth)
	var form_card: PanelContainer=PanelContainer.new();form_card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;form_card.size_flags_stretch_ratio=.9;auth.add_child(form_card)
	var skin: StyleBoxFlat=game._style(Color("122327"),Color("71613d"),14)
	for edge: String in ["left","right","top","bottom"]:skin.set("content_margin_"+edge,18)
	form_card.add_theme_stylebox_override("panel",skin)
	var form: VBoxContainer = VBoxContainer.new(); form.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.add_theme_constant_override("separation",8); form_card.add_child(form)
	text(form,"WELCOME, ADVENTURER",20,game.GOLD)
	text(form,"Sign in to continue your journey.",16,game.MUTED)
	text(form,"Account",19,game.MUTED); c.username_field = field(form,"Account name"); c.username_field.max_length = 16
	text(form,"Password",19,game.MUTED); c.password_field = field(form,"Password"); c.password_field.secret = true; c.password_field.max_length = 64
	remember=CheckBox.new();remember.text="Remember login on this device";remember.custom_minimum_size.y=44;remember.add_theme_font_size_override("font_size",19);remember.visible=c.login_store.available();form.add_child(remember)
	remember.toggled.connect(func(enabled: bool) -> void:
		if not enabled:
			c.login_store.forget(); automatic.set_pressed_no_signal(false); save_automatic_choice(false)
	)
	automatic = CheckBox.new(); automatic.text = "Sign in automatically next time"; automatic.custom_minimum_size.y = 44; automatic.add_theme_font_size_override("font_size",19); automatic.visible = c.login_store.available(); form.add_child(automatic)
	automatic.toggled.connect(func(enabled: bool) -> void:
		if enabled: remember.set_pressed_no_signal(true)
		else: save_automatic_choice(false)
	)
	forget_button=button(form,"Forget saved login",func() -> void:
		c.login_store.forget();remember.set_pressed_no_signal(false);automatic.set_pressed_no_signal(false);save_automatic_choice(false);c.password_field.text="";c.auth_credentials.clear();c.reconnection.forget();restored_login.clear();forget_button.custom_minimum_size.y=44;forget_button.hide()
	);forget_button.custom_minimum_size.y=44;forget_button.hide()
	var actions: HBoxContainer = HBoxContainer.new(); actions.add_theme_constant_override("separation",14); form.add_child(actions)
	button(actions,"Log in",func() -> void: c._authenticate("login"),true)
	button(actions,"Create account",func() -> void: c._authenticate("register"))
	var note: VBoxContainer = VBoxContainer.new(); note.size_flags_horizontal = Control.SIZE_EXPAND_FILL; note.add_theme_constant_override("separation",14); auth.add_child(note)
	auth.move_child(note,0)
	login_hero=preload("res://scripts/login_hero.gd").new();login_hero.game=game
	login_hero.custom_minimum_size=Vector2(280,420);login_hero.size_flags_horizontal=Control.SIZE_EXPAND_FILL;login_hero.size_flags_vertical=Control.SIZE_EXPAND_FILL;note.add_child(login_hero)
	server_toggle = button(c.auth_box,"Server settings",func() -> void: server_options.visible = not server_options.visible)
	server_options = HBoxContainer.new(); server_options.add_theme_constant_override("separation",14); c.auth_box.add_child(server_options)
	c.host_field = field(server_options,"Server hostname or wss://…/ws"); c.host_field.text = "wss://eo.kcpd.top/ws"
	c.port_field = SpinBox.new(); c.port_field.min_value = 1; c.port_field.max_value = 65535; c.port_field.value = 8079; c.port_field.custom_minimum_size = Vector2(140,54); c.port_field.editable = false; server_options.add_child(c.port_field)
	c.host_field.text_changed.connect(func(value: String) -> void: c.port_field.editable = not (value.begins_with("ws://") or value.begins_with("wss://")))
	c.host_field.text_changed.connect(func(_value: String) -> void: credentials_edited())
	c.port_field.value_changed.connect(func(_value: float) -> void: credentials_edited())
	c.username_field.text_changed.connect(func(_value: String) -> void: credentials_edited())
	server_options.hide()
	# Selection is a sibling of the auth scroll, so all three cards share its height.
	c.character_box = VBoxContainer.new(); c.character_box.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.character_box.add_theme_constant_override("separation",14); body.add_child(c.character_box)
	c.character_list = ItemList.new(); c.character_list.hide(); c.character_box.add_child(c.character_list)
	c.character_list.item_selected.connect(c._select_character_card)
	c.character_cards = HBoxContainer.new(); c.character_cards.add_theme_constant_override("separation",18); c.character_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.character_box.add_child(c.character_cards)
	capacity = text(c.character_box,"0 / 3 characters",18,game.MUTED)
	selection_actions = HBoxContainer.new(); selection_actions.add_theme_constant_override("separation",16); c.character_box.add_child(selection_actions)
	create_button = button(selection_actions,"Create a new character…",open_creation)
	button(selection_actions,"Delete selected…",func() -> void: game.feature_ui.open("delete"))
	button(selection_actions,"Change password",func() -> void: game.feature_ui.open("password"))
	enter_button = button(selection_actions,"Enter selected character",c._enter_selected,true)
	c.character_box.visibility_changed.connect(func() -> void: scroll.visible = not c.character_box.visible; refresh())
	c.character_box.hide()
	c.status_label = text(body,"Connect to your world or create a new account.",18); c.status_label.custom_minimum_size.y = 28; c.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.panel.hide()
	build_creation(parent)

func open_creation() -> void:
	if c.entering_character or c.creating_character: return
	if c.selected_characters.size() >= MAX_CHARACTERS:
		c._set_status("This account already has all three character slots filled."); return
	c.character_name_field.text = ""
	c.creation_status.text = ""
	c.creation_panel.show(); c._update_creation_preview()

func build_creation(parent: Control) -> void:
	var parts: Array = page(parent); c.creation_panel = parts[0]; var body: VBoxContainer = parts[1]
	header(body,"Create your character",func() -> void: c.creation_panel.hide())
	text(body,"Choose your body, skin and hair. Tap the preview to turn.",19,game.MUTED)
	var columns: HBoxContainer = HBoxContainer.new(); columns.add_theme_constant_override("separation",32); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_child(columns)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; columns.add_child(scroll)
	var form: VBoxContainer = VBoxContainer.new(); form.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.add_theme_constant_override("separation",12); scroll.add_child(form)
	var name_row: HBoxContainer = HBoxContainer.new(); name_row.add_theme_constant_override("separation",12); form.add_child(name_row)
	text(name_row,"Name",18,game.MUTED).custom_minimum_size.x = 112
	c.character_name_field = field(name_row,"4–12 letters"); c.character_name_field.max_length = 12
	c.character_name_field.text_changed.connect(func(_value: String) -> void: refresh_creation())
	c.character_name_field.text_submitted.connect(func(_value: String) -> void:
		c.character_name_field.release_focus()
		if OS.has_feature("mobile"): DisplayServer.virtual_keyboard_hide()
	)
	var body_row: HBoxContainer = HBoxContainer.new(); body_row.add_theme_constant_override("separation",12); form.add_child(body_row)
	text(body_row,"Body",18,game.MUTED).custom_minimum_size.x = 112
	c.body_choice = OptionButton.new(); c.body_choice.add_item("Female",0); c.body_choice.add_item("Male",1); c.body_choice.select(1); c.body_choice.hide(); form.add_child(c.body_choice)
	var genders: HBoxContainer = HBoxContainer.new(); genders.add_theme_constant_override("separation",12); genders.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body_row.add_child(genders)
	for gender: int in range(2):
		var index: int = gender
		var option: Button = button(genders,"Female" if gender == 0 else "Male",func() -> void: c.body_choice.select(index); c._update_creation_preview())
		option.toggle_mode = true; gender_buttons.append(option)
	c.skin_choice = appearance_row(form,"Skin",["White","Tan","Pale","Orc"],0)
	var hairstyles: Array = []; var colors: Array = []
	for index: int in range(20): hairstyles.append("Style %d" % (index+1))
	for index: int in range(10): colors.append("Color %d" % (index+1))
	c.hair_choice = appearance_row(form,"Hair style",hairstyles,1)
	c.color_choice = appearance_row(form,"Hair color",colors,0)
	var preview_card: PanelContainer = PanelContainer.new(); preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; preview_card.add_theme_stylebox_override("panel",game._style(Color("0c2023"),Color("506c61"),16)); columns.add_child(preview_card)
	var preview_margin: MarginContainer = MarginContainer.new(); preview_card.add_child(preview_margin)
	for edge: String in ["left","right","top","bottom"]: preview_margin.add_theme_constant_override("margin_"+edge,20)
	var preview_content: VBoxContainer = VBoxContainer.new(); preview_content.add_theme_constant_override("separation",12); preview_margin.add_child(preview_content)
	text(preview_content,"YOUR CHARACTER",20,game.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.character_preview = preload("res://scripts/character_preview.gd").new(); c.character_preview.game = game; c.character_preview.zoom = 3.5; c.character_preview.fit_to_rect = true; c.character_preview.bottom_margin = 28; c.character_preview.custom_minimum_size = Vector2(220,220); c.character_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; preview_content.add_child(c.character_preview)
	var rotations: HBoxContainer = HBoxContainer.new(); rotations.add_theme_constant_override("separation",12); preview_content.add_child(rotations)
	button(rotations,"Turn left",func() -> void: c.character_preview.turn(-1))
	button(rotations,"Turn right",func() -> void: c.character_preview.turn(1))
	creation_hint = text(body,"Start with 1,000 Gold, peasant clothes, a Dagger, an Oak Shield and Heal Self.",17,game.MUTED); creation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.creation_status = text(body,"",18,game.GOLD); c.creation_status.custom_minimum_size.y = 26; c.creation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions: HBoxContainer = HBoxContainer.new(); actions.add_theme_constant_override("separation",16); body.add_child(actions)
	button(actions,"Back",func() -> void: c.creation_panel.hide())
	creation_submit = button(actions,"Create character",c._create_character,true)
	c.creation_panel.hide(); refresh_creation()

func appearance_row(parent: Control, label: String, values: Array, first_id: int) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new(); row.add_theme_constant_override("separation",10); parent.add_child(row)
	text(row,label,18,game.MUTED).custom_minimum_size.x = 112
	var choice: OptionButton = OptionButton.new()
	var previous: Button = button(row,"‹",func() -> void: cycle(choice,-1)); previous.custom_minimum_size.x = 58; previous.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for index: int in range(values.size()): choice.add_item(str(values[index]),first_id+index)
	choice.custom_minimum_size.y = 56; choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL; choice.add_theme_font_size_override("font_size",22); row.add_child(choice)
	var next: Button = button(row,"›",func() -> void: cycle(choice,1)); next.custom_minimum_size.x = 58; next.size_flags_horizontal = Control.SIZE_SHRINK_END
	choice.item_selected.connect(func(_index: int) -> void: c._update_creation_preview())
	return choice

func cycle(choice: OptionButton, offset: int) -> void:
	choice.select(posmod(choice.selected+offset,choice.item_count)); c._update_creation_preview()

func show_characters() -> void:
	for child: Node in c.character_cards.get_children(): c.character_cards.remove_child(child); child.queue_free()
	c.selection_previews.clear()
	for index: int in range(MAX_CHARACTERS):
		var slot: int = index
		var exists: bool = index < c.selected_characters.size()
		var control: Button = button(c.character_cards,"",func() -> void:
			if slot < c.selected_characters.size(): c.character_list.select(slot); c._select_character_card(slot)
			else: open_creation()
		)
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL; control.custom_minimum_size = Vector2(0,270)
		var inset: MarginContainer = MarginContainer.new(); control.add_child(inset); inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for edge: String in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+edge,18)
		var content: VBoxContainer = VBoxContainer.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE; inset.add_child(content)
		text(content,"CHARACTER %d" % (index+1),16,game.MUTED).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if exists:
			var character: Dictionary = c.selected_characters[index]
			var preview: Control = preload("res://scripts/character_preview.gd").new(); preview.game = game; preview.appearance = character.duplicate(true); preview.zoom = 2.8; preview.fit_to_rect = true; preview.bottom_margin = 14; preview.custom_minimum_size.y = 170; preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
			content.add_child(preview); preview.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.selection_previews.append(preview)
			var name: Label = text(content,str(character.get("name","Character")),24); name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; name.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var level: Label = text(content,"Level %d" % int(character.get("level",1)),19,game.MUTED); level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; level.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var selected: Label = text(content,"Tap to select",17,game.GOLD); selected.name = "Selection"; selected.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var empty: Label = text(content,"+",60,game.GOLD); empty.size_flags_vertical = Control.SIZE_EXPAND_FILL; empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var label: Label = text(content,"Create character",23); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text(content,"Empty slot",18,game.MUTED).mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()

func refresh() -> void:
	if heading == null or capacity == null: return
	var count: int = c.selected_characters.size()
	heading.get_parent().visible=c.character_box.visible
	subtitle.visible=c.character_box.visible
	heading.text = "Choose your character" if c.character_box.visible else "Aster Vale"
	(heading.get_parent().get_child(1) as Button).visible=c.character_box.visible
	subtitle.text = "Tap a character to see their look, then enter the world." if c.character_box.visible else "Log in or create an account to begin your adventure."
	capacity.text = "%d / %d characters · All slots filled" % [count,MAX_CHARACTERS] if count >= MAX_CHARACTERS else "%d / %d characters · Tap an empty slot to create another" % [count,MAX_CHARACTERS]
	create_button.visible = count < MAX_CHARACTERS
	enter_button.disabled = count == 0 or c.entering_character or c.creating_character
	create_button.disabled = c.entering_character or c.creating_character
	for control: Button in c.character_cards.get_children(): control.disabled = c.entering_character or c.creating_character
	enter_button.text = "Entering…" if c.entering_character else "Enter selected character"
	refresh_creation()

func refresh_creation() -> void:
	if creation_submit == null or c.body_choice == null: return
	for index: int in range(gender_buttons.size()): gender_buttons[index].set_pressed_no_signal(c.body_choice.get_selected_id()==index)
	var name: String = c.character_name_field.text.strip_edges().to_lower()
	creation_submit.disabled = name.length()<4 or name.length()>12 or not c._character_letters(name) or c.selected_characters.size()>=MAX_CHARACTERS or c.creating_character
	creation_submit.text = "Creating…" if c.creating_character else "Create character"

func restore_login() -> void:
	var saved: Dictionary=c.login_store.load_login()
	if saved.is_empty():return
	restoring_login=true
	c.host_field.text=str(saved.get("host","wss://eo.kcpd.top/ws"));c.port_field.value=int(saved.get("port",8079))
	c.username_field.text=str(saved.get("username",""));c.password_field.text=str(saved.get("password",""))
	restored_login={"host":saved.get("host",""),"port":saved.get("port",8079),"username":saved.get("username","")};restoring_login=false
	remember.set_pressed_no_signal(true);forget_button.show()
	automatic.set_pressed_no_signal(automatic_enabled())

func automatic_enabled() -> bool:
	var config: ConfigFile = ConfigFile.new()
	return config.load(options_path) == OK and bool(config.get_value("login","automatic",false))

func save_automatic_choice(enabled: bool) -> void:
	# Only the opt-in flag is stored here. Passwords remain in Android Keystore.
	var config: ConfigFile = ConfigFile.new(); config.set_value("login","automatic",enabled)
	if config.save(options_path) != OK: game._toast("Your automatic login choice could not be saved.")

func try_startup_login() -> void:
	if startup_login_checked: return
	startup_login_checked = true
	if not c.login_store.available() or not automatic_enabled() or c.active or c.session.connecting or c.session.connected: return
	var saved: Dictionary = c.login_store.load_login()
	if str(saved.get("password","")).is_empty() or str(saved.get("username","")).is_empty(): return
	# A manual edit before startup completes must never forward a saved password.
	if c.host_field.text.strip_edges() != str(saved.get("host","")) or int(c.port_field.value) != int(saved.get("port",0)) or c.username_field.text.strip_edges() != str(saved.username) or c.password_field.text != str(saved.password): return
	c._authenticate("login")

func credentials_edited() -> void:
	if restoring_login or restored_login.is_empty():return
	if c.host_field.text.strip_edges()!=str(restored_login.get("host","")) or int(c.port_field.value)!=int(restored_login.get("port",8079)) or c.username_field.text.strip_edges()!=str(restored_login.get("username","")):
		c.password_field.text="";remember.set_pressed_no_signal(false);restored_login.clear()
		automatic.set_pressed_no_signal(false)
