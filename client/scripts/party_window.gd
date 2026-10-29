extends RefCounted
var game: Node
var button: Control
var panel: Control
var members: ItemList
var nearby: ItemList
var notice: Label
var accept_button: Button
var decline_button: Button
var kick_button: Button
var leave_button: Button
var chat: LineEdit
var history: RichTextLabel
var party: Array = []
var invitation: Dictionary = {}
var seen_invitation: String = ""
var stamp: String = ""
var invitation_until: int = 0
func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	button = preload("res://scripts/hud_icon_button.gd").new()
	button.kind = "party"
	button.position = Vector2(-488, 24)
	button.size = Vector2(68, 68)
	button.pressed.connect(open)
	parent.add_child(button)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	panel = game._modal(parent, Vector2(860,620))
	var card: Control = panel.get_child(0)
	game._wood_card(card)
	game._label(card,"PARTY",Vector2(30,20),28,game.GOLD)
	game._button(card,"×",Vector2(778,16),Vector2(54,48),func() -> void: panel.hide())
	notice = game._label(card,"Invite a nearby player or ask to join their party.",Vector2(30,66),18,game.MUTED)
	notice.size = Vector2(800,56); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._label(card,"Members · level · HP",Vector2(30,124),18)
	game._label(card,"Nearby players",Vector2(438,124),18)
	members = ItemList.new(); members.position = Vector2(30,154); members.size = Vector2(390,170); card.add_child(members)
	nearby = ItemList.new(); nearby.position = Vector2(438,154); nearby.size = Vector2(392,170); card.add_child(nearby)
	for list: ItemList in [members,nearby]: list.add_theme_font_size_override("font_size",20)
	kick_button = game._button(card,"Remove selected",Vector2(30,336),Vector2(190,46),func() -> void: action("kick",selected(members)))
	leave_button = game._button(card,"Leave party",Vector2(230,336),Vector2(190,46),func() -> void: confirm_leave())
	game._button(card,"Invite",Vector2(438,336),Vector2(190,46),func() -> void: action("invite",selected(nearby)))
	game._button(card,"Ask to join",Vector2(638,336),Vector2(192,46),func() -> void: action("join",selected(nearby)))
	history = RichTextLabel.new(); history.position = Vector2(30,398); history.size = Vector2(800,102); history.bbcode_enabled = false; history.scroll_following = true; card.add_child(history)
	chat = LineEdit.new(); chat.position = Vector2(30,510); chat.size = Vector2(620,46); chat.placeholder_text = "Party message…"; chat.max_length = 128; card.add_child(chat)
	chat.text_submitted.connect(func(_text: String) -> void: send_chat())
	game._button(card,"Send",Vector2(664,510),Vector2(166,46),send_chat)
	accept_button = game._button(card,"Accept request",Vector2(30,568),Vector2(390,38),func() -> void: action("accept"))
	decline_button = game._button(card,"Decline",Vector2(438,568),Vector2(392,38),func() -> void: action("decline"))
	panel.hide()
func selected(list: ItemList) -> int:
	var choices: PackedInt32Array = list.get_selected_items()
	return int(list.get_item_metadata(choices[0])) if not choices.is_empty() else 0
func open() -> void:
	if not game.online.active: game.online.show_login(); return
	game.player_actions.close();game.menu.hide(); game.services_ui.panel.hide(); game.chat_ui.panel.hide()
	game._cancel_controls(); panel.show(); stamp = ""; refresh()
	game.online.session.request("party_refresh")
func action(kind: String, pid: int = 0) -> void:
	if kind in ["invite","join","kick"] and pid == 0: game._toast("Choose a player first."); return
	game.online.session.request("party_"+kind,{"player_id":pid})
func invite(pid: int) -> void:
	open(); action("invite",pid)
func confirm_leave() -> void:
	var leader: bool = false
	for member: Dictionary in party:
		if int(member.player_id) == int(game.online.player.get("player_id",-1)): leader = bool(member.leader)
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "Leaving as leader disbands this party. Continue?" if leader else "Leave this party?"
	game.add_child(dialog); dialog.confirmed.connect(func() -> void: action("leave"); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()
func send_chat() -> void:
	if chat.text.strip_edges().is_empty(): return
	game.online.session.request("chat_send",{"channel":"party","message":chat.text}); chat.clear(); chat.release_focus()
func receive(data: Dictionary) -> void:
	if data.has("party"): party = data.party as Array
	if data.has("party_invitation"): invitation = data.party_invitation as Dictionary if data.party_invitation is Dictionary else {}
	if data.has("party_notice"): notice.text = str(data.party_notice) if not str(data.party_notice).is_empty() else "Invite a nearby player or ask to join their party."
	var key: String = JSON.stringify(invitation)
	if not invitation.is_empty() and key != seen_invitation:
		invitation_until = Time.get_ticks_msec()+30000
		open()
	seen_invitation = key
	refresh()
func event(data: Dictionary) -> void:
	if data.get("kind") == "chat" and data.get("channel") == "party": history.append_text(str(data.get("name","Party"))+": "+str(data.get("message",""))+"\n")
func refresh() -> void:
	accept_button.visible = not invitation.is_empty(); decline_button.visible = accept_button.visible
	leave_button.disabled = party.is_empty(); chat.editable = not party.is_empty()
	kick_button.disabled = true
	var ids: Array = []
	for member: Dictionary in party:
		ids.append(int(member.player_id))
		if int(member.player_id) == int(game.online.player.get("player_id",-1)) and bool(member.leader): kick_button.disabled = false
	var rows: String = JSON.stringify([party,game.online.players])
	if rows == stamp: return
	stamp = rows
	var old_member: int = selected(members); var old_nearby: int = selected(nearby)
	members.clear(); nearby.clear()
	for member: Dictionary in party:
		var row: int = members.add_item(("★ " if bool(member.leader) else "")+str(member.name)+" · %d · %d%%" % [int(member.level),int(member.hp_percent)])
		members.set_item_metadata(row,int(member.player_id))
		if int(member.player_id) == old_member: members.select(row)
	for peer: Dictionary in game.online.players:
		var pid: int = int(peer.get("player_id",0))
		if pid == int(game.online.player.get("player_id",0)) or pid in ids: continue
		var row: int = nearby.add_item(str(peer.get("name","Player"))); nearby.set_item_metadata(row,pid)
		if pid == old_nearby: nearby.select(row)
func disconnected() -> void:
	party.clear(); invitation.clear(); seen_invitation = ""; panel.hide(); history.clear()

func tick() -> void:
	button.visible = game.started and game.online_mode and game.online.active and not game._modal_open()
	if not invitation.is_empty() and Time.get_ticks_msec() >= invitation_until:
		invitation.clear(); notice.text = "Party request expired."; refresh()
