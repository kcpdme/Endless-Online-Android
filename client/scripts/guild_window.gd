extends RefCounted
## Guild services and native invitations. Only server replies grant membership.
const PAGES: Array[String] = ["Look up", "Create", "Join", "Manage", "Requests", "Guild chat"]
var game: Node
var panel: Control
var title: Label
var query: LineEdit
var detail: RichTextLabel
var status: Label
var body: VBoxContainer
var scroll: ScrollContainer
var confirmation: ConfirmationDialog
var state: Dictionary = {}
var creation: Dictionary = {}
var invitation: Dictionary = {}
var requests: Array = []
var inputs: Dictionary = {}
var drafts: Dictionary = {}
var chat: Array[String] = []
var page: int = 0
var busy: bool = false
var stamp: String = ""
var notice: String = ""
var pending_op: String = ""
var pending_fields: Dictionary = {}

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(900, 650))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	title = game._label(card, "Guild Bob", Vector2(28, 18), 28, game.GOLD)
	game._button(card, "×", Vector2(818, 12), Vector2(54, 48), close)
	for index: int in range(PAGES.size()):
		var chosen: int = index
		game._button(card, PAGES[index], Vector2(28 + index * 142, 70), Vector2(136, 48), func() -> void: _remember(); page = chosen; refresh())
	scroll = ScrollContainer.new()
	scroll.position = Vector2(28, 134); scroll.size = Vector2(844, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12); scroll.add_child(body)
	status = game._label(card, "", Vector2(28, 570), 18, game.MUTED)
	status.size = Vector2(844, 64); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation = ConfirmationDialog.new(); confirmation.title = "Confirm guild action"
	confirmation.dialog_autowrap = true; confirmation.min_size = Vector2i(520, 220)
	confirmation.confirmed.connect(func() -> void: _send(pending_op, pending_fields))
	panel.add_child(confirmation)
	panel.hide()

func _remember() -> void:
	for key: String in inputs:
		var control: Control = inputs[key] as Control
		if is_instance_valid(control): drafts[key] = control.text

func _field(key: String, placeholder: String, maximum: int = 24, initial: String = "") -> LineEdit:
	var field: LineEdit = LineEdit.new(); field.placeholder_text = placeholder
	field.text = str(drafts.get(key, initial)); field.max_length = maximum
	field.custom_minimum_size = Vector2(800, 52); field.add_theme_font_size_override("font_size", 21)
	body.add_child(field); inputs[key] = field
	field.focus_entered.connect(func() -> void: scroll.ensure_control_visible(field))
	return field

func _text(key: String) -> String:
	return str(inputs[key].text).strip_edges() if inputs.has(key) else str(drafts.get(key, ""))

func _label(text: String) -> void:
	var label: Label = Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 21); body.add_child(label)

func _action(text: String, callback: Callable) -> Button:
	var button: Button = Button.new(); button.text = text; button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 21); button.disabled = busy
	button.pressed.connect(callback); body.add_child(button)
	return button

func _confirm(op: String, fields: Dictionary, text: String) -> void:
	if busy: return
	for control: Control in inputs.values(): control.release_focus()
	pending_op = op; pending_fields = fields.duplicate(true)
	confirmation.dialog_text = text; confirmation.popup_centered(Vector2i(560, 240))

func _send(op: String, fields: Dictionary = {}) -> void:
	if busy: return
	_remember()
	for control: Control in inputs.values(): control.release_focus()
	if game.online.session.request(op, fields) < 0:
		status.text = "Connection lost. Reconnect before retrying."
		return
	busy = true; status.text = "Waiting for the guild service…"
	for child: Node in body.get_children():
		if child is Button: child.disabled = true

func lookup(members: bool) -> void:
	var text: String = _text("query")
	if text.length() < 2: game._toast("Enter a guild tag or name first."); return
	_send("guild_members" if members else "guild_info", {"query": text})

func refresh() -> void:
	for child: Node in body.get_children(): body.remove_child(child); child.queue_free()
	inputs.clear()
	var settings: Dictionary = state.get("settings", {}) as Dictionary
	var member: Dictionary = state.get("membership", {}) as Dictionary if state.get("membership") is Dictionary else {}
	var price: int = int(settings.get("GuildPrice", 50000))
	var minimum: int = int(settings.get("GuildCreateMembers", 10))
	if page == 0:
		query = _field("query", "Guild tag or name", 24)
		_action("Guild information", func() -> void: lookup(false))
		_action("Member list", func() -> void: lookup(true))
		detail = RichTextLabel.new(); detail.custom_minimum_size.y = 230
		detail.add_theme_font_size_override("normal_font_size", 21); detail.bbcode_enabled = false; body.add_child(detail)
		var result: Dictionary = state.get("result", {}) as Dictionary
		if result.is_empty(): detail.text = "Look up a guild’s information or members by tag or name."
		elif result.has("members"):
			detail.text = "%s · Members: %d\n" % [str(result.query), (result.members as Array).size()]
			for row: Dictionary in result.members: detail.text += "\n%s · %s (rank %d)" % [str(row.name), str(row.title), int(row.rank)]
		else:
			detail.text = "%s [%s]\nFounded: %s\nGuild bank: %s Gold\n\n%s\n" % [str(result.name), str(result.tag), str(result.created), str(result.bank), str(result.description)]
			for row: Dictionary in result.get("leaders", []): detail.text += "\n%s · %s" % ["Leader" if int(row.role) == 1 else "Recruiter", str(row.name)]
	elif page == 1:
		_label("Founding requires %d Gold and %d members, including you. Nearby guildless players receive an invitation; Gold is charged only when the guild is created." % [price, minimum])
		if not creation.is_empty():
			_label("%s [%s] · %d supporters\n%s" % [str(creation.name), str(creation.tag), (creation.members as Array).size(), ", ".join(creation.members)])
			_field("create_description", "Description (letters, numbers, spaces, @ _ - .)", 240)
			var finish: Button = _action("Found guild · %d Gold" % price, func() -> void: _confirm("guild_found", {"description":_text("create_description")}, "Create this guild for %d Gold?" % price))
			finish.disabled = busy or not bool(creation.get("ready", false))
			if not bool(creation.get("ready", false)): _label("Waiting for the server to confirm enough founding members. You can close this window while waiting.")
		else:
			_field("create_tag", "Guild tag · 2–3 letters", 3)
			_field("create_name", "Guild name · 4–24 letters/spaces", 24)
			_action("Invite founding members", func() -> void: _send("guild_begin", {"tag":_text("create_tag"),"name":_text("create_name")}))
	elif page == 2:
		_label("Ask an authorised recruiter on this map to accept you. Recruiting costs the guild bank %d Gold." % int(settings.get("RecruitCost", 1000)))
		_field("join_tag", "Guild tag · 2–3 letters", 3)
		_field("recruiter", "Recruiter’s character name", 12)
		_action("Request membership", func() -> void: _send("guild_join", {"tag":_text("join_tag"),"recruiter":_text("recruiter")}))
	elif page == 3:
		_action("Refresh my membership", func() -> void: _send("guild_refresh"))
		if member.is_empty(): _label("You do not currently belong to a guild.")
		else:
			_label("%s [%s] · %s (rank %d)\nGuild bank: %d Gold" % [str(member.guild_name), str(member.tag), str(member.title), int(member.rank), int(member.bank)])
			_field("deposit", "Gold deposit · minimum %d" % int(settings.get("GuildMinDeposit", 1000)), 10)
			_action("Deposit Gold", func() -> void: _confirm("guild_deposit", {"amount":_text("deposit").to_int()}, "Deposit %s Gold into the guild bank?" % _text("deposit")))
			var rank: int = int(member.rank)
			if rank <= int(settings.get("GuildEditRank", 1)):
				_field("description", "Guild description", 240, str(member.description))
				_action("Save description", func() -> void: _send("guild_description", {"description":_text("description")}))
				_label("Rank names · rank 1 through 9 (empty names are allowed)")
				for number: int in range(1, 10): _field("rank_%d" % number, "Rank %d" % number, 16, str((member.ranks as Array)[number - 1]))
				_action("Save rank names", func() -> void:
					var names: PackedStringArray = []
					for number: int in range(1, 10): names.append(_text("rank_%d" % number))
					_send("guild_ranks", {"ranks": ",".join(names)})
				)
			if rank <= maxi(int(settings.get("GuildPromoteRank", 1)), maxi(int(settings.get("GuildDemoteRank", 1)), int(settings.get("GuildKickRank", 1)))):
				_field("member_name", "Member’s character name", 12)
				_field("member_rank", "New rank · 0 founder, 1 leader … 9 member", 1)
				_action("Change member rank", func() -> void: _confirm("guild_rank", {"name":_text("member_name"),"rank":_text("member_rank").to_int()}, "Change %s to rank %s? Rank 0 grants founder authority." % [_text("member_name"), _text("member_rank")]))
				if rank <= int(settings.get("GuildKickRank", 1)): _action("Remove member", func() -> void: _confirm("guild_kick", {"name":_text("member_name")}, "Remove %s from your guild?" % _text("member_name")))
			_action("Leave guild", func() -> void: _confirm("guild_leave", {}, "Leave %s? You will need a recruiter to join again." % str(member.guild_name)))
			if rank <= int(settings.get("GuildDisbandRank", 0)): _action("Disband guild", func() -> void: _confirm("guild_disband", {}, "Disband %s and remove every member? This cannot be undone." % str(member.guild_name)))
	elif page == 4:
		if invitation.is_empty() and requests.is_empty(): _label("No founding invitations or membership requests.")
		if not invitation.is_empty():
			_label("Support the creation of %s? Membership begins when its founder completes creation." % str(invitation.display))
			_action("Support founding", func() -> void: _send("guild_support", {"accept":true}))
			_action("Dismiss invitation", func() -> void: _send("guild_support", {"accept":false}))
		for row: Dictionary in requests:
			var pid: int = int(row.player_id)
			_label("%s wants to join your guild." % str(row.name))
			_action("Accept %s" % str(row.name), func() -> void: _confirm("guild_recruit", {"player_id":pid,"accept":true}, "Accept this applicant? The guild bank pays the recruitment cost."))
			_action("Dismiss %s" % str(row.name), func() -> void: _send("guild_recruit", {"player_id":pid,"accept":false}))
	else:
		_label("\n".join(chat.slice(maxi(0, chat.size() - 30))))
		_field("message", "Message your guild", 128)
		_action("Send to guild", func() -> void: _send("guild_chat", {"message":_text("message")}))
	if page in [0,1,2,3] and state.is_empty():
		_label("Talk to a nearby Guild Bob to use these services.")
		for child: Node in body.get_children():
			if child is Button: child.disabled = true
	status.text = notice

func receive(data: Dictionary) -> void:
	var incoming: bool = false
	var changed: bool = false
	if data.has("guild"):
		state = (data.guild as Dictionary).duplicate(true) if data.guild is Dictionary else {}
		if not state.is_empty(): changed = true
		elif panel.visible and page not in [4,5] and not busy: panel.hide()
	if data.has("guild_creation"): creation = (data.guild_creation as Dictionary).duplicate(true) if data.guild_creation is Dictionary else {}
	if data.has("guild_invitation"):
		var next: Dictionary = data.guild_invitation as Dictionary if data.guild_invitation is Dictionary else {}
		incoming = not next.is_empty() and next != invitation
		invitation = next.duplicate(true)
	if data.has("guild_requests"):
		var next: Array = data.guild_requests as Array
		incoming = incoming or (next.size() > requests.size())
		requests = next.duplicate(true)
	if data.has("guild_notice"):
		var next_notice: String = str(data.guild_notice)
		if next_notice != notice and not next_notice.is_empty() and not panel.visible: game._toast(next_notice)
		notice = next_notice
	for event: Dictionary in data.get("events", []):
		if str(event.get("kind", "")) == "chat" and str(event.get("channel", "")) == "guild":
			chat.append("%s: %s" % [str(event.get("name", "")), str(event.get("message", ""))])
			if chat.size() > 100: chat.pop_front()
	if incoming: _remember(); page = 4
	var next_stamp: String = JSON.stringify([state,creation,invitation,requests,notice,chat,page,busy])
	if next_stamp != stamp:
		_remember(); refresh(); stamp = next_stamp
	if changed or incoming:
		game._cancel_controls(); game.shop_ui.close(); game.services_ui.panel.hide()
		game.quest_ui.panel.hide(); game.inn_ui.panel.hide(); game.inventory.hide()
		game.character_panel.hide(); game.stats_ui.dismiss(); game.skills_ui.panel.hide()
		title.text = str(((game.online.catalog.get("npcs", {}) as Dictionary).get(str(int(state.get("npc_id", 46))), {}) as Dictionary).get("name", "Guild services"))
		panel.show()

func response(message: Dictionary) -> void:
	var op: String = str(message.get("op", ""))
	if not op.begins_with("guild_"): return
	busy = false
	_remember()
	if not bool(message.get("ok", true)):
		notice = str(message.get("error", "Guild action declined"))
	elif op == "guild_chat": drafts["message"] = ""
	refresh()
	stamp = ""

func tick() -> void:
	if not panel.visible: return
	var keyboard: float = float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	var viewport: Vector2 = game.get_viewport_rect().size
	var lift: float = clampf(keyboard * viewport.y / maxf(1.0, DisplayServer.window_get_size().y), 0, viewport.y * 0.6)
	layout(lift)

func layout(lift: float) -> void:
	var height: float = clampf(game.get_viewport_rect().size.y - lift - 24, 280, 650)
	var card: Control = panel.get_child(0) as Control
	card.size = Vector2(900, height)
	card.position = Vector2(-450, -height / 2.0 - lift / 2.0)
	scroll.size.y = maxf(52, height - 228)
	status.position.y = height - 78
	var focus: Control = game.get_viewport().gui_get_focus_owner()
	if focus != null and body.is_ancestor_of(focus): scroll.ensure_control_visible(focus)

func close() -> void:
	_remember()
	for control: Control in inputs.values(): control.release_focus()
	confirmation.hide()
	game.online.session.request("guild_close")
	state.clear(); panel.hide()

func disconnected() -> void:
	state.clear(); creation.clear(); invitation.clear(); requests.clear(); inputs.clear(); drafts.clear(); chat.clear()
	busy = false; notice = ""; stamp = ""; confirmation.hide(); panel.hide()
